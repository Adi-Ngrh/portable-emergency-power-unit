`timescale 1ns / 1ps

// INA226 bus voltage and current reader over I2C (uses i2c_master.v from alexforencich/verilog-i2c, MIT license)
module ina226_reader #(
    parameter CLK_FREQ_HZ,
    parameter I2C_FREQ_HZ           = 100_000,  // I2C clock speed (INA226 supports up to 400 kHz)
    parameter INA226_ADDRESS        = 7'h40,    // 7-bit I2C address of the INA226 (0x40 when A0 and A1 are tied to GND)
    parameter SHUNT_RESISTANCE_MOHM = 10,       // shunt resistor value in milliohm (placeholder, must match the hardware)
    parameter CURRENT_LSB_UA        = 1000,     // current resolution in microampere per bit (1000 = 1 mA per bit)
    parameter CONFIG_VALUE          = 16'h4127, // configuration register (0x4127 = INA226 default: no averaging, 1.1 ms conversions, continuous)
    parameter CONVERSION_TIME_US    = 2500      // wait before reading, must be longer than one shunt + bus conversion (2 x 1.1 ms)
)(
    input  logic clk,
    input  logic reset_n,

    // I2C pins (open-drain: the FPGA only pulls low, the lines are pulled high by the hardware)
    inout  wire  scl,
    inout  wire  sda,

    // output signals
    output logic [15:0] bus_voltage,         // unsigned, 1 LSB = 1.25 mV
    output logic signed [15:0] current,      // signed, 1 LSB = CURRENT_LSB_UA microampere
    output logic measurement_valid,          // high for 1 clock when new bus_voltage and current values are available
    output logic measurement_error           // high while the last attempt failed (no answer, wrong data, timeout)
);

// INA226 register addresses
localparam logic [7:0] REG_CONFIGURATION = 8'h00;
localparam logic [7:0] REG_BUS_VOLTAGE   = 8'h02;
localparam logic [7:0] REG_CURRENT       = 8'h04;
localparam logic [7:0] REG_CALIBRATION   = 8'h05;

// calibration value from the INA226 datasheet, CAL = 0.00512 / (current_lsb * shunt_resistance), written in integer units
localparam logic [15:0] CALIBRATION_VALUE = 5_120_000 / (CURRENT_LSB_UA * SHUNT_RESISTANCE_MOHM);

// I2C speed setting for i2c_master: prescale = clock frequency / (I2C frequency * 4)
localparam logic [15:0] I2C_PRESCALE = CLK_FREQ_HZ / (I2C_FREQ_HZ * 4);

// timing in clock cycles
localparam integer CONVERSION_CYCLES = CONVERSION_TIME_US * (CLK_FREQ_HZ / 1_000_000);
localparam integer TIMEOUT_CYCLES    = CONVERSION_CYCLES + 20 * (CLK_FREQ_HZ / 1_000);  // one full measurement must finish within conversion time + 20 ms

// register operations the transaction engine can do
typedef enum logic
{
    OP_WRITE_REGISTER = 1'b0,  // write a 16-bit value into an INA226 register
    OP_READ_REGISTER  = 1'b1   // read a 16-bit value from an INA226 register
} op_type_e;

// transaction engine states (one register write or read)
typedef enum logic [3:0]
{
    TR_IDLE               = 4'd0,   // waiting for op_start
    TR_WRITE_SEND_COMMAND = 4'd1,   // write: command "write several bytes, then stop"
    TR_WRITE_SEND_POINTER = 4'd2,   // write: register address byte
    TR_WRITE_SEND_MSB     = 4'd3,   // write: value high byte
    TR_WRITE_SEND_LSB     = 4'd4,   // write: value low byte (last byte)
    TR_READ_SEND_COMMAND  = 4'd5,   // read: command "write 1 byte, no stop"
    TR_READ_SEND_POINTER  = 4'd6,   // read: register address byte
    TR_READ_REQUEST_MSB   = 4'd7,   // read: command "read 1 byte"
    TR_READ_WAIT_MSB      = 4'd8,   // read: waiting for the high byte
    TR_READ_REQUEST_LSB   = 4'd9,   // read: command "read 1 byte, then stop"
    TR_READ_WAIT_LSB      = 4'd10,  // read: waiting for the low byte
    TR_WAIT_BUS_IDLE      = 4'd11   // waiting for the I2C master to finish (stop condition sent)
} tr_state_e;

// sequence states (one full measurement)
typedef enum logic [2:0]
{
    SEQ_START             = 3'd0,  // start a new measurement
    SEQ_WRITE_CONFIG      = 3'd1,  // writing the configuration register
    SEQ_WRITE_CALIBRATION = 3'd2,  // writing the calibration register
    SEQ_CHECK_CALIBRATION = 3'd3,  // reading the calibration register back to check the connection
    SEQ_WAIT_CONVERSION   = 3'd4,  // waiting for a fresh conversion
    SEQ_READ_BUS_VOLTAGE  = 3'd5,  // reading the bus voltage register
    SEQ_READ_CURRENT      = 3'd6,  // reading the current register
    SEQ_UPDATE_OUTPUTS    = 3'd7   // updating the outputs
} seq_state_e;

// synchronizer registers for the I2C pins
logic scl_raw, scl_sync;
logic sda_raw, sda_sync;

// signals between this module and i2c_master
logic i2c_reset;            // high for 1 clock to reset i2c_master after a timeout
logic i2c_master_rst;       // i2c_master uses an active-high reset
logic cmd_read;
logic cmd_write;
logic cmd_write_multiple;
logic cmd_stop;
logic cmd_valid;
logic cmd_ready;
logic [7:0] tx_data;
logic tx_valid;
logic tx_last;
logic tx_ready;
logic [7:0] rx_data;
logic rx_valid;
logic rx_last;
logic scl_o;
logic sda_o;
logic i2c_busy;
logic i2c_missed_ack;       // high for 1 clock when the INA226 did not acknowledge a byte

// interface between the sequence FSM and the transaction engine
logic op_start;             // high for 1 clock to start a register operation
op_type_e op_type;          // write or read
logic [7:0] op_register;    // INA226 register address
logic [15:0] op_write_value;// value to write for OP_WRITE_REGISTER
logic op_done;              // high for 1 clock when the operation is finished
logic op_failed;            // result of the operation: 1 = the INA226 did not acknowledge
logic [15:0] op_read_value; // value read by OP_READ_REGISTER

// transaction engine registers
tr_state_e tr_state;

// sequence FSM registers
seq_state_e seq_state;
logic [31:0] wait_counter;      // counts clock cycles during the conversion wait
logic [31:0] timeout_counter;   // counts clock cycles since the start of the current measurement
logic [15:0] bus_voltage_reading;
logic [15:0] current_reading;

// pin drivers: release the line for 1, pull it low for 0
assign scl = scl_o ? 1'bz : 1'b0;
assign sda = sda_o ? 1'bz : 1'b0;

assign i2c_master_rst = !reset_n || i2c_reset;





// I2C master instance (bit-level I2C timing is handled inside this module)
i2c_master u_i2c_master (
    .clk                       (clk),
    .rst                       (i2c_master_rst),

    .s_axis_cmd_address        (INA226_ADDRESS),
    .s_axis_cmd_start          (1'b0),
    .s_axis_cmd_read           (cmd_read),
    .s_axis_cmd_write          (cmd_write),
    .s_axis_cmd_write_multiple (cmd_write_multiple),
    .s_axis_cmd_stop           (cmd_stop),
    .s_axis_cmd_valid          (cmd_valid),
    .s_axis_cmd_ready          (cmd_ready),

    .s_axis_data_tdata         (tx_data),
    .s_axis_data_tvalid        (tx_valid),
    .s_axis_data_tready        (tx_ready),
    .s_axis_data_tlast         (tx_last),

    .m_axis_data_tdata         (rx_data),
    .m_axis_data_tvalid        (rx_valid),
    .m_axis_data_tready        (1'b1),
    .m_axis_data_tlast         (rx_last),

    .scl_i                     (scl_sync),
    .scl_o                     (scl_o),
    .scl_t                     (),
    .sda_i                     (sda_sync),
    .sda_o                     (sda_o),
    .sda_t                     (),

    .busy                      (i2c_busy),
    .bus_control               (),
    .bus_active                (),
    .missed_ack                (i2c_missed_ack),

    .prescale                  (I2C_PRESCALE),
    .stop_on_idle              (1'b0)
);





// 2-stage synchronizer for the I2C pins (reset to 1 because idle lines are high)
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        scl_raw <= 1'b1;
        scl_sync <= 1'b1;
        sda_raw <= 1'b1;
        sda_sync <= 1'b1;
    end
    else begin
        scl_raw <= scl;
        scl_sync <= scl_raw;
        sda_raw <= sda;
        sda_sync <= sda_raw;
    end
end





// transaction engine: one register write or read through i2c_master (a transfer happens when valid and ready are both high)
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        tr_state <= TR_IDLE;
        op_done <= 1'b0;
        op_failed <= 1'b0;
        op_read_value <= 16'd0;
        cmd_read <= 1'b0;
        cmd_write <= 1'b0;
        cmd_write_multiple <= 1'b0;
        cmd_stop <= 1'b0;
        cmd_valid <= 1'b0;
        tx_data <= 8'd0;
        tx_valid <= 1'b0;
        tx_last <= 1'b0;
    end
    else if (i2c_reset) begin
        tr_state <= TR_IDLE;
        op_done <= 1'b0;
        cmd_valid <= 1'b0;
        tx_valid <= 1'b0;
        tx_last <= 1'b0;
    end
    else begin
        // default value for 1-clock pulse
        op_done <= 1'b0;

        // remember if any byte of this operation was not acknowledged
        if (i2c_missed_ack) begin
            op_failed <= 1'b1;
        end

        case (tr_state)
            TR_IDLE: begin
                if (op_start) begin
                    op_failed <= 1'b0;
                    if (op_type == OP_WRITE_REGISTER) begin
                        cmd_read <= 1'b0;
                        cmd_write <= 1'b0;
                        cmd_write_multiple <= 1'b1;
                        cmd_stop <= 1'b1;
                        cmd_valid <= 1'b1;
                        tr_state <= TR_WRITE_SEND_COMMAND;
                    end
                    else begin
                        cmd_read <= 1'b0;
                        cmd_write <= 1'b1;
                        cmd_write_multiple <= 1'b0;
                        cmd_stop <= 1'b0;
                        cmd_valid <= 1'b1;
                        tr_state <= TR_READ_SEND_COMMAND;
                    end
                end
            end

            TR_WRITE_SEND_COMMAND: begin
                if (cmd_valid && cmd_ready) begin
                    cmd_valid <= 1'b0;
                    tx_data <= op_register;
                    tx_last <= 1'b0;
                    tx_valid <= 1'b1;
                    tr_state <= TR_WRITE_SEND_POINTER;
                end
            end

            TR_WRITE_SEND_POINTER: begin
                if (tx_valid && tx_ready) begin
                    tx_data <= op_write_value[15:8];
                    tx_last <= 1'b0;
                    tr_state <= TR_WRITE_SEND_MSB;
                end
            end

            TR_WRITE_SEND_MSB: begin
                if (tx_valid && tx_ready) begin
                    tx_data <= op_write_value[7:0];
                    tx_last <= 1'b1;  // last byte, i2c_master sends stop after it
                    tr_state <= TR_WRITE_SEND_LSB;
                end
            end

            TR_WRITE_SEND_LSB: begin
                if (tx_valid && tx_ready) begin
                    tx_valid <= 1'b0;
                    tx_last <= 1'b0;
                    tr_state <= TR_WAIT_BUS_IDLE;
                end
            end

            TR_READ_SEND_COMMAND: begin
                if (cmd_valid && cmd_ready) begin
                    cmd_valid <= 1'b0;
                    tx_data <= op_register;
                    tx_last <= 1'b1;
                    tx_valid <= 1'b1;
                    tr_state <= TR_READ_SEND_POINTER;
                end
            end

            TR_READ_SEND_POINTER: begin
                if (tx_valid && tx_ready) begin
                    tx_valid <= 1'b0;
                    tx_last <= 1'b0;
                    cmd_read <= 1'b1;
                    cmd_write <= 1'b0;
                    cmd_write_multiple <= 1'b0;
                    cmd_stop <= 1'b0;
                    cmd_valid <= 1'b1;
                    tr_state <= TR_READ_REQUEST_MSB;
                end
            end

            TR_READ_REQUEST_MSB: begin
                if (cmd_valid && cmd_ready) begin
                    cmd_valid <= 1'b0;
                    tr_state <= TR_READ_WAIT_MSB;
                end
            end

            TR_READ_WAIT_MSB: begin
                if (rx_valid) begin
                    op_read_value[15:8] <= rx_data;
                    cmd_read <= 1'b1;
                    cmd_stop <= 1'b1;  // i2c_master sends stop after the low byte
                    cmd_valid <= 1'b1;
                    tr_state <= TR_READ_REQUEST_LSB;
                end
            end

            TR_READ_REQUEST_LSB: begin
                if (cmd_valid && cmd_ready) begin
                    cmd_valid <= 1'b0;
                    tr_state <= TR_READ_WAIT_LSB;
                end
            end

            TR_READ_WAIT_LSB: begin
                if (rx_valid) begin
                    op_read_value[7:0] <= rx_data;
                    tr_state <= TR_WAIT_BUS_IDLE;
                end
            end

            TR_WAIT_BUS_IDLE: begin
                if (!i2c_busy) begin
                    op_done <= 1'b1;
                    tr_state <= TR_IDLE;
                end
            end

            default: begin
                tr_state <= TR_IDLE;
            end
        endcase
    end
end





// sequence FSM: write config, write calibration, check calibration, wait, read bus voltage, read current, repeat
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        seq_state <= SEQ_START;
        op_start <= 1'b0;
        op_type <= OP_WRITE_REGISTER;
        op_register <= 8'd0;
        op_write_value <= 16'd0;
        wait_counter <= 32'd0;
        timeout_counter <= 32'd0;
        i2c_reset <= 1'b0;
        bus_voltage_reading <= 16'd0;
        current_reading <= 16'd0;
        bus_voltage <= 16'd0;
        current <= 16'sd0;
        measurement_valid <= 1'b0;
        measurement_error <= 1'b0;
    end
    else begin
        // default values for 1-clock pulses
        op_start <= 1'b0;
        i2c_reset <= 1'b0;
        measurement_valid <= 1'b0;

        if (seq_state != SEQ_START && timeout_counter == TIMEOUT_CYCLES - 1) begin
            measurement_error <= 1'b1;  // measurement took too long (for example a stuck I2C line), reset i2c_master and start over
            i2c_reset <= 1'b1;
            timeout_counter <= 32'd0;
            seq_state <= SEQ_START;
        end
        else begin
            if (seq_state == SEQ_START) begin
                timeout_counter <= 32'd0;
            end
            else begin
                timeout_counter <= timeout_counter + 1'b1;
            end

            case (seq_state)
                SEQ_START: begin
                    op_type <= OP_WRITE_REGISTER;
                    op_register <= REG_CONFIGURATION;
                    op_write_value <= CONFIG_VALUE;
                    op_start <= 1'b1;
                    seq_state <= SEQ_WRITE_CONFIG;
                end

                SEQ_WRITE_CONFIG: begin
                    if (op_done) begin
                        if (op_failed) begin
                            measurement_error <= 1'b1;  // INA226 did not answer
                            seq_state <= SEQ_START;
                        end
                        else begin
                            op_type <= OP_WRITE_REGISTER;
                            op_register <= REG_CALIBRATION;
                            op_write_value <= CALIBRATION_VALUE;
                            op_start <= 1'b1;
                            seq_state <= SEQ_WRITE_CALIBRATION;
                        end
                    end
                end

                SEQ_WRITE_CALIBRATION: begin
                    if (op_done) begin
                        if (op_failed) begin
                            measurement_error <= 1'b1;  // INA226 did not answer
                            seq_state <= SEQ_START;
                        end
                        else begin
                            op_type <= OP_READ_REGISTER;
                            op_register <= REG_CALIBRATION;
                            op_start <= 1'b1;
                            seq_state <= SEQ_CHECK_CALIBRATION;
                        end
                    end
                end

                SEQ_CHECK_CALIBRATION: begin
                    if (op_done) begin
                        if (op_failed || op_read_value != CALIBRATION_VALUE) begin
                            measurement_error <= 1'b1;  // no answer or wrong value read back (for example SDA stuck low)
                            seq_state <= SEQ_START;
                        end
                        else begin
                            wait_counter <= 32'd0;
                            seq_state <= SEQ_WAIT_CONVERSION;
                        end
                    end
                end

                SEQ_WAIT_CONVERSION: begin
                    if (wait_counter == CONVERSION_CYCLES - 1) begin
                        op_type <= OP_READ_REGISTER;
                        op_register <= REG_BUS_VOLTAGE;
                        op_start <= 1'b1;
                        seq_state <= SEQ_READ_BUS_VOLTAGE;
                    end
                    else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end

                SEQ_READ_BUS_VOLTAGE: begin
                    if (op_done) begin
                        if (op_failed) begin
                            measurement_error <= 1'b1;  // INA226 did not answer
                            seq_state <= SEQ_START;
                        end
                        else begin
                            bus_voltage_reading <= op_read_value;
                            op_type <= OP_READ_REGISTER;
                            op_register <= REG_CURRENT;
                            op_start <= 1'b1;
                            seq_state <= SEQ_READ_CURRENT;
                        end
                    end
                end

                SEQ_READ_CURRENT: begin
                    if (op_done) begin
                        if (op_failed) begin
                            measurement_error <= 1'b1;  // INA226 did not answer
                            seq_state <= SEQ_START;
                        end
                        else begin
                            current_reading <= op_read_value;
                            seq_state <= SEQ_UPDATE_OUTPUTS;
                        end
                    end
                end

                SEQ_UPDATE_OUTPUTS: begin
                    bus_voltage <= bus_voltage_reading;
                    current <= current_reading;
                    measurement_valid <= 1'b1;
                    measurement_error <= 1'b0;
                    seq_state <= SEQ_START;
                end

                default: begin
                    seq_state <= SEQ_START;
                end
            endcase
        end
    end
end

endmodule
