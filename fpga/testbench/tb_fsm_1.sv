`timescale 1ns / 1ps

// FSM test case 1: normal boot, then reset_n back to STATE_OFF
module tb_fsm_1;

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
    logic mcu_power_enable;
    logic warning_led;
    logic shutdown_ack;
    logic critical_clear;
    logic buzzer_alert;
    logic recovery_mode;
    logic [6:0] state_debug_bus;

    // one-hot state codes, must match power_state_machine
    localparam logic [6:0] STATE_OFF    = 7'b0000001;
    localparam logic [6:0] STATE_BOOT   = 7'b0000010;
    localparam logic [6:0] STATE_NORMAL = 7'b0000100;

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
        .mcu_power_enable  (mcu_power_enable),
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
        assert (state_debug_bus == STATE_OFF) else $error("did not reset to STATE_OFF");

        // release reset
        reset_n = 1'b1;
        @(posedge clk);

        // press the power button
        manual_power = 1'b1;
        repeat (2) @(posedge clk);
        manual_power = 1'b0;

        // wait for the FSM to reach STATE_BOOT
        wait (state_debug_bus == STATE_BOOT);
        $display("[%0t] entered STATE_BOOT", $time);

        // toggle the heartbeat so mcu_alive gets set
        repeat (5) begin
            @(posedge clk);
            mcu_heartbeat = ~mcu_heartbeat;
        end

        // MCU reports a successful boot
        boot_success = 1'b1;

        // wait for the FSM to reach STATE_NORMAL
        wait (state_debug_bus == STATE_NORMAL);
        $display("[%0t] entered STATE_NORMAL", $time);
        assert (system_enable == 1'b1) else $error("system_enable not high in STATE_NORMAL");
        assert (mcu_power_enable == 1'b1) else $error("mcu_power_enable not high in STATE_NORMAL");

        boot_success = 1'b0;

        // reset the FSM back to STATE_OFF
        @(posedge clk);
        reset_n = 1'b0;
        repeat (2) @(posedge clk);
        assert (state_debug_bus == STATE_OFF) else $error("did not reset back to STATE_OFF");
        assert (system_enable == 1'b0) else $error("system_enable not low after reset");
        assert (mcu_power_enable == 1'b0) else $error("mcu_power_enable not low after reset");
        $display("[%0t] reset back to STATE_OFF, test passed", $time);

        $finish;
    end

endmodule
