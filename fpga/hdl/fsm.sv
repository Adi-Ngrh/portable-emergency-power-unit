module power_state_machine(
	input logic battery_low,
	input logic battery_critical,
	input logic overtemp,
	input logic overcurrent,
	input logic charger_connected,
	input logic manual_shutdown,
	input logic reset_n,
	input logic clk,
	
	output logic system_enable,
	output logic warning_led,
	output logic shutdown_signal,
	output logic buzzer_alert,
	output logic recovery_mode,
	output logic state_debug_bus
);

// variable to store states (one-hot encoded)
typedef enum logic [6:0] 
{
	OFF       = 7'b0000001,
	BOOT      = 7'b0000010,
	NORMAL    = 7'b0000100,
	WARNING   = 7'b0001000,
	CRITICAL  = 7'b0010000,
	SHUTDOWN  = 7'b0100000,
	RECOVERY  = 7'b1000000
} state_t;

state_t current_state;
state_t next_state;

// block to update current state on clock edge or reset signal
always_ff @(posedge clk or negedge reset_n) begin
	// reset button bypass other logics
	if (!reset_n) begin
		current_state <= OFF;
	end else begin
		current_state <= next_state;
	end
end

// block to set next state
always_comb begin

end

endmodule