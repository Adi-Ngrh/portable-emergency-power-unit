`timescale 1ns / 1ps

// Testbench for the Power-State FSM Engine (fsm.sv).
// Mapped to FPGA_Template_2_IP_Siap_Tapeout-1.pdf, Section 3.
// Simulation only (QuestaSim/ModelSim) - no hardware.

module tb_fsm();

    // -------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------
    logic clk;
    logic reset_n;

    logic battery_low;
    logic battery_critical;
    logic overtemp;
    logic overcurrent;
    logic charger_connected;
    logic manual_shutdown;

    logic system_enable;
    logic warning_led;
    logic shutdown_signal;
    logic buzzer_alert;
    logic recovery_mode;
    logic [6:0] state_debug_bus;

    power_state_machine dut (
        .clk(clk),
        .reset_n(reset_n),
        .battery_low(battery_low),
        .battery_critical(battery_critical),
        .overtemp(overtemp),
        .overcurrent(overcurrent),
        .charger_connected(charger_connected),
        .manual_shutdown(manual_shutdown),

        .system_enable(system_enable),
        .warning_led(warning_led),
        .shutdown_signal(shutdown_signal),
        .buzzer_alert(buzzer_alert),
        .recovery_mode(recovery_mode),
        .state_debug_bus(state_debug_bus)
    );

    // -------------------------------------------------------------------
    // 3.7 Testbench Requirements - Clock generator (50MHz, 20ns period)
    // -------------------------------------------------------------------
    initial clk = 0;
    always #10 clk = ~clk;

    // -------------------------------------------------------------------
    // Pass/fail bookkeeping
    // -------------------------------------------------------------------
    int pass_total = 0;
    int fail_total = 0;

    // -------------------------------------------------------------------
    // Current test-case marker - shown as a labeled text track in the
    // Questa Wave window so test case boundaries are visible at a glance
    // and easy to zoom/screenshot individually.
    // -------------------------------------------------------------------
    string current_test;

    task automatic check(string label, logic cond);
        if (cond) begin
            pass_total++;
            $display("[%0t] PASS: %s", $time, label);
        end else begin
            fail_total++;
            $display("[%0t] FAIL: %s", $time, label);
        end
    endtask

    // Polls per clock edge so single-cycle transient states aren't missed.
    task automatic wait_for_state(input logic [6:0] expected_state, input string label, input int timeout_cycles = 50);
        int cycles;
        cycles = 0;
        while ((state_debug_bus !== expected_state) && (cycles < timeout_cycles)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        check(label, state_debug_bus == expected_state);
    endtask

    // -------------------------------------------------------------------
    // 3.7 Testbench Requirements - Reset sequence
    // -------------------------------------------------------------------
    task automatic apply_reset();
        reset_n = 0;
        #40;
        reset_n = 1;
        #20;
    endtask

    task automatic boot_to_normal();
        charger_connected = 1;
        wait_for_state(dut.NORMAL, "Booted to NORMAL state");
    endtask

    // =====================================================================
    // 3.6 Verification Checklist - Reset behavior verified
    // =====================================================================
    task automatic test_reset_behavior();
        current_test = "3.6 Reset behavior verified";
        $display("\n--- 3.6 Reset behavior verified ---");

        apply_reset();
        check("State is OFF immediately after reset", state_debug_bus == dut.OFF);
        check("system_enable is 0 after reset", system_enable == 1'b0);
        check("warning_led is 0 after reset", warning_led == 1'b0);
        check("shutdown_signal is 0 after reset", shutdown_signal == 1'b0);
        check("buzzer_alert is 0 after reset", buzzer_alert == 1'b0);
        check("recovery_mode is 0 after reset", recovery_mode == 1'b0);

        boot_to_normal();
        reset_n = 0;
        repeat (2) @(posedge clk);
        check("Mid-operation reset forces state back to OFF", state_debug_bus == dut.OFF);
        reset_n = 1;
        repeat (2) @(posedge clk);
    endtask

    // =====================================================================
    // 3.6 Verification Checklist - Illegal state handling tested
    // =====================================================================
    task automatic test_illegal_state();
        current_test = "3.6 Illegal state handling tested";
        $display("\n--- 3.6 Illegal state handling tested ---");

        apply_reset();
        // Invalid one-hot code; only reachable via a forced fault, not normal operation.
        force dut.current_state = 7'b1100000;
        @(posedge clk);
        release dut.current_state;
        wait_for_state(dut.OFF, "Illegal one-hot state recovers to OFF via default case");
    endtask

    // =====================================================================
    // 3.6 Verification Checklist - All state transitions simulated
    // Walks Section 3.5's example sequence plus the remaining graph edges.
    // =====================================================================
    task automatic test_all_transitions();
        current_test = "3.6 All state transitions simulated";
        $display("\n--- 3.6 All state transitions simulated ---");

        apply_reset();
        boot_to_normal();

        battery_low = 1;
        wait_for_state(dut.WARNING, "NORMAL -> WARNING on battery_low");
        battery_low = 0;
        wait_for_state(dut.NORMAL, "WARNING -> NORMAL once battery_low clears");

        // charger already connected from boot_to_normal
        battery_low = 1;
        wait_for_state(dut.WARNING, "NORMAL -> WARNING on battery_low (2nd time)");
        battery_critical = 1;
        wait_for_state(dut.CRITICAL, "WARNING -> CRITICAL on battery_critical");
        check("shutdown_signal asserted in CRITICAL", shutdown_signal == 1'b1);
        check("warning_led asserted in CRITICAL", warning_led == 1'b1);
        check("buzzer_alert asserted in CRITICAL", buzzer_alert == 1'b1);

        wait_for_state(dut.SHUTDOWN, "CRITICAL -> SHUTDOWN automatically for a battery-caused fault");
        wait_for_state(dut.RECOVERY, "SHUTDOWN -> RECOVERY once charger is connected and fault is latched");
        check("recovery_mode asserted in RECOVERY", recovery_mode == 1'b1);
        check("system_enable stays 0 in RECOVERY", system_enable == 1'b0);

        battery_critical = 0;
        battery_low = 0;
        wait_for_state(dut.NORMAL, "RECOVERY -> NORMAL once battery is safe again");

        // reset first so battery_fault_latch is clean, isolating this from RECOVERY
        apply_reset();
        boot_to_normal();
        manual_shutdown = 1;
        wait_for_state(dut.SHUTDOWN, "NORMAL -> SHUTDOWN via direct manual_shutdown");
        manual_shutdown = 0;
        repeat (5) @(posedge clk);
        check("Stays in SHUTDOWN with no battery fault to recover from", state_debug_bus == dut.SHUTDOWN);

        apply_reset();
        boot_to_normal();
        overtemp = 1;
        wait_for_state(dut.WARNING, "NORMAL -> WARNING on overtemp");
        overcurrent = 1;
        wait_for_state(dut.CRITICAL, "WARNING -> CRITICAL on overcurrent");

        repeat (5) @(posedge clk);
        check("Non-battery CRITICAL does not auto-advance without manual_shutdown", state_debug_bus == dut.CRITICAL);

        manual_shutdown = 1;
        wait_for_state(dut.SHUTDOWN, "CRITICAL -> SHUTDOWN once manual_shutdown acknowledges a non-battery fault");
        manual_shutdown = 0;

        repeat (5) @(posedge clk);
        check("Stays in SHUTDOWN with no charger / no battery fault to recover from", state_debug_bus == dut.SHUTDOWN);

        overtemp = 0;
        overcurrent = 0;
    endtask
    

    // =====================================================================
    // 3.7 Testbench Requirements - Battery-low event injection
    // =====================================================================
    task automatic test_battery_low_event();
        current_test = "3.7 Battery-low event injection";
        $display("\n--- 3.7 Battery-low event injection ---");
        apply_reset();
        boot_to_normal();

        battery_low = 1;
        wait_for_state(dut.WARNING, "battery_low injection drives FSM into WARNING");
        check("system_enable stays 1 in WARNING (output still running)", system_enable == 1'b1);
        check("warning_led asserted in WARNING", warning_led == 1'b1);

        battery_low = 0;
        wait_for_state(dut.NORMAL, "WARNING -> NORMAL once battery_low clears");
    endtask

    // =====================================================================
    // 3.7 Testbench Requirements - Critical battery event
    // =====================================================================
    task automatic test_critical_battery_event();
        current_test = "3.7 Critical battery event";
        $display("\n--- 3.7 Critical battery event ---");
        apply_reset();
        boot_to_normal();
        charger_connected = 0; // isolate from RECOVERY auto-advance

        battery_critical = 1;
        wait_for_state(dut.CRITICAL, "battery_critical injection drives FSM into CRITICAL");
        check("system_enable de-asserted in CRITICAL", system_enable == 1'b0);
        check("shutdown_signal asserted in CRITICAL", shutdown_signal == 1'b1);
        check("buzzer_alert asserted in CRITICAL", buzzer_alert == 1'b1);

        wait_for_state(dut.SHUTDOWN, "Battery-caused CRITICAL auto-advances to SHUTDOWN");
        repeat (5) @(posedge clk);
        check("Holds in SHUTDOWN with no charger connected", state_debug_bus == dut.SHUTDOWN);

        battery_critical = 0;
    endtask

    // =====================================================================
    // 3.7 Testbench Requirements - Recovery scenario
    // =====================================================================
    task automatic test_recovery_scenario();
        current_test = "3.7 Recovery scenario";
        $display("\n--- 3.7 Recovery scenario ---");
        apply_reset();
        boot_to_normal();

        battery_critical = 1;
        wait_for_state(dut.CRITICAL, "Battery-caused fault reaches CRITICAL");
        wait_for_state(dut.SHUTDOWN, "CRITICAL auto-advances to SHUTDOWN");
        wait_for_state(dut.RECOVERY, "SHUTDOWN -> RECOVERY with charger already connected");
        check("system_enable stays 0 in RECOVERY (output disabled while charging)", system_enable == 1'b0);
        check("recovery_mode asserted in RECOVERY", recovery_mode == 1'b1);

        battery_critical = 0;
        wait_for_state(dut.NORMAL, "RECOVERY -> NORMAL once battery is no longer critical/low");
    endtask

    // =====================================================================
    // 3.7 Testbench Requirements - Overtemperature event
    // =====================================================================
    task automatic test_overtemperature_event();
        current_test = "3.7 Overtemperature event";
        $display("\n--- 3.7 Overtemperature event ---");
        apply_reset();
        boot_to_normal();

        overtemp = 1;
        wait_for_state(dut.WARNING, "overtemp injection drives FSM into WARNING");

        overtemp = 0;
        wait_for_state(dut.NORMAL, "WARNING -> NORMAL once overtemp clears");
    endtask

    // -------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------
    initial begin
        $display("===========================================");
        $display("  STARTING FSM TESTBENCH");
        $display("  (FPGA_Template_2_IP_Siap_Tapeout-1.pdf, Section 3)");
        $display("===========================================");

        clk = 0;
        reset_n = 0;
        current_test = "Setup";
        battery_low = 0;
        battery_critical = 0;
        overtemp = 0;
        overcurrent = 0;
        charger_connected = 0;
        manual_shutdown = 0;

        test_reset_behavior();
        test_illegal_state();
        test_all_transitions();
        test_battery_low_event();
        test_critical_battery_event();
        test_recovery_scenario();
        test_overtemperature_event();

        current_test = "Done";
        $display("\n===========================================");
        $display("  FSM TESTBENCH COMPLETE: %0d PASS / %0d FAIL", pass_total, fail_total);
        $display("===========================================");
        $display("  Not coverable by simulation alone:");
        $display("  - Timing clean after synthesis: needs post-synthesis STA, not sim.");
        $display("  - Timeout conditions verified: no timeout logic exists in fsm.sv.");
        $display("  Waveform documented: satisfied by capturing the wave window for this run.");
        $display("===========================================");

        $stop;
    end

endmodule
