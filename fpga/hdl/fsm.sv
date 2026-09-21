module power_state_machine(
	input logic boot_success,
	input logic battery_low,
	input logic battery_critical,
	input logic overtemp,
	input logic overcurrent,
	input logic manual_power,
	input logic manual_shutdown,
	input logic shutdown_request,
	input logic shutdown_success,
	input logic reset_n,
	input logic clk,
	
	output logic system_enable,
	output logic warning_led,
	output logic shutdown_ack,
	output logic buzzer_alert,
	output logic recovery_mode,
	output logic [6:0] state_debug_bus
);

// variable to store states (one-hot encoded)
typedef enum logic [6:0] 
{
	STATE_OFF       = 7'b0000001,
	STATE_BOOT      = 7'b0000010,
	STATE_NORMAL    = 7'b0000100,
	STATE_WARNING   = 7'b0001000,
	STATE_CRITICAL  = 7'b0010000,
	STATE_SHUTDOWN  = 7'b0100000,
	STATE_RECOVERY  = 7'b1000000
} state_e;
state_e current_state;
state_e next_state;
state_e state_debug_bus_next;

// synchronizer registers
logic boot_success_raw, boot_success_sync;
logic battery_low_raw, battery_low_sync;
logic battery_critical_raw, battery_critical_sync;
logic overtemp_raw, overtemp_sync;
logic overcurrent_raw, overcurrent_sync;
logic manual_power_raw, manual_power_sync, manual_power_sync_prev;
logic manual_shutdown_raw, manual_shutdown_sync;
logic shutdown_request_raw, shutdown_request_sync;
logic shutdown_success_raw, shutdown_success_sync;

// timer related variables
logic timer_start;
logic [28:0] timer_counter;
logic [28:0] timer_threshold;
logic timer_finish;
localparam logic [28:0] boot_timeout = 29'd500_000_000;
localparam logic [28:0] shutdown_timeout = 29'd500_000_000;

// temporary outputs registers
logic system_enable_next;
logic warning_led_next;
logic shutdown_ack_next;
logic buzzer_alert_next;
logic recovery_mode_next;

logic battery_fault_latch;	// differentiate battery related fault
logic manual_power_pressed; // when boot fail, keep system at STATE_OFF state until fresh trigger

assign manual_power_pressed = manual_power_sync & ~manual_power_sync_prev;
assign shutdown_trigger = manual_shutdown_sync || shutdown_request_sync || battery_critical_sync;





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
		manual_power_raw <= 1'b0;
		manual_power_sync <= 1'b0;
		manual_power_sync_prev <= 1'b0;
		manual_shutdown_raw <= 1'b0;
		manual_shutdown_sync <= 1'b0;
		shutdown_request_raw <= 1'b0;
		shutdown_request_sync <= 1'b0;
		shutdown_success_raw <= 1'b0;
		shutdown_success_sync <= 1'b0;
	end 
	else begin
		// Stage 1: Capture raw inputs (susceptible to metastability)
		boot_success_raw <= boot_success;
		battery_low_raw <= battery_low;
		battery_critical_raw <= battery_critical;
		overtemp_raw <= overtemp;
		overcurrent_raw <= overcurrent;
		manual_power_raw <= manual_power;
		manual_shutdown_raw <= manual_shutdown;
		shutdown_request_raw <= shutdown_request;
		shutdown_success_raw <= shutdown_success;
		
		// Stage 2: Capture settled signals
		boot_success_sync <= boot_success_raw;
		battery_low_sync <= battery_low_raw;
		battery_critical_sync <= battery_critical_raw;
		overtemp_sync <= overtemp_raw;
		overcurrent_sync <= overcurrent_raw;
		manual_power_sync <= manual_power_raw;
		manual_shutdown_sync <= manual_shutdown_raw;
		shutdown_request_sync <= shutdown_request_raw;
		shutdown_success_sync <= shutdown_success_raw;
		
		// record previous manual_power signal
		manual_power_sync_prev <= manual_power_sync;
	end
end





