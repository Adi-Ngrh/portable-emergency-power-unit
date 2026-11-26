module fault_event_engine #(
    parameter CLK_FREQ_HZ,
    parameter OVERTEMP_SET_C   = 60,  // overtemperature trips at or above this temperature (°C)
    parameter OVERTEMP_CLEAR_C = 55,  // overtemperature releases below this temperature (°C), must be lower than OVERTEMP_SET_C
    parameter OVERTEMP_READING_COUNT = 3,  // consecutive readings above the limit before overtemperature is reported (1 to 255)
    parameter OVERVOLTAGE_SET_MV    = 14_600,  // overvoltage trips at or above this bus voltage (mV), placeholder, must match the battery
    parameter OVERVOLTAGE_CLEAR_MV  = 14_200,  // overvoltage releases below this bus voltage (mV), must be lower than OVERVOLTAGE_SET_MV
    parameter UNDERVOLTAGE_SET_MV   = 10_500,  // undervoltage trips at or below this bus voltage (mV), placeholder, must match the battery
    parameter UNDERVOLTAGE_CLEAR_MV = 11_000,  // undervoltage releases above this bus voltage (mV), must be higher than UNDERVOLTAGE_SET_MV
    parameter OVERCURRENT_SET_MA    = 5_000,   // overcurrent trips at or above this current in either direction (mA), placeholder
    parameter OVERCURRENT_CLEAR_MA  = 4_500,   // overcurrent releases below this current (mA), must be lower than OVERCURRENT_SET_MA
    parameter CURRENT_LSB_UA        = 1000,    // current resolution of ina226_reader (microampere per bit), must match ina226_reader
    parameter INA226_READING_COUNT  = 3        // consecutive INA226 readings beyond a limit before a voltage/current fault is reported (1 to 255)
)(
    input logic clk,
    input logic reset_n,
    
    // input signals
    input logic [15:0] bus_voltage,         // from INA226 reader, unsigned, 1 LSB = 1.25 mV
    input logic signed [15:0] current,      // from INA226 reader, signed, 1 LSB = CURRENT_LSB_UA microampere
    input logic measurement_valid,          // high for 1 clock when new bus_voltage and current values arrive
    input logic measurement_error,          // high while the INA226 reader reports a problem (no answer, wrong data, timeout)
    input logic signed [15:0] temperature,  // from DS18B20 reader, signed, 1 LSB = 1/16 °C
    input logic temperature_valid,          // high for 1 clock when a new temperature reading arrives
    input logic temperature_error,          // high while the temperature reader reports a problem (no response, CRC error, timeout)
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

// overtemperature threshold (converted from °C to DS18B20 format, 1 LSB = 1/16 °C)
localparam logic signed [15:0] overtemperature_set_level   = OVERTEMP_SET_C * 16;
localparam logic signed [15:0] overtemperature_clear_level = OVERTEMP_CLEAR_C * 16;
logic overtemperature_over_limit;   // result of comparing temperature against the threshold
logic overtemperature_result_ready; // high for 1 clock right after overtemperature_over_limit is updated

// voltage thresholds (converted from mV to INA226 bus voltage format, 1 LSB = 1.25 mV, so code = mV * 4 / 5)
localparam logic [15:0] overvoltage_set_level    = OVERVOLTAGE_SET_MV * 4 / 5;
localparam logic [15:0] overvoltage_clear_level  = OVERVOLTAGE_CLEAR_MV * 4 / 5;
localparam logic [15:0] undervoltage_set_level   = UNDERVOLTAGE_SET_MV * 4 / 5;
localparam logic [15:0] undervoltage_clear_level = UNDERVOLTAGE_CLEAR_MV * 4 / 5;

// current thresholds (converted from mA to INA226 current format, 1 LSB = CURRENT_LSB_UA microampere)
localparam logic signed [15:0] overcurrent_set_level   = OVERCURRENT_SET_MA * 1000 / CURRENT_LSB_UA;
localparam logic signed [15:0] overcurrent_clear_level = OVERCURRENT_CLEAR_MA * 1000 / CURRENT_LSB_UA;

logic overvoltage_over_limit;    // result of comparing bus_voltage against the overvoltage threshold
logic undervoltage_under_limit;  // result of comparing bus_voltage against the undervoltage threshold
logic overcurrent_over_limit;    // result of comparing current against the overcurrent threshold
logic ina226_result_ready;       // high for 1 clock right after the three results above are updated

// debounce related variables
logic [7:0]  overcurrent_counter;     // counts readings, not clock cycles
logic [7:0]  overvoltage_counter;     // counts readings, not clock cycles
logic [7:0]  undervoltage_counter;    // counts readings, not clock cycles
logic [7:0]  overtemperature_counter; // counts readings, not clock cycles
logic [18:0] fan_failure_counter;
logic [15:0] sensor_failure_counter;
logic [20:0] communication_timeout_counter;
localparam logic [18:0] fan_failure_threshold           = CLK_FREQ_HZ / 100;        // 10 ms
localparam logic [15:0] sensor_failure_threshold        = CLK_FREQ_HZ / 1_000;      // 1 ms
localparam logic [20:0] communication_timeout_threshold = CLK_FREQ_HZ * 30 / 1_000; // 30 ms

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
        fan_failure_raw <= fan_failure;
        sensor_failure_raw <= sensor_failure;
        communication_timeout_raw <= communication_timeout;
		  critical_clear_raw <= critical_clear;

        // Stage 2: Capture settled signals
        fan_failure_sync <= fan_failure_raw;
        sensor_failure_sync <= sensor_failure_raw;
        communication_timeout_sync <= communication_timeout_raw;
		  critical_clear_sync <= critical_clear_raw;
    end
end





// overtemperature comparator with hysteresis (no synchronizer needed, input is on the same clock)
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        overtemperature_over_limit <= 1'b0;
        overtemperature_result_ready <= 1'b0;
    end
    else begin
        // tells the debounce logic that a new comparison result is available on the next clock
        overtemperature_result_ready <= temperature_valid;

        if (temperature_valid) begin
            if (temperature >= overtemperature_set_level) begin
                overtemperature_over_limit <= 1'b1;
            end
            else if (temperature < overtemperature_clear_level) begin
                overtemperature_over_limit <= 1'b0;
            end
            // between clear level and set level: keep previous value (hysteresis)
        end
    end
end





// voltage and current comparators with hysteresis (no synchronizer needed, inputs are on the same clock)
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        overvoltage_over_limit <= 1'b0;
        undervoltage_under_limit <= 1'b0;
        overcurrent_over_limit <= 1'b0;
        ina226_result_ready <= 1'b0;
    end
    else begin
        // tells the debounce logic that new comparison results are available on the next clock
        ina226_result_ready <= measurement_valid;

        if (measurement_valid) begin
            // overvoltage: trip at or above set level, release below clear level
            if (bus_voltage >= overvoltage_set_level) begin
                overvoltage_over_limit <= 1'b1;
            end
            else if (bus_voltage < overvoltage_clear_level) begin
                overvoltage_over_limit <= 1'b0;
            end

            // undervoltage: trip at or below set level, release above clear level
            if (bus_voltage <= undervoltage_set_level) begin
                undervoltage_under_limit <= 1'b1;
            end
            else if (bus_voltage > undervoltage_clear_level) begin
                undervoltage_under_limit <= 1'b0;
            end

            // overcurrent: the sign of current depends on its direction, so both directions are checked
            if (current >= overcurrent_set_level || current <= -overcurrent_set_level) begin
                overcurrent_over_limit <= 1'b1;
            end
            else if (current < overcurrent_clear_level && current > -overcurrent_clear_level) begin
                overcurrent_over_limit <= 1'b0;
            end
            // between clear level and set level: keep previous values (hysteresis)
        end
    end
end





// debounce logic
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        overcurrent_counter <= 8'd0;
        overcurrent_valid <= 1'b0;
        overvoltage_counter <= 8'd0;
        overvoltage_valid <= 1'b0;
        undervoltage_counter <= 8'd0;
        undervoltage_valid <= 1'b0;
        overtemperature_counter <= 8'd0;
        overtemperature_valid <= 1'b0;
        fan_failure_counter <= 19'd0;
        fan_failure_valid <= 1'b0;
        sensor_failure_counter <= 16'd0;
        sensor_failure_valid <= 1'b0;
        communication_timeout_counter <= 21'd0;
        communication_timeout_valid <= 1'b0;
    end else begin
        // overcurrent (valid after INA226_READING_COUNT consecutive readings above the limit)
        if (ina226_result_ready) begin
            if (overcurrent_over_limit) begin
                if (overcurrent_counter < INA226_READING_COUNT) begin
                    overcurrent_counter <= overcurrent_counter + 1'b1;
                end
            end else begin
                overcurrent_counter <= 8'd0;
            end
        end

        if (overcurrent_counter >= INA226_READING_COUNT) begin
            overcurrent_valid <= 1'b1;
        end else begin
            overcurrent_valid <= 1'b0;
        end

        // overvoltage (valid after INA226_READING_COUNT consecutive readings above the limit)
        if (ina226_result_ready) begin
            if (overvoltage_over_limit) begin
                if (overvoltage_counter < INA226_READING_COUNT) begin
                    overvoltage_counter <= overvoltage_counter + 1'b1;
                end
            end else begin
                overvoltage_counter <= 8'd0;
            end
        end

        if (overvoltage_counter >= INA226_READING_COUNT) begin
            overvoltage_valid <= 1'b1;
        end else begin
            overvoltage_valid <= 1'b0;
        end

        // undervoltage (valid after INA226_READING_COUNT consecutive readings below the limit)
        if (ina226_result_ready) begin
            if (undervoltage_under_limit) begin
                if (undervoltage_counter < INA226_READING_COUNT) begin
                    undervoltage_counter <= undervoltage_counter + 1'b1;
                end
            end else begin
                undervoltage_counter <= 8'd0;
            end
        end

        if (undervoltage_counter >= INA226_READING_COUNT) begin
            undervoltage_valid <= 1'b1;
        end else begin
            undervoltage_valid <= 1'b0;
        end

        // overtemperature (valid after OVERTEMP_READING_COUNT consecutive readings above the limit)
        if (overtemperature_result_ready) begin
            if (overtemperature_over_limit) begin
                if (overtemperature_counter < OVERTEMP_READING_COUNT) begin
                    overtemperature_counter <= overtemperature_counter + 1'b1;
                end
            end else begin
                overtemperature_counter <= 8'd0;
            end
        end

        if (overtemperature_counter >= OVERTEMP_READING_COUNT) begin
            overtemperature_valid <= 1'b1;
        end else begin
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

        // sensor_failure pin, temperature reader error or INA226 reader error (valid at >= 1 ms or 50000 clock cycles)
        if (sensor_failure_sync || temperature_error || measurement_error) begin
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