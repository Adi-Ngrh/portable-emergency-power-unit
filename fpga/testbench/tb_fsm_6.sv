`timescale 1ns / 1ps

// FSM test case 6: STATE_WARNING entry, clears back to STATE_NORMAL, then an invalid current_state
module tb_fsm_6;

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
    localparam logic [6:0] STATE_OFF     = 7'b0000001;
    localparam logic [6:0] STATE_BOOT    = 7'b0000010;
    localparam logic [6:0] STATE_NORMAL  = 7'b0000100;
    localparam logic [6:0] STATE_WARNING = 7'b0001000;

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

        // a non-immediate issue is reported
        warning_request = 1'b1;

        // wait for the FSM to reach STATE_WARNING
        wait (state_debug_bus == STATE_WARNING);
        $display("[%0t] entered STATE_WARNING", $time);
        assert (warning_led == 1'b1) else $error("warning_led not high in STATE_WARNING");
        assert (system_enable == 1'b1) else $error("system_enable dropped in STATE_WARNING");

        // let it sit in STATE_WARNING for a bit
        repeat (5) @(posedge clk);

        // the warning clears
        warning_request = 1'b0;

        // wait for the FSM to return to STATE_NORMAL
        wait (state_debug_bus == STATE_NORMAL);
        $display("[%0t] back in STATE_NORMAL", $time);
        assert (warning_led == 1'b0) else $error("warning_led still high after returning to STATE_NORMAL");
        assert (system_enable == 1'b1) else $error("system_enable not high in STATE_NORMAL");

        // inject an illegal, non one-hot current_state
        repeat (3) @(posedge clk);
        force dut.current_state = 7'b1111111;
        @(posedge clk);
        $display("[%0t] forced an invalid current_state", $time);
        assert (system_enable == 1'b0) else $error("system_enable not forced low while current_state is invalid");
        release dut.current_state;

        // the default case should self-correct back to STATE_OFF on its own
        wait (state_debug_bus == STATE_OFF);
        $display("[%0t] self-corrected to STATE_OFF, test passed", $time);

        $finish;
    end

endmodule
