`timescale 1ns / 1ps

// FSM test case 4: STATE_CRITICAL entry, retries, then lockout at max_retry
module tb_fsm_4;

    // clock and reset
    logic clk;
    logic reset_n;

    // dut inputs
    logic boot_success;
    logic mcu_heartbeat;
    logic battery_low;
    logic battery_critical;
    logic warning_request;
    logic shutdown_request;
    logic critical_request;
    logic manual_power;
    logic manual_shutdown;
    logic shutdown_success;

    // dut outputs
    logic system_enable;
    logic warning_led;
    logic critical_clear;
    logic buzzer_alert;
    logic recovery_mode;
    logic [6:0] state_debug_bus;

    // one-hot state codes, must match power_state_machine
    localparam logic [6:0] STATE_OFF      = 7'b0000001;
    localparam logic [6:0] STATE_BOOT     = 7'b0000010;
    localparam logic [6:0] STATE_NORMAL   = 7'b0000100;
    localparam logic [6:0] STATE_CRITICAL = 7'b0010000;

    // 20 ns clock period, 50 MHz
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // device under test
    power_state_machine dut (
        .boot_success      (boot_success),
        .mcu_heartbeat     (mcu_heartbeat),
        .battery_low       (battery_low),
        .battery_critical  (battery_critical),
        .warning_request   (warning_request),
        .shutdown_request  (shutdown_request),
        .critical_request  (critical_request),
        .manual_power      (manual_power),
        .manual_shutdown   (manual_shutdown),
        .shutdown_success  (shutdown_success),
        .reset_n           (reset_n),
        .clk               (clk),
        .system_enable     (system_enable),
        .warning_led       (warning_led),
        .critical_clear    (critical_clear),
        .buzzer_alert      (buzzer_alert),
        .recovery_mode     (recovery_mode),
        .state_debug_bus   (state_debug_bus)
    );

    // pulse the power button for one press
    task automatic press_power();
        manual_power = 1'b1;
        repeat (2) @(posedge clk);
        manual_power = 1'b0;
    endtask

    // pulse a critical fault report from the FEE
    task automatic report_critical_fault();
        critical_request = 1'b1;
        @(posedge clk);
        critical_request = 1'b0;
    endtask

    initial begin
        // default every input low
        reset_n          = 1'b0;
        boot_success     = 1'b0;
        mcu_heartbeat    = 1'b0;
        battery_low      = 1'b0;
        battery_critical = 1'b0;
        warning_request  = 1'b0;
        shutdown_request = 1'b0;
        critical_request = 1'b0;
        manual_power     = 1'b0;
        manual_shutdown  = 1'b0;
        shutdown_success = 1'b0;

        // hold reset for a few cycles
        repeat (3) @(posedge clk);

        // release reset
        reset_n = 1'b1;
        @(posedge clk);

        // boot up to STATE_NORMAL
        press_power();
        wait (state_debug_bus == STATE_BOOT);
        repeat (5) begin
            @(posedge clk);
            mcu_heartbeat = ~mcu_heartbeat;
        end
        boot_success = 1'b1;
        wait (state_debug_bus == STATE_NORMAL);
        boot_success = 1'b0;

        // a critical fault is reported
        report_critical_fault();
        wait (state_debug_bus == STATE_CRITICAL);
        $display("[%0t] entered STATE_CRITICAL, retry_count=%0d", $time, dut.retry_count);
        assert (system_enable == 1'b0) else $error("system_enable not low in STATE_CRITICAL");
        assert (buzzer_alert == 1'b1) else $error("buzzer_alert not high in STATE_CRITICAL");

        // retry #1, and prove a fresh heartbeat does not bounce it back
        press_power();
        wait (state_debug_bus == STATE_BOOT);
        assert (dut.retry_count == 2'd1) else $error("retry_count not 1 after first retry");
        repeat (3) begin
            @(posedge clk);
            mcu_heartbeat = ~mcu_heartbeat;
        end
        assert (state_debug_bus == STATE_BOOT) else $error("bounced back to STATE_CRITICAL after a fresh heartbeat");
        report_critical_fault();
        wait (state_debug_bus == STATE_CRITICAL);

        // retry #2
        press_power();
        wait (state_debug_bus == STATE_BOOT);
        assert (dut.retry_count == 2'd2) else $error("retry_count not 2 after second retry");
        report_critical_fault();
        wait (state_debug_bus == STATE_CRITICAL);

        // retry #3, retry_count now reaches max_retry
        press_power();
        wait (state_debug_bus == STATE_BOOT);
        assert (dut.retry_count == 2'd3) else $error("retry_count not 3 after third retry");
        report_critical_fault();
        wait (state_debug_bus == STATE_CRITICAL);
        $display("[%0t] retry budget spent, retry_count=%0d", $time, dut.retry_count);

        // retry #4 should be refused
        press_power();
        repeat (5) @(posedge clk);
        assert (state_debug_bus == STATE_CRITICAL) else $error("a retry was granted past max_retry");
        $display("[%0t] retry correctly refused, still locked in STATE_CRITICAL", $time);

        // only reset_n clears the lockout
        reset_n = 1'b0;
        repeat (2) @(posedge clk);
        assert (state_debug_bus == STATE_OFF) else $error("did not reset back to STATE_OFF");
        assert (dut.retry_count == 2'd0) else $error("retry_count not cleared by reset_n");
        $display("[%0t] reset_n cleared the lockout, test passed", $time);

        $finish;
    end

endmodule
