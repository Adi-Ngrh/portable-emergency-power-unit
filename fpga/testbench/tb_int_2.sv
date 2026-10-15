`timescale 1ns / 1ps

// Integration test case 2: critical fault overrides a pending warning fault, retries run out and lock the FSM, only reset_n releases it
module tb_int_2;

    // clock and reset
    logic clk;
    logic reset_n;

    // top inputs, FSM side
    logic boot_success;
    logic mcu_heartbeat;
    logic battery_low;
    logic battery_critical;
    logic manual_power;
    logic manual_shutdown;
    logic shutdown_success;

    // top inputs, FEE side
    logic overcurrent;
    logic overvoltage;
    logic undervoltage;
    logic overtemperature;
    logic fan_failure;
    logic sensor_failure;
    logic communication_timeout;

    // top outputs, FSM side
    logic system_enable;
    logic warning_led;
    logic buzzer_alert;
    logic recovery_mode;
    logic [6:0] state_debug_bus;

    // top outputs, FEE side
    logic shutdown_response;
    logic warning_response;
    logic critical_response;
    logic [2:0] fault_code_bus;
    logic [1:0] buzzer_pattern;

    // one-hot state codes, must match power_state_machine
    localparam logic [6:0] STATE_OFF      = 7'b0000001;
    localparam logic [6:0] STATE_BOOT     = 7'b0000010;
    localparam logic [6:0] STATE_NORMAL   = 7'b0000100;
    localparam logic [6:0] STATE_WARNING  = 7'b0001000;
    localparam logic [6:0] STATE_CRITICAL = 7'b0010000;

    // fault_code_bus codes, must match fault_event_engine
    localparam logic [2:0] CODE_DEFAULT       = 3'b000;
    localparam logic [2:0] CODE_OVERCURRENT   = 3'b001;
    localparam logic [2:0] CODE_UNDERVOLTAGE  = 3'b101;

    // buzzer_pattern codes, must match fault_event_engine
    localparam logic [1:0] PATTERN_DEFAULT  = 2'b00;
    localparam logic [1:0] PATTERN_WARNING  = 2'b01;
    localparam logic [1:0] PATTERN_CRITICAL = 2'b11;

    // 20 ns clock period, 50 MHz
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // device under test
    portable_emergency_power_unit dut (
        .clk                    (clk),
        .reset_n                (reset_n),
        .boot_success           (boot_success),
        .mcu_heartbeat          (mcu_heartbeat),
        .battery_low            (battery_low),
        .battery_critical       (battery_critical),
        .manual_power           (manual_power),
        .manual_shutdown        (manual_shutdown),
        .shutdown_success       (shutdown_success),
        .system_enable          (system_enable),
        .warning_led            (warning_led),
        .buzzer_alert           (buzzer_alert),
        .recovery_mode          (recovery_mode),
        .state_debug_bus        (state_debug_bus),
        .overcurrent            (overcurrent),
        .overvoltage            (overvoltage),
        .undervoltage           (undervoltage),
        .overtemperature        (overtemperature),
        .fan_failure            (fan_failure),
        .sensor_failure         (sensor_failure),
        .communication_timeout  (communication_timeout),
        .shutdown_response      (shutdown_response),
        .warning_response       (warning_response),
        .critical_response      (critical_response),
        .fault_code_bus         (fault_code_bus),
        .buzzer_pattern         (buzzer_pattern)
    );

    // error counter for the PASS/FAIL summary
    int error_count = 0;

    // count the critical_clear pulses the FSM sends to the FEE
    int clear_pulses = 0;
    always @(posedge clk) if (dut.fsm_critical_clear) clear_pulses++;

    // count and report a failed check
    task automatic check(input bit ok, input string msg);
        if (!ok) begin
            error_count++;
            $error("%s", msg);
        end
    endtask

    // pulse the power button for one press, non-blocking so the DUT samples the old value at the edge
    task automatic press_power();
        manual_power <= 1'b1;
        repeat (2) @(posedge clk);
        manual_power <= 1'b0;
    endtask

    // boot from STATE_OFF up to STATE_NORMAL
    task automatic boot_to_normal();
        press_power();
        wait (state_debug_bus == STATE_BOOT);
        repeat (5) begin
            @(posedge clk);
            mcu_heartbeat <= ~mcu_heartbeat;
        end
        boot_success <= 1'b1;
        wait (state_debug_bus == STATE_NORMAL);
        boot_success <= 1'b0;
    endtask

    // press the button once while locked in or retrying out of STATE_CRITICAL, then wait for the FSM to settle back
    task automatic retry_press(input int expected_count);
        press_power();
        wait (state_debug_bus == STATE_BOOT);
        check(dut.u_fsm.retry_count == expected_count, "retry_count did not follow the retry press");
        wait (state_debug_bus == STATE_CRITICAL);
        check(clear_pulses == expected_count, "critical_clear pulse count does not match the retry count");
        check(critical_response == 1'b1, "critical_response cleared while the critical fault is still present");
        check(system_enable == 1'b0, "system_enable high after bouncing back to STATE_CRITICAL");
        $display("[%0t] retry #%0d bounced back to STATE_CRITICAL, retry_count=%0d", $time, expected_count, dut.u_fsm.retry_count);
        repeat (3) @(posedge clk);
    endtask

    // watchdog so a stuck wait cannot hang the run
    initial begin
        #20_000_000;
        $display("[%0t] FAIL: watchdog timeout, a wait never completed", $time);
        $finish;
    end

    initial begin
        // default every input low
        reset_n               = 1'b0;
        boot_success          = 1'b0;
        mcu_heartbeat         = 1'b0;
        battery_low           = 1'b0;
        battery_critical      = 1'b0;
        manual_power          = 1'b0;
        manual_shutdown       = 1'b0;
        shutdown_success      = 1'b0;
        overcurrent           = 1'b0;
        overvoltage           = 1'b0;
        undervoltage          = 1'b0;
        overtemperature       = 1'b0;
        fan_failure           = 1'b0;
        sensor_failure        = 1'b0;
        communication_timeout = 1'b0;

        // hold reset for a few cycles
        repeat (3) @(posedge clk);

        // release reset
        reset_n <= 1'b1;
        @(posedge clk);

        // boot up to STATE_NORMAL
        boot_to_normal();
        repeat (3) @(posedge clk);
        check(state_debug_bus == STATE_NORMAL, "not in STATE_NORMAL before the faults");
        check(system_enable == 1'b1, "system_enable not high in STATE_NORMAL");
        $display("[%0t] entered STATE_NORMAL, no fault active", $time);

        // warning-class fault starts its 50,000 cycle debounce, then a critical fault arrives 10 cycles later
        undervoltage <= 1'b1;
        repeat (10) @(posedge clk);
        overcurrent <= 1'b1;

        // the critical fault validates first and must take the FSM to STATE_CRITICAL
        wait (critical_response == 1'b1);
        wait (state_debug_bus == STATE_CRITICAL);
        @(posedge clk);
        $display("[%0t] entered STATE_CRITICAL while the warning fault is still debouncing", $time);
        check(warning_response == 1'b0, "warning_response already set, the critical fault did not come first");
        check(system_enable == 1'b0, "system_enable not low in STATE_CRITICAL");
        check(buzzer_alert == 1'b1, "buzzer_alert not high in STATE_CRITICAL");
        check(fault_code_bus == CODE_OVERCURRENT, "fault_code_bus did not report overcurrent");
        check(buzzer_pattern == PATTERN_CRITICAL, "buzzer_pattern not PATTERN_CRITICAL");

        // the warning fault validates while critical is active, critical must stay in charge
        wait (warning_response == 1'b1);
        repeat (5) @(posedge clk);
        $display("[%0t] warning fault validated, FSM must stay in STATE_CRITICAL", $time);
        check(state_debug_bus == STATE_CRITICAL, "the warning fault pulled the FSM out of STATE_CRITICAL");
        check(fault_code_bus == CODE_OVERCURRENT, "fault_code_bus lost the higher priority overcurrent code");
        check(buzzer_pattern == PATTERN_CRITICAL, "buzzer_pattern lost PATTERN_CRITICAL");
        check(critical_response == 1'b1, "critical_response dropped");
        check(system_enable == 1'b0, "system_enable went high while critical");

        // the user presses power 3 times, each retry bounces back because the critical fault is still there
        retry_press(1);
        retry_press(2);
        retry_press(3);
        $display("[%0t] retry budget spent, retry_count=%0d", $time, dut.u_fsm.retry_count);

        // a 4th press must be refused
        press_power();
        repeat (6) @(posedge clk);
        check(state_debug_bus == STATE_CRITICAL, "a retry was granted past max_retry");
        check(dut.u_fsm.retry_count == 2'd3, "retry_count moved past max_retry");
        check(clear_pulses == 3, "a critical_clear pulse was sent past max_retry");
        $display("[%0t] 4th press refused, FSM locked in STATE_CRITICAL", $time);

        // the critical fault goes away, the live fault code follows but the latch needs a critical_clear
        overcurrent <= 1'b0;
        repeat (8) @(posedge clk);
        check(fault_code_bus == CODE_UNDERVOLTAGE, "fault_code_bus did not fall back to undervoltage");
        check(buzzer_pattern == PATTERN_WARNING, "buzzer_pattern did not fall back to PATTERN_WARNING");
        check(critical_response == 1'b1, "critical_response cleared without a critical_clear");
        check(state_debug_bus == STATE_CRITICAL, "FSM left STATE_CRITICAL without a retry");
        $display("[%0t] critical fault removed, critical_response still latched", $time);

        // retry budget is spent, so another press is still refused even with the fault gone
        press_power();
        repeat (6) @(posedge clk);
        check(state_debug_bus == STATE_CRITICAL, "FSM left the lockout without reset_n");
        check(clear_pulses == 3, "a critical_clear pulse was sent past max_retry");
        $display("[%0t] press refused with the fault gone, only reset_n releases the lockout", $time);

        // reset_n releases the lockout and the FEE latch
        reset_n <= 1'b0;
        repeat (2) @(posedge clk);
        check(state_debug_bus == STATE_OFF, "reset_n did not return the FSM to STATE_OFF");
        check(dut.u_fsm.retry_count == 2'd0, "retry_count not cleared by reset_n");
        check(critical_response == 1'b0, "critical_response not cleared by reset_n");
        check(warning_response == 1'b0, "warning_response not cleared by reset_n");
        reset_n <= 1'b1;
        @(posedge clk);

        // the user can turn the system on again
        boot_to_normal();
        repeat (3) @(posedge clk);
        check(state_debug_bus == STATE_NORMAL, "did not reach STATE_NORMAL after reset_n");
        check(system_enable == 1'b1, "system_enable not high in STATE_NORMAL after reset_n");
        check(critical_response == 1'b0, "critical_response high after the critical fault is gone");
        $display("[%0t] system turned on again after reset_n", $time);

        // the undervoltage fault is still held, so the FEE must recognize it again and the FSM must go to STATE_WARNING
        wait (warning_response == 1'b1);
        wait (state_debug_bus == STATE_WARNING);
        @(posedge clk);
        check(warning_led == 1'b1, "warning_led not high in STATE_WARNING");
        check(system_enable == 1'b1, "system_enable dropped in STATE_WARNING");
        check(fault_code_bus == CODE_UNDERVOLTAGE, "fault_code_bus did not report undervoltage");
        check(critical_response == 1'b0, "critical_response came back");
        $display("[%0t] held undervoltage recognized again, entered STATE_WARNING", $time);

        if (error_count == 0) $display("[%0t] PASS: critical priority, retry lockout and reset_n recovery handled correctly", $time);
        else                  $display("[%0t] FAIL: %0d check(s) failed", $time, error_count);

        $finish;
    end

endmodule
