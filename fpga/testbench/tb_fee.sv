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
        $display("  STARTING FEE TESTBENCH (Questa/ModelSim) ");
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
        
        // --- 1. Fault clear sequence tested (Section 4.5 Requirement) ---
        // Ensure everything is zero at startup
        if (fault_interrupt == 0 && shutdown_request == 0)
            $display("[%0t] PASS: Outputs clear at startup.", $time);
            
        // --- 2. Single Fault Test (Warning) ---
        $display("[%0t] Injecting fan_failure...", $time);
        fan_failure = 1;
        #20; // Wait 1 clock cycle to propagate through register
        if (warning_request == 1 && fault_code_bus == 3'b110)
            $display("[%0t] PASS: fan_failure recognized correctly.", $time);
            
        // Clear fault to test fault clear sequence
        fan_failure = 0;
        #20;
        if (fault_interrupt == 0 && warning_request == 0)
            $display("[%0t] PASS: Fault clear sequence working.", $time);
        
        // --- 3. Single Fault Test (Critical) ---
        $display("[%0t] Injecting overtemperature...", $time);
        overtemperature = 1;
        #20;
        if (shutdown_request == 1 && fault_code_bus == 3'b001)
            $display("[%0t] PASS: overtemperature recognized correctly.", $time);
        overtemperature = 0;
        #20;

        // --- 4. Multiple simultaneous faults tested & Priority handling verified ---
        // Section 4.5 Requirements
        // If we have overvoltage (priority 3), sensor_failure (priority 4), and fan_failure (priority 6)
        // overvoltage should win.
        $display("[%0t] Injecting simultaneous faults (overvoltage, sensor_failure, fan_failure)...", $time);
        overvoltage = 1;
        sensor_failure = 1;
        fan_failure = 1;
        #20;
        
        if (shutdown_request == 1 && fault_code_bus == 3'b011) 
            $display("[%0t] PASS: Priority handling verified (overvoltage > sensor/fan).", $time);
        else 
            $display("[%0t] FAIL: Priority logic failed.", $time);
            
        // Now inject overcurrent (priority 2), it should override overvoltage
        $display("[%0t] Injecting higher priority overcurrent...", $time);
        overcurrent = 1;
        #20;
        
        if (fault_code_bus == 3'b010)
            $display("[%0t] PASS: Priority handling verified (overcurrent > overvoltage).", $time);
        else
            $display("[%0t] FAIL: Priority logic failed.", $time);
            
        // Clear all faults
        overcurrent = 0;
        overvoltage = 0;
        sensor_failure = 0;
        fan_failure = 0;
        #40;
        
        $display("===========================================");
        $display("  FEE TESTBENCH COMPLETED ");
        $display("===========================================");
        
        // Stop simulation
        $stop;
    end

endmodule
