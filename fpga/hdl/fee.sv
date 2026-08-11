module fault_event_engine(
    input logic clk,
    input logic reset_n,
    
    // Input Fault Signals (Section 4.2)
    input logic overcurrent,
    input logic overvoltage,
    input logic undervoltage,
    input logic overtemperature,
    input logic fan_failure,
    input logic sensor_failure,
    input logic communication_timeout,
    
    // Output Signals (Section 4.3)
    output logic fault_interrupt,
    output logic shutdown_request,
    output logic warning_request,
    output logic [2:0] fault_code_bus,
    output logic [1:0] buzzer_pattern
);


    // Next state variables for outputs
    logic fault_interrupt_next;
    logic shutdown_request_next;
    logic warning_request_next;
    logic [2:0] fault_code_bus_next;
    logic [1:0] buzzer_pattern_next;

    // Debounce Logic (Wait 5 clock cycles to validate fault)
    logic any_fault;
    logic fault_valid;
    logic [3:0] debounce_counter;

    assign any_fault = (overtemperature || overcurrent || overvoltage || 
                        undervoltage || fan_failure || sensor_failure || 
                        communication_timeout);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            debounce_counter <= 4'd0;
            fault_valid <= 1'b0;
        end else begin
            if (any_fault) begin
                if (debounce_counter >= 4'd4) begin
                    fault_valid <= 1'b1;
                end else begin
                    debounce_counter <= debounce_counter + 1'b1;
                    fault_valid <= 1'b0;
                end
            end else begin
                debounce_counter <= 4'd0;
                fault_valid <= 1'b0;
            end
        end
    end

    // Combinational logic for fault aggregation and priority (Section 4.4)
    always_comb begin
        // Default assignments (No Fault)
        fault_interrupt_next  = 1'b0;
        shutdown_request_next = 1'b0;
        warning_request_next  = 1'b0;
        fault_code_bus_next   = 3'b000;
        buzzer_pattern_next   = 2'b00;

        // Check if fault has been validated by debounce timer
        if (fault_valid) begin
            
            fault_interrupt_next = 1'b1;

            // Priority Encoder (Highest to Lowest Priority)
            if (overtemperature) begin
                fault_code_bus_next   = 3'b001;
                shutdown_request_next = 1'b1;
                buzzer_pattern_next   = 2'b11; // Critical pattern
            end
            else if (overcurrent) begin
                fault_code_bus_next   = 3'b010;
                shutdown_request_next = 1'b1;
                buzzer_pattern_next   = 2'b11; // Critical pattern
            end
            else if (overvoltage) begin
                fault_code_bus_next   = 3'b011;
                shutdown_request_next = 1'b1;
                buzzer_pattern_next   = 2'b11; // Critical pattern
            end
            else if (sensor_failure) begin
                fault_code_bus_next   = 3'b100;
                shutdown_request_next = 1'b1;
                buzzer_pattern_next   = 2'b11; // Critical pattern
            end
            else if (undervoltage) begin
                fault_code_bus_next   = 3'b101;
                warning_request_next  = 1'b1;
                buzzer_pattern_next   = 2'b01; // Warning pattern
            end
            else if (fan_failure) begin
                fault_code_bus_next   = 3'b110;
                warning_request_next  = 1'b1;
                buzzer_pattern_next   = 2'b01; // Warning pattern
            end
            else if (communication_timeout) begin
                fault_code_bus_next   = 3'b111;
                warning_request_next  = 1'b1;
                buzzer_pattern_next   = 2'b01; // Warning pattern
            end
        end
    end

    // Sequential block to update outputs on clock edge
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fault_interrupt  <= 1'b0;
            shutdown_request <= 1'b0;
            warning_request  <= 1'b0;
            fault_code_bus   <= 3'b000;
            buzzer_pattern   <= 2'b00;
        end else begin
            fault_interrupt  <= fault_interrupt_next;
            shutdown_request <= shutdown_request_next;
            warning_request  <= warning_request_next;
            fault_code_bus   <= fault_code_bus_next;
            buzzer_pattern   <= buzzer_pattern_next;
        end
    end

endmodule