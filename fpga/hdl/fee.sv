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

// synchronizer registers
logic overcurrent_raw, overcurrent_sync;
logic overvoltage_raw, overvoltage_sync;
logic undervoltage_raw, undervoltage_sync;
logic overtemperature_raw, overtemperature_sync;
logic fan_failure_raw, fan_failure_sync;
logic sensor_failure_raw, sensor_failure_sync;
logic communication_timeout_raw, communication_timeout_sync;

// 2-stage synchronizer block for external fault inputs
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        overcurrent_raw <= 1'b0;
        overcurrent_sync <= 1'b0;
        overvoltage_raw <= 1'b0;
        overvoltage_sync <= 1'b0;
        undervoltage_raw <= 1'b0;
        undervoltage_sync <= 1'b0;
        overtemperature_raw <= 1'b0;
        overtemperature_sync <= 1'b0;
        fan_failure_raw <= 1'b0;
        fan_failure_sync <= 1'b0;
        sensor_failure_raw <= 1'b0;
        sensor_failure_sync <= 1'b0;
        communication_timeout_raw <= 1'b0;
        communication_timeout_sync <= 1'b0;
    end else begin
        // Stage 1: Capture raw inputs (susceptible to metastability)
        overcurrent_raw <= overcurrent;
        overvoltage_raw <= overvoltage;
        undervoltage_raw <= undervoltage;
        overtemperature_raw <= overtemperature;
        fan_failure_raw <= fan_failure;
        sensor_failure_raw <= sensor_failure;
        communication_timeout_raw <= communication_timeout;

        // Stage 2: Capture settled signals
        overcurrent_sync <= overcurrent_raw;
        overvoltage_sync <= overvoltage_raw;
        undervoltage_sync <= undervoltage_raw;
        overtemperature_sync <= overtemperature_raw;
        fan_failure_sync <= fan_failure_raw;
        sensor_failure_sync <= sensor_failure_raw;
        communication_timeout_sync <= communication_timeout_raw;
    end
end





// next state variables for outputs
logic fault_interrupt_next;
logic shutdown_request_next;
logic warning_request_next;
logic [2:0] fault_code_bus_next;
logic [1:0] buzzer_pattern_next;

// debounce related variables (Wait 5 clock cycles to validate each fault independently)
logic [2:0] overcurrent_counter;
logic [2:0] overvoltage_counter;
logic [2:0] undervoltage_counter;
logic [2:0] overtemperature_counter;
logic [2:0] fan_failure_counter;
logic [2:0] sensor_failure_counter;
logic [2:0] communication_timeout_counter;

logic overcurrent_valid;
logic overvoltage_valid;
logic undervoltage_valid;
logic overtemperature_valid;
logic fan_failure_valid;
logic sensor_failure_valid;
logic communication_timeout_valid;
logic any_fault;

assign any_fault = (overtemperature_valid || overcurrent_valid || overvoltage_valid ||
                    undervoltage_valid || fan_failure_valid || sensor_failure_valid ||
                    communication_timeout_valid);

