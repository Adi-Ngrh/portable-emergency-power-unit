module power_state_machine(
	input logic boot_success,
	input logic mcu_heartbeat,
	input logic battery_low,
	input logic battery_critical,
	input logic warning_request,
	input logic shutdown_request,
	input logic critical_request,
	input logic manual_power,
	input logic manual_shutdown,
	input logic shutdown_success,
	input logic reset_n,
	input logic clk,

	output logic system_enable,
	output logic warning_led,
	output logic shutdown_ack,
	output logic critical_clear,
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
logic warning_request_raw, warning_request_sync;
logic shutdown_request_raw, shutdown_request_sync;
logic critical_request_raw, critical_request_sync;
logic manual_power_raw, manual_power_sync, manual_power_sync_prev;
logic manual_shutdown_raw, manual_shutdown_sync;
logic mcu_heartbeat_raw, mcu_heartbeat_sync, mcu_heartbeat_sync_prev;
logic shutdown_success_raw, shutdown_success_sync;

// timer related variables
logic timer_start;
logic [28:0] timer_counter;
logic [28:0] timer_threshold;
logic timer_finish;
localparam logic [28:0] boot_timeout = 29'd500_000_000;
localparam logic [28:0] shutdown_timeout = 29'd500_000_000;

// heartbeat watchdog: counts cycles since the last mcu_heartbeat toggle
logic [28:0] heartbeat_counter;
logic heartbeat_timeout;
localparam logic [28:0] heartbeat_timeout_threshold = 29'd150_000_000; // placeholder ~3s @ 50MHz, set from real MCU heartbeat rate

// temporary outputs registers
logic system_enable_next;
logic warning_led_next;
logic shutdown_ack_next;
logic critical_clear_next;
logic buzzer_alert_next;
logic recovery_mode_next;

logic battery_fault_latch; // mark shutdown caused by battery
logic manual_power_pressed; // when boot fail, keep system at STATE_OFF state until fresh trigger
logic shutdown_trigger;
logic warning_trigger;
logic critical_trigger;
logic critical_retry_allowed; // gate for leaving STATE_CRITICAL: a retry was asked for and the budget isn't spent
logic [1:0] retry_count; // consecutive retries out of STATE_CRITICAL; only reset_n clears this
localparam logic [1:0] max_retry = 2'd3;
logic heartbeat_edge; // any toggle on mcu_heartbeat = proof the MCU is alive and running
logic mcu_alive; // set once a heartbeat is seen; only cleared in STATE_OFF

assign manual_power_pressed = manual_power_sync & ~manual_power_sync_prev;
assign shutdown_trigger = manual_shutdown_sync || shutdown_request_sync || battery_critical_sync;
assign warning_trigger = warning_request_sync || battery_low_sync;
assign critical_trigger = critical_request_sync;
assign critical_retry_allowed = manual_power_pressed && (retry_count < max_retry);
assign heartbeat_edge = mcu_heartbeat_sync ^ mcu_heartbeat_sync_prev;





// 2-stage synchronizer block for external inputs
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		boot_success_raw <= 1'b0; 
		boot_success_sync <= 1'b0;
		battery_low_raw <= 1'b0;
		battery_low_sync <= 1'b0;
		battery_critical_raw <= 1'b0;
		battery_critical_sync <= 1'b0;
		warning_request_raw <= 1'b0;
		warning_request_sync <= 1'b0;
		shutdown_request_raw <= 1'b0;
		shutdown_request_sync <= 1'b0;
		critical_request_raw <= 1'b0;
		critical_request_sync <= 1'b0;
		manual_power_raw <= 1'b0;
		manual_power_sync <= 1'b0;
		manual_power_sync_prev <= 1'b0;
		manual_shutdown_raw <= 1'b0;
		manual_shutdown_sync <= 1'b0;
		mcu_heartbeat_raw <= 1'b0;
		mcu_heartbeat_sync <= 1'b0;
		mcu_heartbeat_sync_prev <= 1'b0;
		shutdown_success_raw <= 1'b0;
		shutdown_success_sync <= 1'b0;
	end
	else begin
		// Stage 1: Capture raw inputs (susceptible to metastability)
		boot_success_raw <= boot_success;
		battery_low_raw <= battery_low;
		battery_critical_raw <= battery_critical;
		warning_request_raw <= warning_request;
		shutdown_request_raw <= shutdown_request;
		critical_request_raw <= critical_request;
		manual_power_raw <= manual_power;
		manual_shutdown_raw <= manual_shutdown;
		mcu_heartbeat_raw <= mcu_heartbeat;
		shutdown_success_raw <= shutdown_success;

		// Stage 2: Capture settled signals
		boot_success_sync <= boot_success_raw;
		battery_low_sync <= battery_low_raw;
		battery_critical_sync <= battery_critical_raw;
		warning_request_sync <= warning_request_raw;
		shutdown_request_sync <= shutdown_request_raw;
		critical_request_sync <= critical_request_raw;
		manual_power_sync <= manual_power_raw;
		manual_shutdown_sync <= manual_shutdown_raw;
		mcu_heartbeat_sync <= mcu_heartbeat_raw;
		shutdown_success_sync <= shutdown_success_raw;

		// record previous manual_power/mcu_heartbeat signal
		manual_power_sync_prev <= manual_power_sync;
		mcu_heartbeat_sync_prev <= mcu_heartbeat_sync;
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

// heartbeat watchdog block
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		heartbeat_counter <= 29'b0;
		heartbeat_timeout <= 1'b0;
	end
	else if (heartbeat_edge || (current_state == STATE_CRITICAL && next_state == STATE_BOOT)) begin
		// also clear on a STATE_CRITICAL retry
		heartbeat_counter <= 29'b0;
		heartbeat_timeout <= 1'b0;
	end
	else if (heartbeat_counter >= heartbeat_timeout_threshold) begin
		heartbeat_timeout <= 1'b1;
	end
	else begin
		heartbeat_counter <= heartbeat_counter + 1'b1;
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
	critical_clear_next = 1'b0;
	buzzer_alert_next = 1'b0;
	recovery_mode_next = 1'b0;
	state_debug_bus_next = current_state;

	// state evaluation
	case (current_state)
            
		// STATE_OFF: Device is off.
		// Transitions to STATE_BOOT when the power button is manually pressed.
		STATE_OFF: begin
			if (manual_power_pressed) begin
				next_state = STATE_BOOT;
			end
		end

		// STATE_BOOT: Device is starting up.
		// Transitions to STATE_NORMAL once boot_success arrives.
		// Transitions back to STATE_OFF if the boot timeout expires.
		STATE_BOOT: begin
			system_enable_next = 1'b1;
			timer_threshold = boot_timeout;
			timer_start = 1'b1;
			if (mcu_alive && boot_success_sync) begin
				next_state = STATE_NORMAL;
			end
			else if (timer_finish) begin
				next_state = STATE_OFF;
			end
		end

		// STATE_NORMAL: Device is fully operational.
		// See the global overrides below for transitions to STATE_CRITICAL,
		// STATE_SHUTDOWN, STATE_RECOVERY, or STATE_WARNING.
		STATE_NORMAL: begin
			system_enable_next = 1'b1;	
		end

		// STATE_WARNING: Non-immediate issue exists.
		// Transitions to STATE_CRITICAL if faults escalate.
		// Transitions back to STATE_NORMAL if all warnings clear.
		STATE_WARNING: begin
			system_enable_next = 1'b1;
			warning_led_next   = 1'b1;
			if (!warning_trigger) begin
				next_state = STATE_NORMAL;
			end
		end

		// STATE_CRITICAL: Immediate danger. System block turned off, alarm asserted.
		// Transitions to STATE_BOOT when the user retries and the retry budget isn't spent.
		STATE_CRITICAL: begin
			warning_led_next   = 1'b1;
			buzzer_alert_next  = 1'b1;
			if (critical_retry_allowed) begin
				critical_clear_next = 1'b1;
				next_state = STATE_BOOT;
			end
		end

		// STATE_SHUTDOWN: Graceful process of turning off.
		// Transitions to STATE_RECOVERY or STATE_OFF once shutdown completes.
		STATE_SHUTDOWN: begin
			system_enable_next = 1'b1;
			timer_threshold = shutdown_timeout;
			timer_start = 1'b1;
			if (shutdown_success_sync) begin
				if (battery_fault_latch) begin
					next_state = STATE_RECOVERY;
				end else begin
					next_state = STATE_OFF;
				end
			end
			else if (timer_finish) begin
				system_enable_next = 1'b0;
				if (battery_fault_latch) begin
					next_state = STATE_RECOVERY;
				end else begin
					next_state = STATE_OFF;
				end
			end
		end

		// STATE_RECOVERY: Battery critical, system block already off.
		// Transitions to STATE_BOOT once battery_critical clears.
		STATE_RECOVERY: begin
			recovery_mode_next = 1'b1;
			if (!battery_critical_sync) begin
				next_state = STATE_BOOT;
			end
		end

		default: begin
			 next_state = STATE_OFF;
		end
		
	endcase
	
	
	if (mcu_alive && heartbeat_timeout && current_state != STATE_OFF && current_state != STATE_CRITICAL) begin
		next_state = STATE_CRITICAL;
	end
	else if (critical_trigger && (current_state == STATE_NORMAL || current_state == STATE_WARNING || current_state == STATE_BOOT || current_state == STATE_SHUTDOWN)) begin
		next_state = STATE_CRITICAL;
	end
	else if (shutdown_trigger && (current_state == STATE_NORMAL || current_state == STATE_WARNING)) begin
		next_state = STATE_SHUTDOWN;
	end
	else if (warning_trigger && current_state == STATE_NORMAL) begin
		next_state = STATE_WARNING;
	end
end





// block to update current state on clock edge or reset signal
always_ff @(posedge clk or negedge reset_n) begin
	// reset button bypass other logics (active-low)
	if (!reset_n) begin
		battery_fault_latch <= 1'b0;
		retry_count <= 2'd0;
		mcu_alive <= 1'b0;
		current_state <= STATE_OFF;
	end else begin
		current_state <= next_state;

		// handling shutdown caused by battery
		if (battery_critical_sync) begin
			battery_fault_latch <= 1'b1;
		end else if (next_state == STATE_NORMAL) begin
			battery_fault_latch <= 1'b0;
		end

		// count retries out of STATE_CRITICAL; only reset_n clears this counter
		if (current_state == STATE_CRITICAL && next_state == STATE_BOOT) begin
			retry_count <= retry_count + 1'b1;
		end

		// track MCU heartbeat
		if (current_state == STATE_OFF || (current_state == STATE_CRITICAL && next_state == STATE_BOOT)) begin
			mcu_alive <= 1'b0;
		end else if (heartbeat_edge) begin
			mcu_alive <= 1'b1;
		end
	end
end





// block to update output signals on clock edge or reset signal
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		system_enable   <= 1'b0;
		warning_led     <= 1'b0;
		shutdown_ack <= 1'b0;
		critical_clear <= 1'b0;
		buzzer_alert    <= 1'b0;
		recovery_mode   <= 1'b0;
		state_debug_bus <= STATE_OFF;
	end else begin
		system_enable   <= system_enable_next;
		warning_led     <= warning_led_next;
		shutdown_ack <= shutdown_ack_next;
		critical_clear <= critical_clear_next;
		buzzer_alert    <= buzzer_alert_next;
		recovery_mode   <= recovery_mode_next;
		state_debug_bus <= state_debug_bus_next;
	end
end

endmodule