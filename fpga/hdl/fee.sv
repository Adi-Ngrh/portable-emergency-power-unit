module fault_event_engine(
    input logic clk,
    input logic reset_n,
    
    // input signals
    input logic overcurrent,
    input logic overvoltage,
    input logic undervoltage,
    input logic overtemperature,
    input logic fan_failure,
    input logic sensor_failure,
    input logic communication_timeout,
	 input logic critical_clear,
    
    // output signals
    output logic shutdown_response,
    output logic warning_response,
	 output logic critical_response,
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
logic critical_clear_raw, critical_clear_sync;

// code bus & buzzer pattern
typedef enum logic [2:0]
{
	CODE_DEFAULT = 3'b000,
	CODE_OVERCURRENT = 3'b001,
	CODE_OVERVOLTAGE = 3'b010,
	CODE_OVERTEMPERATURE = 3'b011,
	CODE_SENSOR_FAILURE = 3'b100,
	CODE_UNDERVOLTAGE = 3'b101,
	CODE_FAN_FAILURE = 3'b110,
	CODE_COMMUNICATION_TIMEOUT = 3'b111
} code_e;
typedef enum logic [1:0]
{
	PATTERN_DEFAULT = 2'b00,
	PATTERN_WARNING = 2'b01,
	PATTERN_SHUTDOWN = 2'b10,
	PATTERN_CRITICAL = 2'b11
} pattern_e;

// debounce related variables
logic [5:0] overcurrent_counter;
logic [5:0] overvoltage_counter;
logic [15:0] undervoltage_counter;
logic [15:0] overtemperature_counter;
logic [18:0] fan_failure_counter;
logic [15:0] sensor_failure_counter;
logic [20:0] communication_timeout_counter;
localparam logic [5:0] overcurrent_threshold = 6'd50;
localparam logic [5:0] overvoltage_threshold = 6'd50;
localparam logic [15:0] undervoltage_threshold = 16'd50_000;
localparam logic [15:0] overtemperature_threshold = 16'd50_000;
localparam logic [18:0] fan_failure_threshold = 19'd500_000;
localparam logic [15:0] sensor_failure_threshold = 16'd50_000;
localparam logic [20:0] communication_timeout_threshold = 21'd1_500_000;

logic overcurrent_valid;
logic overvoltage_valid;
logic undervoltage_valid;
logic overtemperature_valid;
logic fan_failure_valid;
logic sensor_failure_valid;
logic communication_timeout_valid;
logic any_fault;

// next state variables for outputs
logic warning_response_next;
logic shutdown_response_next;
logic critical_response_next;
code_e fault_code_bus_next;
pattern_e buzzer_pattern_next;

assign any_fault = (overcurrent_valid || overvoltage_valid || overtemperature_valid || sensor_failure_valid ||
							undervoltage_valid || fan_failure_valid || communication_timeout_valid);
assign warning_response_next = undervoltage_valid || fan_failure_valid || communication_timeout_valid;
assign shutdown_response_next = overtemperature_valid || sensor_failure_valid;
assign critical_response_next = overcurrent_valid || overvoltage_valid;





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
		  critical_clear_raw <= 1'b0;
		  critical_clear_sync <= 1'b0;
    end 
	 else begin
        // Stage 1: Capture raw inputs (susceptible to metastability)
        overcurrent_raw <= overcurrent;
        overvoltage_raw <= overvoltage;
        undervoltage_raw <= undervoltage;
        overtemperature_raw <= overtemperature;
        fan_failure_raw <= fan_failure;
        sensor_failure_raw <= sensor_failure;
        communication_timeout_raw <= communication_timeout;
		  critical_clear_raw <= critical_clear;

        // Stage 2: Capture settled signals
        overcurrent_sync <= overcurrent_raw;
        overvoltage_sync <= overvoltage_raw;
        undervoltage_sync <= undervoltage_raw;
        overtemperature_sync <= overtemperature_raw;
        fan_failure_sync <= fan_failure_raw;
        sensor_failure_sync <= sensor_failure_raw;
        communication_timeout_sync <= communication_timeout_raw;
		  critical_clear_sync <= critical_clear_raw;
    end
end





// debounce logic
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        overcurrent_counter <= 6'd0;
        overcurrent_valid <= 1'b0;
        overvoltage_counter <= 6'd0;
        overvoltage_valid <= 1'b0;
        undervoltage_counter <= 16'd0;
        undervoltage_valid <= 1'b0;
        overtemperature_counter <= 16'd0;
        overtemperature_valid <= 1'b0;
        fan_failure_counter <= 19'd0;
        fan_failure_valid <= 1'b0;
        sensor_failure_counter <= 16'd0;
        sensor_failure_valid <= 1'b0;
        communication_timeout_counter <= 21'd0;
        communication_timeout_valid <= 1'b0;
    end else begin
        // overcurrent (valid at >= 1 us or 50 clock cycles)
        if (overcurrent_sync) begin
            if (overcurrent_counter >= overcurrent_threshold) begin
                overcurrent_valid <= 1'b1;
            end else begin
                overcurrent_counter <= overcurrent_counter + 1'b1;
                overcurrent_valid <= 1'b0;
            end
        end else begin
            overcurrent_counter <= 3'd0;
            overcurrent_valid <= 1'b0;
        end

        // overvoltage (valid at >= 1 us or 50 clock cycles)
        if (overvoltage_sync) begin
            if (overvoltage_counter >= overvoltage_threshold) begin
                overvoltage_valid <= 1'b1;
            end else begin
                overvoltage_counter <= overvoltage_counter + 1'b1;
                overvoltage_valid <= 1'b0;
            end
        end else begin
            overvoltage_counter <= 3'd0;
            overvoltage_valid <= 1'b0;
        end

        // undervoltage (valid at >= 1 ms or 50000 clock cycles)
        if (undervoltage_sync) begin
            if (undervoltage_counter >= undervoltage_threshold) begin
                undervoltage_valid <= 1'b1;
            end else begin
                undervoltage_counter <= undervoltage_counter + 1'b1;
                undervoltage_valid <= 1'b0;
            end
        end else begin
            undervoltage_counter <= 3'd0;
            undervoltage_valid <= 1'b0;
        end

        // overtemperature (valid at >= 1 ms or 50000 clock cycles)
        if (overtemperature_sync) begin
            if (overtemperature_counter >= overtemperature_threshold) begin
                overtemperature_valid <= 1'b1;
            end else begin
                overtemperature_counter <= overtemperature_counter + 1'b1;
                overtemperature_valid <= 1'b0;
            end
        end else begin
            overtemperature_counter <= 3'd0;
            overtemperature_valid <= 1'b0;
        end

        // fan_failure (valid at >= 10 ms or 500000 clock cycles)
        if (fan_failure_sync) begin
            if (fan_failure_counter >= fan_failure_threshold) begin
                fan_failure_valid <= 1'b1;
            end else begin
                fan_failure_counter <= fan_failure_counter + 1'b1;
                fan_failure_valid <= 1'b0;
            end
        end else begin
            fan_failure_counter <= 3'd0;
            fan_failure_valid <= 1'b0;
        end

        // sensor_failure (valid at >= 1 ms or 50000 clock cycles)
        if (sensor_failure_sync) begin
            if (sensor_failure_counter >= sensor_failure_threshold) begin
                sensor_failure_valid <= 1'b1;
            end else begin
                sensor_failure_counter <= sensor_failure_counter + 1'b1;
                sensor_failure_valid <= 1'b0;
            end
        end else begin
            sensor_failure_counter <= 3'd0;
            sensor_failure_valid <= 1'b0;
        end

        // communication_timeout (valid at >= 30 ms or 1500000 clock cycles)
        if (communication_timeout_sync) begin
            if (communication_timeout_counter >= communication_timeout_threshold) begin
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
    fault_code_bus_next   = CODE_DEFAULT;
    buzzer_pattern_next   = PATTERN_DEFAULT;

    // Check if any signal has been validated by its debounce timer
    if (any_fault) begin
        // Priority Encoder (Highest to Lowest Priority)
		  if (overcurrent_valid) begin
            fault_code_bus_next   = CODE_OVERCURRENT;
            buzzer_pattern_next   = PATTERN_CRITICAL; 
        end
		  else if (overvoltage_valid) begin
            fault_code_bus_next   = CODE_OVERVOLTAGE;
            buzzer_pattern_next   = PATTERN_CRITICAL;
        end
        else if (overtemperature_valid) begin
            fault_code_bus_next   = CODE_OVERTEMPERATURE;
            buzzer_pattern_next   = PATTERN_SHUTDOWN;
        end
        else if (sensor_failure_valid) begin
            fault_code_bus_next   = CODE_SENSOR_FAILURE;
            buzzer_pattern_next   = PATTERN_SHUTDOWN;
        end
        else if (undervoltage_valid) begin
            fault_code_bus_next   = CODE_UNDERVOLTAGE;
            buzzer_pattern_next   = PATTERN_WARNING;
        end
        else if (fan_failure_valid) begin
            fault_code_bus_next   = CODE_FAN_FAILURE;
            buzzer_pattern_next   = PATTERN_WARNING;
        end
        else if (communication_timeout_valid) begin
            fault_code_bus_next   = CODE_COMMUNICATION_TIMEOUT;
            buzzer_pattern_next   = PATTERN_WARNING; 
        end
    end
end





// Sequential block to update outputs on clock edge
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        shutdown_response <= 1'b0;
        warning_response  <= 1'b0;
        fault_code_bus   <= 3'b000;
        buzzer_pattern   <= 2'b00;
    end else begin
        shutdown_response <= shutdown_response_next;
        warning_response  <= warning_response_next;
        fault_code_bus   <= fault_code_bus_next;
        buzzer_pattern   <= buzzer_pattern_next;
    end
end





// latch so critical response stay high until fault clear
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		critical_response <= 1'b0;
	end
	else if (critical_response_next) begin
		critical_response <= 1'b1;
	end
	else if (critical_clear_sync) begin
		critical_response <= 1'b0;
	end
end

endmodule