// debounce logic
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        overcurrent_counter <= 3'd0;
        overcurrent_valid <= 1'b0;
        overvoltage_counter <= 3'd0;
        overvoltage_valid <= 1'b0;
        undervoltage_counter <= 3'd0;
        undervoltage_valid <= 1'b0;
        overtemperature_counter <= 3'd0;
        overtemperature_valid <= 1'b0;
        fan_failure_counter <= 3'd0;
        fan_failure_valid <= 1'b0;
        sensor_failure_counter <= 3'd0;
        sensor_failure_valid <= 1'b0;
        communication_timeout_counter <= 3'd0;
        communication_timeout_valid <= 1'b0;
    end else begin
        // overcurrent
        if (overcurrent_sync) begin
            if (overcurrent_counter >= 3'd4) begin
                overcurrent_valid <= 1'b1;
            end else begin
                overcurrent_counter <= overcurrent_counter + 1'b1;
                overcurrent_valid <= 1'b0;
            end
        end else begin
            overcurrent_counter <= 3'd0;
            overcurrent_valid <= 1'b0;
        end

        // overvoltage
        if (overvoltage_sync) begin
            if (overvoltage_counter >= 3'd4) begin
                overvoltage_valid <= 1'b1;
            end else begin
                overvoltage_counter <= overvoltage_counter + 1'b1;
                overvoltage_valid <= 1'b0;
            end
        end else begin
            overvoltage_counter <= 3'd0;
            overvoltage_valid <= 1'b0;
        end

        // undervoltage
        if (undervoltage_sync) begin
            if (undervoltage_counter >= 3'd4) begin
                undervoltage_valid <= 1'b1;
            end else begin
                undervoltage_counter <= undervoltage_counter + 1'b1;
                undervoltage_valid <= 1'b0;
            end
        end else begin
            undervoltage_counter <= 3'd0;
            undervoltage_valid <= 1'b0;
        end

        // overtemperature
        if (overtemperature_sync) begin
            if (overtemperature_counter >= 3'd4) begin
                overtemperature_valid <= 1'b1;
            end else begin
                overtemperature_counter <= overtemperature_counter + 1'b1;
                overtemperature_valid <= 1'b0;
            end
        end else begin
            overtemperature_counter <= 3'd0;
            overtemperature_valid <= 1'b0;
        end

        // fan_failure
        if (fan_failure_sync) begin
            if (fan_failure_counter >= 3'd4) begin
                fan_failure_valid <= 1'b1;
            end else begin
                fan_failure_counter <= fan_failure_counter + 1'b1;
                fan_failure_valid <= 1'b0;
            end
        end else begin
            fan_failure_counter <= 3'd0;
            fan_failure_valid <= 1'b0;
        end

        // sensor_failure
        if (sensor_failure_sync) begin
            if (sensor_failure_counter >= 3'd4) begin
                sensor_failure_valid <= 1'b1;
            end else begin
                sensor_failure_counter <= sensor_failure_counter + 1'b1;
                sensor_failure_valid <= 1'b0;
            end
        end else begin
            sensor_failure_counter <= 3'd0;
            sensor_failure_valid <= 1'b0;
        end

        // communication_timeout
        if (communication_timeout_sync) begin
            if (communication_timeout_counter >= 3'd4) begin
                communication_timeout_valid <= 1'b1;
            end else begin
                communication_timeout_counter <= communication_timeout_counter + 1'b1;
                communication_timeout_valid <= 1'b0;
            end
        end else begin
            communication_timeout_counter <= 3'd0;
            communication_timeout_valid <= 1'b0;
        end
    end
end





// combinational logic for fault aggregation and priority
always_comb begin
    // Default assignments (No Fault)
    fault_interrupt_next  = 1'b0;
    shutdown_request_next = 1'b0;
    warning_request_next  = 1'b0;
    fault_code_bus_next   = 3'b000;
    buzzer_pattern_next   = 2'b00;

    // Check if any signal has been validated by its debounce timer
    if (any_fault) begin

        fault_interrupt_next = 1'b1;

        // Priority Encoder (Highest to Lowest Priority)
        if (overtemperature_valid) begin
            fault_code_bus_next   = 3'b001;
            shutdown_request_next = 1'b1;
            buzzer_pattern_next   = 2'b11; // Critical pattern
        end
        else if (overcurrent_valid) begin
            fault_code_bus_next   = 3'b010;
            shutdown_request_next = 1'b1;
            buzzer_pattern_next   = 2'b11; // Critical pattern
        end
        else if (overvoltage_valid) begin
            fault_code_bus_next   = 3'b011;
            shutdown_request_next = 1'b1;
            buzzer_pattern_next   = 2'b11; // Critical pattern
        end
        else if (sensor_failure_valid) begin
            fault_code_bus_next   = 3'b100;
            shutdown_request_next = 1'b1;
            buzzer_pattern_next   = 2'b11; // Critical pattern
        end
        else if (undervoltage_valid) begin
            fault_code_bus_next   = 3'b101;
            warning_request_next  = 1'b1;
            buzzer_pattern_next   = 2'b01; // Warning pattern
        end
        else if (fan_failure_valid) begin
            fault_code_bus_next   = 3'b110;
            warning_request_next  = 1'b1;
            buzzer_pattern_next   = 2'b01; // Warning pattern
        end
        else if (communication_timeout_valid) begin
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