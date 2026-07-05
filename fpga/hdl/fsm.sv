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
	// reset button bypass other logics (active-low)
	if (!reset_n) begin
		current_state <= OFF;
	end else begin
		current_state <= next_state;
	end
end

// block to set next state
always_comb begin
	// default assignment
	next_state = current_state; 
	system_enable = 1'b0;
	warning_led = 1'b0;
	shutdown_signal = 1'b0;
	buzzer_alert = 1'b0;
	recovery_mode = 1'b0;
	state_debug_bus = current_state; // Output the current state to the debug pins

	// state evaluation
	case (current_state)
		
		OFF: begin
			 if (charger_connected) begin
				  next_state = BOOT;
			 end
		end

		BOOT: begin
			 system_enable = 1'b1; 
			 next_state = NORMAL; 
		end

		NORMAL: begin
			 system_enable = 1'b1;
			 if (battery_critical || overcurrent) begin
				  next_state = CRITICAL;
			 end else if (battery_low || overtemp) begin
				  next_state = WARNING;
			 end else if (manual_shutdown) begin
				  next_state = SHUTDOWN;
			 end
		end

		WARNING: begin
			 system_enable = 1'b1;
			 warning_led = 1'b1; // turn on warning LED
			 if (battery_critical || overcurrent) begin
				  next_state = CRITICAL;
			 end else if (!battery_low && !overtemp) begin
				  next_state = NORMAL;
			 end
		end

		CRITICAL: begin
			 // give signs and wait for manual shutdown
			 shutdown_signal = 1'b1;
			 warning_led = 1'b1;
			 buzzer_alert = 1'b1;
			 if (manual_shutdown) begin
				  next_state = SHUTDOWN;
			 end
		end

		SHUTDOWN: begin
			 // disable the system
			 system_enable = 1'b0;
			 if (charger_connected) begin
				  next_state = RECOVERY;
			 end
		end

		RECOVERY: begin
			 recovery_mode = 1'b1;
			 // Wait until battery is no longer critical to resume operations
			 if (!battery_critical && !battery_low) begin
				  next_state = NORMAL;
			 end
		end

		default: begin
			 // turn off system if the current state is invalid
			 next_state = OFF;
		end
		
	endcase
end

endmodule