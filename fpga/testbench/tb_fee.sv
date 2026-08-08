`timescale 1ns / 1ps

// This testbench is designed for Questa/ModelSim simulation (Quartus Prime)
// It verifies the Fault Event Engine based on Section 4.5 of the specification.

module tb_fee();

    // 1. Declare inputs to the DUT as logic
    logic clk;
    logic reset_n;
    
    logic overcurrent;
    logic overvoltage;
    logic undervoltage;
    logic overtemperature;
    logic fan_failure;
    logic sensor_failure;
    logic communication_timeout;
    
    // 2. Declare outputs from the DUT as logic
    logic fault_interrupt;
    logic shutdown_request;
    logic warning_request;
    logic [2:0] fault_code_bus;
    logic [1:0] buzzer_pattern;

    // 3. Instantiate the Device Under Test (DUT)
    fault_event_engine dut (
        .clk(clk),
        .reset_n(reset_n),
        .overcurrent(overcurrent),
        .overvoltage(overvoltage),
        .undervoltage(undervoltage),
        .overtemperature(overtemperature),
        .fan_failure(fan_failure),
        .sensor_failure(sensor_failure),
        .communication_timeout(communication_timeout),
        
        .fault_interrupt(fault_interrupt),
        .shutdown_request(shutdown_request),
        .warning_request(warning_request),
        .fault_code_bus(fault_code_bus),
        .buzzer_pattern(buzzer_pattern)
    );

    // 4. Clock Generator
    // Generates a 50MHz clock (20ns period) suitable for MAX 10 FPGA
    always begin
        #10 clk = ~clk; 
    end

    // 5. Test Sequence (Stimulus)
    initial begin
        $display("===========================================");
        $display("  STARTING FEE TESTBENCH (2 Scenarios) ");
        $display("===========================================");

        // Initialize all inputs to 0
        clk = 0;
        reset_n = 0;
        overcurrent = 0;
        overvoltage = 0;
        undervoltage = 0;
        overtemperature = 0;
        fan_failure = 0;
        sensor_failure = 0;
        communication_timeout = 0;
        
        // Wait and apply reset
        #30;
        reset_n = 1;
        #20;
        
        // --- SCENARIO 1: Priority Handling, Multiple Faults & Clear Sequence ---
        $display("\n--- SCENARIO 1: Priority Handling, Multiple Faults & Clear Sequence ---");
        // Ensure everything is zero at startup
        if (fault_interrupt == 0 && shutdown_request == 0)
            $display("[%0t] PASS: Outputs clear at startup.", $time);
            
        // 1. Inject first fault
        $display("[%0t] Injecting fan_failure...", $time);
        fan_failure = 1;
        #120; // Wait >5 clock cycles for debounce
        if (warning_request == 1 && fault_code_bus == 3'b110)
            $display("[%0t] PASS: fan_failure recognized correctly.", $time);
            
        // 2. Add simultaneous faults
        $display("[%0t] Injecting simultaneous faults (overvoltage, sensor_failure)...", $time);
        overvoltage = 1;
        sensor_failure = 1;
        #20; // Debounce already active from fan_failure, priority shift is instant
        
        if (shutdown_request == 1 && fault_code_bus == 3'b011) 
            $display("[%0t] PASS: Priority handling verified (overvoltage > sensor/fan).", $time);
        else 
            $display("[%0t] FAIL: Priority logic failed.", $time);
            
        // 3. Inject highest priority
        $display("[%0t] Injecting higher priority overcurrent...", $time);
        overcurrent = 1;
        #20;
        
        if (fault_code_bus == 3'b010)
            $display("[%0t] PASS: Priority handling verified (overcurrent > overvoltage).", $time);
        else
            $display("[%0t] FAIL: Priority logic failed.", $time);
            
        // 4. Test Fault Clear Sequence
        $display("[%0t] Clearing all faults to test clear sequence...", $time);
        overcurrent = 0;
        overvoltage = 0;
        sensor_failure = 0;
        fan_failure = 0;
        #40;
        if (fault_interrupt == 0 && warning_request == 0)
            $display("[%0t] PASS: Fault clear sequence working.", $time);
        
        // --- SCENARIO 2: Fault Debounce Test ---
        $display("\n--- SCENARIO 2: Fault Debounce Test ---");
        $display("[%0t] Injecting short 3-cycle glitch on overtemperature...", $time);
        overtemperature = 1;
        #60; // Wait 3 clock cycles (less than the 5 required)
        overtemperature = 0; // Clear the glitch
        
        #40; // wait 2 more cycles to check
        
        // If debounce works, system should not have reacted
        if (shutdown_request == 1) begin
            $display("[%0t] FAIL: System reacted to a short glitch! Debounce failed.", $time);
        end else begin
            $display("[%0t] PASS: System safely ignored the 3-cycle glitch.", $time);
        end
        
        $display("[%0t] Injecting sustained overtemperature fault...", $time);
        overtemperature = 1;
        #120; // Wait >5 clock cycles
        
        if (shutdown_request == 1) begin
            $display("[%0t] PASS: System correctly reacted to sustained fault.", $time);
        end else begin
            $display("[%0t] FAIL: System ignored sustained fault.", $time);
        end
        
        overtemperature = 0;
        #40;
        
        $display("\n===========================================");
        $display("  FEE TESTBENCH COMPLETED ");
        $display("===========================================");
        
        // Stop simulation
        $stop;
    end


endmodule
