`timescale 1ns / 1ps

// This testbench is designed for Questa/ModelSim simulation (Quartus Prime)
// It verifies the Power-State FSM Engine based on Section 3.7 of the specification.

module tb_fsm();

    // 1. Declare inputs to the DUT as logic
    logic clk;
    logic reset_n;
    
    logic battery_low;
    logic battery_critical;
    logic overtemp;
    logic overcurrent;
    logic charger_connected;
    logic manual_shutdown;
    
    // 2. Declare outputs from the DUT as logic
    logic system_enable;
    logic warning_led;
    logic shutdown_signal;
    logic buzzer_alert;
    logic recovery_mode;
    logic [6:0] state_debug_bus;

    // 3. Instantiate the Device Under Test (DUT)
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

    // 4. Clock Generator
    // Generates a 50MHz clock (20ns period) suitable for MAX 10 FPGA
    always begin
        #10 clk = ~clk; 
    end

    // 5. Test Sequence (Stimulus)
    initial begin
        $display("===========================================");
        $display("  STARTING FSM TESTBENCH (Questa/ModelSim) ");
        $display("===========================================");
        
        // Initialize all inputs to 0
        clk = 0;
        reset_n = 0;
        battery_low = 0;
        battery_critical = 0;
        overtemp = 0;
        overcurrent = 0;
        charger_connected = 0;
        manual_shutdown = 0;

        // --- 1. Reset Sequence (Section 3.7 Requirement) ---
        $display("[%0t] Asserting Reset...", $time);
        #30; 
        reset_n = 1; // Release reset (active low)
        #20;
        
        // --- 2. Boot up to NORMAL state ---
        // Need charger connected to boot from OFF state
        $display("[%0t] Connecting charger to boot...", $time);
        charger_connected = 1;
        #100; // Wait for synchronizers (2-stage) and state transitions
        if (state_debug_bus == 7'b0000100) $display("[%0t] PASS: Reached NORMAL state.", $time);
        else $display("[%0t] FAIL: Did not reach NORMAL state.", $time);

        // --- 3. Battery-low event injection (Section 3.7 Requirement) ---
        $display("[%0t] Injecting battery_low...", $time);
        battery_low = 1;
        #100;
        if (state_debug_bus == 7'b0001000) $display("[%0t] PASS: Reached WARNING state.", $time);
        else $display("[%0t] FAIL: Did not reach WARNING state.", $time);
        
        // Clear battery low
        battery_low = 0;
        #100;

        // --- 4. Overtemperature event (Section 3.7 Requirement) ---
        $display("[%0t] Injecting overtemp...", $time);
        overtemp = 1;
        #100;
        if (state_debug_bus == 7'b0001000) $display("[%0t] PASS: Reached WARNING state from overtemp.", $time);
        
        // Clear overtemp
        overtemp = 0;
        #100;
        if (state_debug_bus == 7'b0000100) $display("[%0t] PASS: Returned to NORMAL state.", $time);

        // --- 5. Critical battery event (Section 3.7 Requirement) ---
        $display("[%0t] Injecting battery_critical...", $time);
        battery_critical = 1;
        #100;
        if (state_debug_bus == 7'b0010000) $display("[%0t] PASS: Reached CRITICAL state.", $time);
        
        // Transition to SHUTDOWN requires user to manually acknowledge
        $display("[%0t] Acknowledging shutdown...", $time);
        manual_shutdown = 1;
        #100;
        if (state_debug_bus == 7'b0100000) $display("[%0t] PASS: Reached SHUTDOWN state.", $time);
        manual_shutdown = 0;

        // --- 6. Recovery scenario (Section 3.7 Requirement) ---
        // Device is shutdown, battery critical was latched. Charger is still connected.
        #100;
        if (state_debug_bus == 7'b1000000) $display("[%0t] PASS: Entered RECOVERY mode.", $time);
        
        // Clear critical battery, assume it charged up a bit
        $display("[%0t] Battery charging... clearing critical...", $time);
        battery_critical = 0;
        #100;
        if (state_debug_bus == 7'b0000100) $display("[%0t] PASS: Returned to NORMAL state from RECOVERY.", $time);

        $display("===========================================");
        $display("  FSM TESTBENCH COMPLETED ");
        $display("===========================================");
        
        // Stop simulation (Questa uses $stop to pause, $finish to close)
        $stop;
    end

endmodule
