`timescale 1ns / 1ps

// FSM test case 5: battery critical, graceful shutdown into STATE_RECOVERY, then back to STATE_NORMAL
module tb_fsm_5;

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
    logic shutdown_ack;
    logic critical_clear;
    logic buzzer_alert;
    logic recovery_mode;
    logic [6:0] state_debug_bus;

    // one-hot state codes, must match power_state_machine
    localparam logic [6:0] STATE_OFF      = 7'b0000001;
    localparam logic [6:0] STATE_BOOT     = 7'b0000010;
    localparam logic [6:0] STATE_NORMAL   = 7'b0000100;
    localparam logic [6:0] STATE_SHUTDOWN = 7'b0100000;
    localparam logic [6:0] STATE_RECOVERY = 7'b1000000;

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
        .shutdown_ack      (shutdown_ack),
        .critical_clear    (critical_clear),
        .buzzer_alert      (buzzer_alert),
        .recovery_mode     (recovery_mode),
        .state_debug_bus   (state_debug_bus)
    );

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
        manual_power = 1'b1;
        repeat (2) @(posedge clk);
        manual_power = 1'b0;
        wait (state_debug_bus == STATE_BOOT);
        repeat (5) begin
            @(posedge clk);
            mcu_heartbeat = ~mcu_heartbeat;
        end
        boot_success = 1'b1;
        wait (state_debug_bus == STATE_NORMAL);
        boot_success = 1'b0;
        $display("[%0t] entered STATE_NORMAL", $time);

        // battery becomes critical
        battery_critical = 1'b1;

        // wait for the FSM to reach STATE_SHUTDOWN
        wait (state_debug_bus == STATE_SHUTDOWN);
        $display("[%0t] entered STATE_SHUTDOWN, battery_fault_latch=%0b", $time, dut.battery_fault_latch);
        assert (dut.battery_fault_latch == 1'b1) else $error("battery_fault_latch not set for a battery-caused shutdown");

        // MCU finishes powering down its own loads
        repeat (2) @(posedge clk);
        shutdown_success = 1'b1;
        repeat (2) @(posedge clk);
        shutdown_success = 1'b0;

        // battery_fault_latch routes this to STATE_RECOVERY, not STATE_OFF
        wait (state_debug_bus == STATE_RECOVERY);
        $display("[%0t] entered STATE_RECOVERY", $time);
        assert (recovery_mode == 1'b1) else $error("recovery_mode not high in STATE_RECOVERY");
        assert (system_enable == 1'b0) else $error("system_enable not low in STATE_RECOVERY");

        // battery recovers
        repeat (3) @(posedge clk);
        battery_critical = 1'b0;

        // STATE_RECOVERY exits back through STATE_BOOT, not straight to STATE_NORMAL
        wait (state_debug_bus == STATE_BOOT);
        $display("[%0t] left STATE_RECOVERY into STATE_BOOT", $time);

        // MCU reports a successful boot again
        boot_success = 1'b1;
        wait (state_debug_bus == STATE_NORMAL);
        boot_success = 1'b0;
        $display("[%0t] back in STATE_NORMAL, battery_fault_latch=%0b, test passed", $time, dut.battery_fault_latch);
        assert (dut.battery_fault_latch == 1'b0) else $error("battery_fault_latch not cleared after returning to STATE_NORMAL");
        assert (system_enable == 1'b1) else $error("system_enable not high in STATE_NORMAL");

        $finish;
    end

endmodule
