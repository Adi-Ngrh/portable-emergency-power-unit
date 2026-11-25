`timescale 1ns / 1ps

// DS18B20 temperature reader over 1-Wire (single sensor on the line, externally powered)
module ds18b20_reader #(
    parameter CLK_FREQ_HZ,
    parameter CONVERSION_TIME_MS = 750  // time to wait for a temperature conversion (750 ms = DS18B20 worst case at 12-bit)
)(
    input  logic clk,
    input  logic reset_n,

    // 1-Wire data pin (needs an external 4.7k pull-up resistor to 3.3V)
    inout  wire  dq,

    // output signals
    output logic signed [15:0] temperature,  // signed, 1 LSB = 1/16 °C
    output logic temperature_valid,          // high for 1 clock when a new good reading is available
    output logic temperature_error           // high while the last attempt failed (no sensor, line stuck low, CRC error)
);

// DS18B20 commands
localparam logic [7:0] CMD_SKIP_ROM        = 8'hCC;
localparam logic [7:0] CMD_CONVERT_T       = 8'h44;
localparam logic [7:0] CMD_READ_SCRATCHPAD = 8'hBE;

// 1-Wire timing (from DS18B20 datasheet), converted from microseconds to clock cycles
localparam integer CLOCKS_PER_US         = CLK_FREQ_HZ / 1_000_000;
localparam integer RESET_LOW_CYCLES      = 480 * CLOCKS_PER_US;  // reset pulse: line low for 480 us
localparam integer RESET_SAMPLE_CYCLES   = 550 * CLOCKS_PER_US;  // check presence pulse 70 us after releasing the line
localparam integer RESET_TOTAL_CYCLES    = 960 * CLOCKS_PER_US;  // reset slot total length
localparam integer WRITE_0_LOW_CYCLES    = 60  * CLOCKS_PER_US;  // write 0: line low for 60 us
localparam integer WRITE_1_LOW_CYCLES    = 6   * CLOCKS_PER_US;  // write 1: line low for 6 us
localparam integer READ_LOW_CYCLES       = 6   * CLOCKS_PER_US;  // read: line low for 6 us to start the slot
localparam integer READ_SAMPLE_CYCLES    = 12  * CLOCKS_PER_US;  // read: sample the line 12 us after slot start (must be before 15 us)
localparam integer BIT_SLOT_TOTAL_CYCLES = 70  * CLOCKS_PER_US;  // write/read slot total length (includes recovery time)
localparam integer CONVERSION_CYCLES     = CONVERSION_TIME_MS * (CLK_FREQ_HZ / 1_000);

// operations the 1-Wire engine can do
typedef enum logic [1:0]
{
    OP_RESET      = 2'd0,  // reset pulse + presence check
    OP_WRITE_BYTE = 2'd1,  // send 8 bits, LSB first
    OP_READ_BYTE  = 2'd2   // receive 8 bits, LSB first
} op_type_e;

// sequence states (one full temperature reading)
typedef enum logic [3:0]
{
    SEQ_START            = 4'd0,  // check that the line is idle (high), then send reset
    SEQ_RESET_1          = 4'd1,  // reset before starting a conversion
    SEQ_SKIP_ROM_1       = 4'd2,  // sending Skip ROM command
    SEQ_CONVERT_T        = 4'd3,  // sending Convert T command
    SEQ_WAIT_CONVERSION  = 4'd4,  // waiting for the sensor to finish converting
    SEQ_RESET_2          = 4'd5,  // reset before reading the result
    SEQ_SKIP_ROM_2       = 4'd6,  // sending Skip ROM command
    SEQ_READ_SCRATCHPAD  = 4'd7,  // sending Read Scratchpad command
    SEQ_READ_DATA        = 4'd8,  // reading the 9 scratchpad bytes
    SEQ_CHECK_CRC        = 4'd9   // checking CRC and updating the outputs
} seq_state_e;

// synchronizer registers for the data pin
logic dq_raw, dq_sync;

// pin driver: the FPGA only pulls the line low or releases it, the pull-up resistor makes it high
logic dq_drive_low;
assign dq = dq_drive_low ? 1'b0 : 1'bz;

// interface between the sequence FSM and the 1-Wire engine
logic op_start;            // high for 1 clock to start an operation
op_type_e op_type;         // which operation to start
logic [7:0] op_write_byte; // byte to send for OP_WRITE_BYTE
logic op_done;             // high for 1 clock when the operation is finished
logic [7:0] op_read_byte;  // byte received by OP_READ_BYTE
logic presence_detected;   // result of OP_RESET: 1 = sensor answered

// 1-Wire engine registers
logic op_busy;
op_type_e op_type_reg;
logic [7:0] shift_reg;     // bits to send or bits received
logic [2:0] bit_index;     // which bit of the byte is being handled
logic [15:0] slot_counter; // clock cycles since start of the current slot (enough for 960 us up to 68 MHz)
logic [15:0] slot_low_cycles;
logic [15:0] slot_sample_cycles;
logic [15:0] slot_total_cycles;
logic bit_read_strobe;     // high for 1 clock when a bit is read from the sensor
logic bit_read_value;      // value of that bit

// sequence FSM registers
seq_state_e seq_state;
logic [31:0] wait_counter;      // counts clock cycles during the conversion wait
logic [3:0] byte_index;         // which scratchpad byte is being read (0 to 8)
logic [7:0] temperature_low_byte;
logic [7:0] temperature_high_byte;
logic [7:0] config_byte;        // scratchpad byte 4, its lowest 5 bits are always 1 on a real DS18B20

// CRC registers
logic [7:0] crc;
logic crc_clear;

assign op_read_byte = shift_reg;





// 2-stage synchronizer for the data pin (reset to 1 because the idle line is high)
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        dq_raw <= 1'b1;
        dq_sync <= 1'b1;
    end
    else begin
        dq_raw <= dq;
        dq_sync <= dq_raw;
    end
end





// slot timing for the current operation
always_comb begin
    case (op_type_reg)
        OP_RESET: begin
            slot_low_cycles    = RESET_LOW_CYCLES;
            slot_sample_cycles = RESET_SAMPLE_CYCLES;
            slot_total_cycles  = RESET_TOTAL_CYCLES;
        end
        OP_WRITE_BYTE: begin
            if (shift_reg[0] == 1'b1) begin
                slot_low_cycles = WRITE_1_LOW_CYCLES;
            end
            else begin
                slot_low_cycles = WRITE_0_LOW_CYCLES;
            end
            slot_sample_cycles = 16'd0;  // not used when writing
            slot_total_cycles  = BIT_SLOT_TOTAL_CYCLES;
        end
        default: begin  // OP_READ_BYTE
            slot_low_cycles    = READ_LOW_CYCLES;
            slot_sample_cycles = READ_SAMPLE_CYCLES;
            slot_total_cycles  = BIT_SLOT_TOTAL_CYCLES;
        end
    endcase
end





// 1-Wire engine: runs one operation at a time (reset, write byte or read byte)
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        op_busy <= 1'b0;
        op_done <= 1'b0;
        op_type_reg <= OP_RESET;
        shift_reg <= 8'd0;
        bit_index <= 3'd0;
        slot_counter <= 16'd0;
        presence_detected <= 1'b0;
        bit_read_strobe <= 1'b0;
        bit_read_value <= 1'b0;
        dq_drive_low <= 1'b0;
    end
    else begin
        // default values for 1-clock pulses
        op_done <= 1'b0;
        bit_read_strobe <= 1'b0;

        if (!op_busy) begin
            dq_drive_low <= 1'b0;
            if (op_start) begin
                op_busy <= 1'b1;
                op_type_reg <= op_type;
                shift_reg <= op_write_byte;
                bit_index <= 3'd0;
                slot_counter <= 16'd0;
            end
        end
        else begin
            // pull the line low at the start of the slot, then release it
            if (slot_counter < slot_low_cycles) begin
                dq_drive_low <= 1'b1;
            end
            else begin
                dq_drive_low <= 1'b0;
            end

            // sample the line at the sample point
            if (slot_counter == slot_sample_cycles) begin
                if (op_type_reg == OP_RESET) begin
                    presence_detected <= ~dq_sync;  // sensor answers by pulling the line low
                end
                else if (op_type_reg == OP_READ_BYTE) begin
                    shift_reg <= {dq_sync, shift_reg[7:1]};  // bits arrive LSB first
                    bit_read_value <= dq_sync;
                    bit_read_strobe <= 1'b1;
                end
            end

            // end of the slot
            if (slot_counter == slot_total_cycles - 1) begin
                slot_counter <= 16'd0;
                if (op_type_reg == OP_RESET || bit_index == 3'd7) begin
                    op_busy <= 1'b0;
                    op_done <= 1'b1;
                end
                else begin
                    bit_index <= bit_index + 1'b1;
                    if (op_type_reg == OP_WRITE_BYTE) begin
                        shift_reg <= {1'b0, shift_reg[7:1]};  // move the next bit to send into shift_reg[0]
                    end
                end
            end
            else begin
                slot_counter <= slot_counter + 1'b1;
            end
        end
    end
end





// CRC-8 used by DS18B20 (polynomial x^8 + x^5 + x^4 + 1), updated on every bit read
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        crc <= 8'd0;
    end
    else if (crc_clear) begin
        crc <= 8'd0;
    end
    else if (bit_read_strobe) begin
        if ((crc[0] ^ bit_read_value) == 1'b1) begin
            crc <= {1'b0, crc[7:1]} ^ 8'h8C;
        end
        else begin
            crc <= {1'b0, crc[7:1]};
        end
    end
end





// sequence FSM: reset, convert, wait, reset, read scratchpad, check CRC, repeat
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        seq_state <= SEQ_START;
        op_start <= 1'b0;
        op_type <= OP_RESET;
        op_write_byte <= 8'd0;
        wait_counter <= 32'd0;
        byte_index <= 4'd0;
        temperature_low_byte <= 8'd0;
        temperature_high_byte <= 8'd0;
        config_byte <= 8'd0;
        crc_clear <= 1'b0;
        temperature <= 16'sd0;
        temperature_valid <= 1'b0;
        temperature_error <= 1'b0;
    end
    else begin
        // default values for 1-clock pulses
        op_start <= 1'b0;
        crc_clear <= 1'b0;
        temperature_valid <= 1'b0;

        case (seq_state)
            SEQ_START: begin
                if (dq_sync == 1'b1) begin
                    op_type <= OP_RESET;
                    op_start <= 1'b1;
                    seq_state <= SEQ_RESET_1;
                end
                else begin
                    temperature_error <= 1'b1;  // line stuck low, keep checking until it is released
                end
            end

            SEQ_RESET_1: begin
                if (op_done) begin
                    if (presence_detected) begin
                        op_type <= OP_WRITE_BYTE;
                        op_write_byte <= CMD_SKIP_ROM;
                        op_start <= 1'b1;
                        seq_state <= SEQ_SKIP_ROM_1;
                    end
                    else begin
                        temperature_error <= 1'b1;  // no sensor answered
                        seq_state <= SEQ_START;
                    end
                end
            end

            SEQ_SKIP_ROM_1: begin
                if (op_done) begin
                    op_type <= OP_WRITE_BYTE;
                    op_write_byte <= CMD_CONVERT_T;
                    op_start <= 1'b1;
                    seq_state <= SEQ_CONVERT_T;
                end
            end

            SEQ_CONVERT_T: begin
                if (op_done) begin
                    wait_counter <= 32'd0;
                    seq_state <= SEQ_WAIT_CONVERSION;
                end
            end

            SEQ_WAIT_CONVERSION: begin
                if (wait_counter == CONVERSION_CYCLES - 1) begin
                    if (dq_sync == 1'b1) begin
                        op_type <= OP_RESET;
                        op_start <= 1'b1;
                        seq_state <= SEQ_RESET_2;
                    end
                    else begin
                        temperature_error <= 1'b1;  // line stuck low
                        seq_state <= SEQ_START;
                    end
                end
                else begin
                    wait_counter <= wait_counter + 1'b1;
                end
            end

            SEQ_RESET_2: begin
                if (op_done) begin
                    if (presence_detected) begin
                        op_type <= OP_WRITE_BYTE;
                        op_write_byte <= CMD_SKIP_ROM;
                        op_start <= 1'b1;
                        seq_state <= SEQ_SKIP_ROM_2;
                    end
                    else begin
                        temperature_error <= 1'b1;  // no sensor answered
                        seq_state <= SEQ_START;
                    end
                end
            end

            SEQ_SKIP_ROM_2: begin
                if (op_done) begin
                    op_type <= OP_WRITE_BYTE;
                    op_write_byte <= CMD_READ_SCRATCHPAD;
                    op_start <= 1'b1;
                    seq_state <= SEQ_READ_SCRATCHPAD;
                end
            end

            SEQ_READ_SCRATCHPAD: begin
                if (op_done) begin
                    byte_index <= 4'd0;
                    crc_clear <= 1'b1;
                    op_type <= OP_READ_BYTE;
                    op_start <= 1'b1;
                    seq_state <= SEQ_READ_DATA;
                end
            end

            SEQ_READ_DATA: begin
                if (op_done) begin
                    if (byte_index == 4'd0) begin
                        temperature_low_byte <= op_read_byte;
                    end
                    if (byte_index == 4'd1) begin
                        temperature_high_byte <= op_read_byte;
                    end
                    if (byte_index == 4'd4) begin
                        config_byte <= op_read_byte;
                    end

                    if (byte_index == 4'd8) begin
                        seq_state <= SEQ_CHECK_CRC;  // all 9 bytes received (byte 8 is the CRC)
                    end
                    else begin
                        byte_index <= byte_index + 1'b1;
                        op_type <= OP_READ_BYTE;
                        op_start <= 1'b1;
                    end
                end
            end

            SEQ_CHECK_CRC: begin
                // CRC over all 9 bytes is 0 when data is correct, config check rejects all-zero data (line stuck low)
                if (crc == 8'd0 && config_byte[4:0] == 5'b11111) begin
                    temperature <= {temperature_high_byte, temperature_low_byte};
                    temperature_valid <= 1'b1;
                    temperature_error <= 1'b0;
                end
                else begin
                    temperature_error <= 1'b1;  // bad data, keep the previous temperature
                end
                seq_state <= SEQ_START;
            end

            default: begin
                seq_state <= SEQ_START;
            end
        endcase
    end
end

endmodule
