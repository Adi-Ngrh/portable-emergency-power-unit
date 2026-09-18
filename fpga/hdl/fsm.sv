module power_state_machine(
	input logic boot_success,
	input logic battery_low,
	input logic battery_critical,
	input logic overtemp,
	input logic overcurrent,
	input logic charger_connected,
	input logic manual_power,
	input logic manual_shutdown,
	input logic reset_n,
	input logic clk,
	
	output logic system_enable,
	output logic warning_led,
	output logic shutdown_signal,
	output logic buzzer_alert,
	output logic recovery_mode,
	output logic [6:0] state_debug_bus
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

// synchronizer registers
logic boot_success_raw, boot_success_sync;
logic battery_low_raw, battery_low_sync;
logic battery_critical_raw, battery_critical_sync;
logic overtemp_raw, overtemp_sync;
logic overcurrent_raw, overcurrent_sync;
logic charger_connected_raw, charger_connected_sync;
logic manual_power_raw, manual_power_sync, manual_power_sync_prev;
logic manual_shutdown_raw, manual_shutdown_sync;

// timer related variables
logic timer_start;
logic [28:0] timer_counter;
logic [28:0] timer_threshold;
logic timer_finish;

// temporary outputs registers
logic system_enable_next;
logic warning_led_next;
logic shutdown_signal_next;
logic buzzer_alert_next;
logic recovery_mode_next;
state_t state_debug_bus_next;

logic battery_fault_latch;	// differentiate battery related fault
logic manual_power_pressed; // when boot fail, keep system at OFF state until fresh trigger





// 2-stage synchronizer block for external inputs
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		boot_success_raw <= 1'b0; 
		boot_success_sync <= 1'b0;
		battery_low_raw <= 1'b0;
		battery_low_sync <= 1'b0;
		battery_critical_raw <= 1'b0;
		battery_critical_sync <= 1'b0;
		overtemp_raw <= 1'b0;
		overtemp_sync <= 1'b0;
		overcurrent_raw <= 1'b0;
		overcurrent_sync <= 1'b0;
		charger_connected_raw <= 1'b0;
		charger_connected_sync <= 1'b0;
		manual_power_raw <= 1'b0;
		manual_power_sync <= 1'b0;
		manual_power_sync_prev <= 1'b0;
		manual_shutdown_raw <= 1'b0;
		manual_shutdown_sync <= 1'b0;
	end else begin
		// Stage 1: Capture raw inputs (susceptible to metastability)
		boot_success_raw <= boot_success;
		battery_low_raw <= battery_low;
		battery_critical_raw <= battery_critical;
		overtemp_raw <= overtemp;
		overcurrent_raw <= overcurrent;
		charger_connected_raw <= charger_connected;
		manual_power_raw <= manual_power;
		manual_shutdown_raw <= manual_shutdown;
		
		// Stage 2: Capture settled signals
		boot_success_sync <= boot_success_raw;
		battery_low_sync <= battery_low_raw;
		battery_critical_sync <= battery_critical_raw;
		overtemp_sync <= overtemp_raw;
		overcurrent_sync <= overcurrent_raw;
		charger_connected_sync <= charger_connected_raw;
		manual_power_sync <= manual_power_raw;
		manual_shutdown_sync <= manual_shutdown_raw;
		
		// record previous manual_power signal
		manual_power_sync_prev <= manual_power_sync;
	end
end

assign manual_power_pressed = manual_power_sync & ~manual_power_sync_prev;





// reusable timer block
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		timer_counter <= 29'b0;
		timer_finish <= 1'b0;
	end else if (!timer_start) begin
		timer_counter <= 29'b0;
		timer_finish <= 1'b0;
	end else if (timer_counter >= timer_threshold) begin
		timer_finish <= 1'b1;
	end else begin
		timer_counter <= timer_counter + 1'b1;
		timer_finish <= 1'b0;
	end
end





// block to set next state
always_comb begin
	// default assignment
	next_state = current_state; 
	system_enable_next = 1'b0;
	timer_start = 1'b0;
	timer_threshold = 29'd0;
	warning_led_next = 1'b0;
	shutdown_signal_next = 1'b0;
	buzzer_alert_next = 1'b0;
	recovery_mode_next = 1'b0;
	state_debug_bus_next = current_state;

	// state evaluation
	case (current_state)
            
		// OFF: Device is off. Transitions to BOOT when power button is manually pressed.
		OFF: begin
			if (manual_power_pressed) begin
				next_state = BOOT;
			end
		end

		// BOOT: Device is starting up. Transitions immediately to NORMAL once enabled.
		BOOT: begin
			// boot timeout (valid at >= 10 seconds or 500000000 clock cycles)
			timer_threshold = 29'd500000000;
			timer_start = 1'b1;
			if (boot_success_sync) begin
				next_state = NORMAL;
			end else if (timer_finish) begin
				next_state = OFF;
			end
		end

		// NORMAL: Device is fully operational. 
		// Transitions to CRITICAL if immediate danger (battery_critical/overcurrent).
		// Transitions to WARNING if non-immediate issue (battery_low/overtemp).
		// Transitions to SHUTDOWN if requested by user.
		NORMAL: begin
			 system_enable_next = 1'b1;
			 if (battery_critical_sync || overcurrent_sync) begin
				  next_state = CRITICAL;
			 end else if (battery_low_sync || overtemp_sync) begin
				  next_state = WARNING;
			 end else if (manual_shutdown_sync) begin
				  next_state = SHUTDOWN;
			 end
		end

		// WARNING: Non-immediate issue exists.
		// Transitions to CRITICAL if faults escalate.
		// Transitions back to NORMAL if all warnings clear.
		WARNING: begin
			 system_enable_next = 1'b1;
			 warning_led_next   = 1'b1;
			 if (battery_critical_sync || overcurrent_sync) begin
				  next_state = CRITICAL;
			 end else if (!battery_low_sync && !overtemp_sync) begin
				  next_state = NORMAL;
			 end
		end

		// CRITICAL: Immediate danger. Device asserts shutdown and alarms.
		// Transitions to SHUTDOWN only when acknowledged via manual_shutdown.
		CRITICAL: begin
			shutdown_signal_next = 1'b1;
			warning_led_next     = 1'b1;
			buzzer_alert_next    = 1'b1;
			if (manual_shutdown_sync || battery_fault_latch) begin
				next_state = SHUTDOWN;
			end
		end

		// SHUTDOWN: Device is in the process of turning off.
		// Transitions to RECOVERY if a charger is connected AND a battery fault caused the shutdown.
		SHUTDOWN: begin
			 if (charger_connected_sync && battery_fault_latch) begin
				  next_state = RECOVERY;
			 end
			 shutdown_signal_next = 1'b1;
		end

		// RECOVERY: Device charges safely while keeping main system disabled.
		// Transitions back to NORMAL once the battery is no longer low or critical.
		RECOVERY: begin
			 recovery_mode_next = 1'b1;
			 if (!battery_critical_sync && !battery_low_sync) begin
				  next_state = NORMAL;
			 end
		end

		default: begin
			 next_state = OFF;
		end
		
	endcase
end





// block to update current state on clock edge or reset signal
always_ff @(posedge clk or negedge reset_n) begin
	// reset button bypass other logics (active-low)
	if (!reset_n) begin
		battery_fault_latch <= 1'b0;
		current_state <= OFF;
	end else begin
		current_state <= next_state;
		
		// Latch battery faults to ensure RECOVERY is only used for dead batteries
		if (battery_critical_sync || battery_low_sync) begin
			battery_fault_latch <= 1'b1;
		end else if (next_state == NORMAL) begin
            battery_fault_latch <= 1'b0;
        end
	end
end





// block to update output signals on clock edge or reset signal
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		system_enable   <= 1'b0;
		warning_led     <= 1'b0;
		shutdown_signal <= 1'b0;
		buzzer_alert    <= 1'b0;
		recovery_mode   <= 1'b0;
		state_debug_bus <= OFF;
	end else begin
		system_enable   <= system_enable_next;
		warning_led     <= warning_led_next;
		shutdown_signal <= shutdown_signal_next;
		buzzer_alert    <= buzzer_alert_next;
		recovery_mode   <= recovery_mode_next;
		state_debug_bus <= state_debug_bus_next;
	end
end

endmodule