`timescale 1ns / 1ps

// FPGA heartbeat: toggles an output at a fixed rate so the MCU can see the FPGA is running
module fpga_heartbeat #(
    parameter CLK_FREQ_HZ,
    parameter HALF_PERIOD_MS = 250  // time between toggles (the MCU treats 3 s without a toggle as FPGA dead)
)(
    input  logic clk,
    input  logic reset_n,

    // output signal
    output logic heartbeat  // toggles every HALF_PERIOD_MS, held low during reset
);

// half period converted from milliseconds to clock cycles
localparam integer HALF_PERIOD_CYCLES = HALF_PERIOD_MS * (CLK_FREQ_HZ / 1_000);

// clock cycles since the last toggle (28 bits = up to about 9.9 s at 27 MHz)
logic [27:0] toggle_counter;





// toggle block
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        toggle_counter <= 28'd0;
        heartbeat      <= 1'b0;
    end
    else if (toggle_counter == HALF_PERIOD_CYCLES - 1) begin
        toggle_counter <= 28'd0;
        heartbeat      <= ~heartbeat;
    end
    else begin
        toggle_counter <= toggle_counter + 1'b1;
    end
end

endmodule