// reusable timer block
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		timer_counter <= 29'b0;
		timer_finish <= 1'b0;
	end 
	else if (!timer_start) begin
		timer_counter <= 29'b0;
		timer_finish <= 1'b0;
	end 
	else if (timer_counter >= timer_threshold) begin
		timer_finish <= 1'b1;
	end 
	else begin
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
	shutdown_ack_next = 1'b0;
	buzzer_alert_next = 1'b0;
	recovery_mode_next = 1'b0;
	state_debug_bus_next = current_state;

	// state evaluation
	case (current_state)
            
		// STATE_OFF: Device is off. Transitions to STATE_BOOT when power button is manually pressed.
		STATE_OFF: begin
			if (manual_power_pressed) begin
				next_state = STATE_BOOT;
			end
		end

		// STATE_BOOT: Device is starting up. Transitions immediately to STATE_NORMAL once enabled.
		STATE_BOOT: begin
			system_enable_next = 1'b1;
			// boot timeout (valid at >= 10 seconds or 500000000 clock cycles)
			timer_threshold = boot_timeout;
			timer_start = 1'b1;
			if (boot_success_sync) begin
				next_state = STATE_NORMAL;
			end 
			else if (timer_finish) begin
				next_state = STATE_OFF;
			end
		end

		// STATE_NORMAL: Device is fully operational. 
		// Transitions to STATE_CRITICAL if immediate danger (overcurrent).
		// Transitions to STATE_WARNING if non-immediate issue (battery_low/overtemp).
		// Transitions to STATE_SHUTDOWN if requested by user.
		STATE_NORMAL: begin
			 system_enable_next = 1'b1;
			 if (overcurrent_sync) begin
				  next_state = STATE_CRITICAL;
			 end 
			 else if (battery_low_sync || overtemp_sync) begin
				  next_state = STATE_WARNING;
			 end
		end

		// STATE_WARNING: Non-immediate issue exists.
		// Transitions to STATE_CRITICAL if faults escalate.
		// Transitions back to STATE_NORMAL if all warnings clear.
		STATE_WARNING: begin
			 system_enable_next = 1'b1;
			 warning_led_next   = 1'b1;
			 if (overcurrent_sync) begin
				  next_state = STATE_CRITICAL;
			 end 
			 else if (!battery_low_sync && !overtemp_sync) begin
				  next_state = STATE_NORMAL;
			 end
		end

		// STATE_CRITICAL: Immediate danger. System block turned off, alarm asserted
		STATE_CRITICAL: begin
			warning_led_next   = 1'b1;
			buzzer_alert_next  = 1'b1;
		end

		// STATE_SHUTDOWN: Device is in the process of turning off.
		STATE_SHUTDOWN: begin
			system_enable_next = 1'b1;
			timer_threshold = shutdown_timeout;
			timer_start = 1'b1;
			if (shutdown_success_sync) begin
				next_state = STATE_OFF;
			end 
			else if (timer_finish) begin
				system_enable_next = 1'b0;
				next_state = STATE_OFF;
			end
		end

		// STATE_RECOVERY: Device charges safely while keeping main system disabled.
		// Transitions back to STATE_NORMAL once the battery is no longer low or critical.
		STATE_RECOVERY: begin
			 
		end

		default: begin
			 next_state = STATE_OFF;
		end
		
	endcase
	
	// limit shutdown interrupt to be fired only from STATE_NORMAL and STATE_WARNING state
	if (shutdown_trigger && (current_state = STATE_NORMAL || current_state = STATE_WARNING)) begin
		next_state = STATE_SHUTDOWN;
	end
end





// block to update current state on clock edge or reset signal
always_ff @(posedge clk or negedge reset_n) begin
	// reset button bypass other logics (active-low)
	if (!reset_n) begin
		battery_fault_latch <= 1'b0;
		current_state <= STATE_OFF;
	end else begin
		current_state <= next_state;
		
		// Latch battery faults to ensure STATE_RECOVERY is only used for dead batteries
		if (battery_critical_sync || battery_low_sync) begin
			battery_fault_latch <= 1'b1;
		end else if (next_state == STATE_NORMAL) begin
            battery_fault_latch <= 1'b0;
        end
	end
end





// block to update output signals on clock edge or reset signal
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		system_enable   <= 1'b0;
		warning_led     <= 1'b0;
		shutdown_ack <= 1'b0;
		buzzer_alert    <= 1'b0;
		recovery_mode   <= 1'b0;
		state_debug_bus <= STATE_OFF;
	end else begin
		system_enable   <= system_enable_next;
		warning_led     <= warning_led_next;
		shutdown_ack <= shutdown_ack_next;
		buzzer_alert    <= buzzer_alert_next;
		recovery_mode   <= recovery_mode_next;
		state_debug_bus <= state_debug_bus_next;
	end
end

endmodule