`timescale 1ns / 1ps

// Integration test case 1: warning fault followed by a shutdown fault, FSM must follow NORMAL -> WARNING -> SHUTDOWN -> OFF
module tb_int_1;

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
    localparam logic [6:0] STATE_SHUTDOWN = 7'b0100000;

    // fault_code_bus codes, must match fault_event_engine
    localparam logic [2:0] CODE_DEFAULT         = 3'b000;
    localparam logic [2:0] CODE_OVERTEMPERATURE = 3'b011;
    localparam logic [2:0] CODE_UNDERVOLTAGE    = 3'b101;

    // buzzer_pattern codes, must match fault_event_engine
    localparam logic [1:0] PATTERN_DEFAULT  = 2'b00;
    localparam logic [1:0] PATTERN_WARNING  = 2'b01;
    localparam logic [1:0] PATTERN_SHUTDOWN = 2'b10;

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

    // watchdog so a stuck wait cannot hang the run
    initial begin
        #10_000_000;
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
        press_power();
        wait (state_debug_bus == STATE_BOOT);
        repeat (5) begin
            @(posedge clk);
            mcu_heartbeat <= ~mcu_heartbeat;
        end
        boot_success <= 1'b1;
        wait (state_debug_bus == STATE_NORMAL);
        boot_success <= 1'b0;
        repeat (3) @(posedge clk);
        check(system_enable == 1'b1, "system_enable not high in STATE_NORMAL");
        check(warning_led == 1'b0, "warning_led high before any fault");
        check(warning_response == 1'b0 && shutdown_response == 1'b0 && critical_response == 1'b0, "a FEE response is high before any fault");
        $display("[%0t] entered STATE_NORMAL, no fault active", $time);

        // warning-class fault, the real 50,000 cycle debounce runs, nothing is forced
        undervoltage <= 1'b1;
        wait (warning_response == 1'b1);
        wait (state_debug_bus == STATE_WARNING);
        @(posedge clk);
        $display("[%0t] entered STATE_WARNING via undervoltage", $time);
        check(warning_led == 1'b1, "warning_led not high in STATE_WARNING");
        check(system_enable == 1'b1, "system_enable dropped in STATE_WARNING");
        check(fault_code_bus == CODE_UNDERVOLTAGE, "fault_code_bus did not report undervoltage");
        check(buzzer_pattern == PATTERN_WARNING, "buzzer_pattern not PATTERN_WARNING");
        check(shutdown_response == 1'b0, "shutdown_response high with only a warning fault");
        check(critical_response == 1'b0, "critical_response high with only a warning fault");

        // the warning alone must not escalate
        repeat (5) @(posedge clk);
        check(state_debug_bus == STATE_WARNING, "left STATE_WARNING without a new fault");

        // shutdown-class fault arrives while the warning fault is still held
        overtemperature <= 1'b1;
        wait (shutdown_response == 1'b1);
        @(posedge clk);
        check(fault_code_bus == CODE_OVERTEMPERATURE, "fault_code_bus did not switch to overtemperature");
        check(buzzer_pattern == PATTERN_SHUTDOWN, "buzzer_pattern not PATTERN_SHUTDOWN");
        check(warning_response == 1'b1, "warning_response dropped while undervoltage is still held");
        wait (state_debug_bus == STATE_SHUTDOWN);
        @(posedge clk);
        $display("[%0t] entered STATE_SHUTDOWN via overtemperature", $time);
        check(warning_led == 1'b0, "warning_led still high in STATE_SHUTDOWN");
        check(system_enable == 1'b1, "system_enable dropped before the shutdown finished");
        check(buzzer_alert == 1'b0, "buzzer_alert high outside STATE_CRITICAL");

        // MCU reports the shutdown is done
        repeat (3) @(posedge clk);
        shutdown_success <= 1'b1;
        @(posedge clk);
        shutdown_success <= 1'b0;
        wait (state_debug_bus == STATE_OFF);
        @(posedge clk);
        check(system_enable == 1'b0, "system_enable still high in STATE_OFF");
        $display("[%0t] shutdown_success took the FSM to STATE_OFF", $time);

        // release both faults, the FEE must clear and the FSM must stay off
        undervoltage    <= 1'b0;
        overtemperature <= 1'b0;
        repeat (8) @(posedge clk);
        check(warning_response == 1'b0, "warning_response did not clear");
        check(shutdown_response == 1'b0, "shutdown_response did not clear");
        check(fault_code_bus == CODE_DEFAULT, "fault_code_bus did not return to default");
        check(buzzer_pattern == PATTERN_DEFAULT, "buzzer_pattern did not return to default");
        check(state_debug_bus == STATE_OFF, "FSM left STATE_OFF without a power press");

        if (error_count == 0) $display("[%0t] PASS: warning then shutdown fault handled correctly", $time);
        else                  $display("[%0t] FAIL: %0d check(s) failed", $time, error_count);

        $finish;
    end

endmodule
