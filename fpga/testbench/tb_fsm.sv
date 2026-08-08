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
    // Generates a 50MHz clock (20ns period) for MAX 10 FPGA
    always begin
        #10 clk = ~clk; 
    end

    // 5. Test Sequence (Stimulus)
    initial begin
        $display("===========================================");
        $display("  STARTING FSM TESTBENCH (4 Scenarios)");
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

        // --- SCENARIO 1: Normal Flow (OFF -> BOOT -> NORMAL -> SHUTDOWN -> OFF) ---
        $display("\n--- SCENARIO 1: Normal Flow ---");
        #30 reset_n = 1; // Release reset
        #20 charger_connected = 1; // Boot up
        #100;
        if (state_debug_bus == 7'b0000100) $display("[%0t] PASS: Reached NORMAL state.", $time);
        
        $display("[%0t] Triggering manual shutdown...", $time);
        manual_shutdown = 1; 
        #100 manual_shutdown = 0;
        if (state_debug_bus == 7'b0100000) $display("[%0t] PASS: Reached SHUTDOWN state.", $time);
        
        $display("[%0t] MCU cleaning up and turning off...", $time);
        charger_connected = 0; 
        reset_n = 0; 
        #50 reset_n = 1; 
        #50 charger_connected = 1; // Boot up for next scenario
        #100;

        // --- SCENARIO 2: Warning Recovery (NORMAL -> WARNING -> NORMAL) ---
        $display("\n--- SCENARIO 2: Warning Recovery ---");
        $display("[%0t] Injecting overtemp (Warning)...", $time);
        overtemp = 1;
        #100;
        if (state_debug_bus == 7'b0001000) $display("[%0t] PASS: Reached WARNING state.", $time);
        
        $display("[%0t] Clearing overtemp...", $time);
        overtemp = 0;
        #100;
        if (state_debug_bus == 7'b0000100) $display("[%0t] PASS: Returned to NORMAL state.", $time);

        // --- SCENARIO 3: Battery Critical (NORMAL -> WARNING -> CRITICAL -> SHUTDOWN -> RECOVERY -> NORMAL) ---
        $display("\n--- SCENARIO 3: Battery Critical Flow ---");
        $display("[%0t] Injecting battery_low (Warning)...", $time);
        battery_low = 1;
        #100;
        $display("[%0t] Injecting battery_critical (Critical)...", $time);
        battery_critical = 1;
        #100;
        if (state_debug_bus == 7'b0010000) $display("[%0t] PASS: Reached CRITICAL state.", $time);
        
        $display("[%0t] Acknowledging shutdown...", $time);
        manual_shutdown = 1;
        #100 manual_shutdown = 0;
        
        #100; // Wait for recovery transition
        if (state_debug_bus == 7'b1000000) $display("[%0t] PASS: Entered RECOVERY mode.", $time);
        
        $display("[%0t] Battery charging... clearing faults...", $time);
        battery_critical = 0;
        battery_low = 0;
        #100;
        if (state_debug_bus == 7'b0000100) $display("[%0t] PASS: Returned to NORMAL state from RECOVERY.", $time);

        // --- SCENARIO 4: Non-Battery Critical (NORMAL -> WARNING -> CRITICAL -> SHUTDOWN -> OFF) ---
        $display("\n--- SCENARIO 4: Non-Battery Critical Flow ---");
        $display("[%0t] Resetting device to clear battery_fault_latch...", $time);
        reset_n = 0; charger_connected = 0;
        #50 reset_n = 1; charger_connected = 1;
        #100; // Boot to NORMAL
        
        $display("[%0t] Injecting overtemp (Warning)...", $time);
        overtemp = 1;
        #100;
        $display("[%0t] Injecting overcurrent (Critical)...", $time);
        overcurrent = 1;
        #100;
        if (state_debug_bus == 7'b0010000) $display("[%0t] PASS: Reached CRITICAL state.", $time);
        
        $display("[%0t] Acknowledging shutdown...", $time);
        manual_shutdown = 1;
        #100 manual_shutdown = 0;
        
        $display("[%0t] Verifying it stays stuck in SHUTDOWN (no recovery)...", $time);
        #100;
        if (state_debug_bus == 7'b0100000) $display("[%0t] PASS: Correctly stuck in SHUTDOWN.", $time);
        
        $display("[%0t] MCU cleaning up and turning off...", $time);
        reset_n = 0; 
        #50;
        if (state_debug_bus == 7'b0000001) $display("[%0t] PASS: Device OFF.", $time);

        $display("\n===========================================");
        $display("  FSM TESTBENCH COMPLETED ");
        $display("===========================================");
        
        $stop;
    end

endmodule
