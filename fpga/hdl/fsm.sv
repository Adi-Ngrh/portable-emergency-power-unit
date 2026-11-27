module power_state_machine #(
    parameter CLK_FREQ_HZ,
    parameter DEBUG_MODE = 0  // 1 = run without the MCU (testing only), keep 0 in the final build
)(
	input logic boot_success,
	input logic mcu_heartbeat,
	input logic battery_low,
	input logic battery_critical,
	input logic warning_request,
	input logic shutdown_request,
	input logic critical_request,
	input logic manual_shutdown,
	input logic shutdown_success,
	input logic reset_n,
	input logic clk,

	output logic system_enable,
	output logic normal_led,   // NORMAL
	output logic warning_led,  // WARNING, SHUTDOWN, RECOVERY
	output logic critical_led, // CRITICAL
	output logic buzzer_alert,
	output logic recovery_mode
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


// synchronizer registers
logic boot_success_raw, boot_success_sync;
logic battery_low_raw, battery_low_sync;
logic battery_critical_raw, battery_critical_sync;
logic warning_request_raw, warning_request_sync;
logic shutdown_request_raw, shutdown_request_sync;
logic critical_request_raw, critical_request_sync;
logic manual_shutdown_raw, manual_shutdown_sync;
logic mcu_heartbeat_raw, mcu_heartbeat_sync, mcu_heartbeat_sync_prev;
logic shutdown_success_raw, shutdown_success_sync;

// timer related variables
logic timer_start;
logic [28:0] timer_counter;
logic [28:0] timer_threshold;
logic timer_finish;
localparam logic [28:0] boot_timeout = CLK_FREQ_HZ * 10;
localparam logic [28:0] shutdown_timeout = CLK_FREQ_HZ * 10;

// heartbeat watchdog: counts cycles since the last mcu_heartbeat toggle
logic [28:0] heartbeat_counter;
logic heartbeat_timeout;
localparam logic [28:0] heartbeat_timeout_threshold = CLK_FREQ_HZ * 3; // 3 s at any clock, the MCU toggles every 250 ms

// temporary outputs registers
logic system_enable_next;
logic normal_led_next;   // status LEDs: at most one is on, none in STATE_OFF and STATE_BOOT
logic warning_led_next;
logic critical_led_next;
logic buzzer_alert_next;
logic recovery_mode_next;

logic battery_fault_latch; // mark shutdown caused by battery
logic booted_once; // left STATE_OFF once since power-on, STATE_OFF is final after that
logic shutdown_trigger;
logic warning_trigger;
logic critical_trigger;
logic heartbeat_edge; // any toggle on mcu_heartbeat = proof the MCU is alive and running

assign shutdown_trigger = manual_shutdown_sync || shutdown_request_sync || battery_critical_sync;
assign warning_trigger = warning_request_sync || battery_low_sync;
assign critical_trigger = critical_request_sync;
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
		manual_shutdown_sync <= manual_shutdown_raw;
		mcu_heartbeat_sync <= mcu_heartbeat_raw;
		shutdown_success_sync <= shutdown_success_raw;

		// record previous mcu_heartbeat signal
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
	else if (heartbeat_edge) begin
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
	normal_led_next = 1'b0;
	warning_led_next = 1'b0;
	critical_led_next = 1'b0;
	buzzer_alert_next = 1'b0;
	recovery_mode_next = 1'b0;

	// state evaluation
	case (current_state)
            
		// STATE_OFF: after power-on go to STATE_BOOT once on the first MCU heartbeat (DEBUG_MODE: at once), then final
		STATE_OFF: begin
			if (!booted_once) begin
				if (DEBUG_MODE == 1 || heartbeat_edge) begin
					next_state = STATE_BOOT;
				end
			end
		end

		// STATE_BOOT: the MCU has 10 s to send boot_success (DEBUG_MODE: not needed), else back to STATE_OFF
		STATE_BOOT: begin
			system_enable_next = 1'b1;
			timer_threshold = boot_timeout;
			timer_start = 1'b1;
			if (DEBUG_MODE == 1 || boot_success_sync) begin
				next_state = STATE_NORMAL;
			end
			else if (timer_finish) begin
				next_state = STATE_OFF;
			end
		end

		// STATE_NORMAL: fully running, leaves only through the global overrides below
		STATE_NORMAL: begin
			system_enable_next = 1'b1;	
			normal_led_next    = 1'b1;
		end

		// STATE_WARNING: running with a non-urgent fault, back to STATE_NORMAL when all warnings clear
		STATE_WARNING: begin
			system_enable_next = 1'b1;
			warning_led_next   = 1'b1;
			if (!warning_trigger) begin
				next_state = STATE_NORMAL;
			end
		end

		// STATE_CRITICAL: system off, alarm on, final until the power switch is turned off and on again
		STATE_CRITICAL: begin
			critical_led_next  = 1'b1;
			buzzer_alert_next  = 1'b1;
		end

		// STATE_SHUTDOWN: wait for shutdown_success or the 10 s timeout, then STATE_RECOVERY (battery) or STATE_OFF
		STATE_SHUTDOWN: begin
			system_enable_next = 1'b1;
			warning_led_next   = 1'b1;
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

		// STATE_RECOVERY: battery critical, system off, back to STATE_BOOT when battery_critical clears
		STATE_RECOVERY: begin
			recovery_mode_next = 1'b1;
			warning_led_next   = 1'b1;
			if (!battery_critical_sync) begin
				next_state = STATE_BOOT;
			end
		end

		default: begin
			 next_state = STATE_OFF;
		end
		
	endcase
	
	
	// MCU heartbeat lost: checked in every state except STATE_OFF, not checked in DEBUG_MODE (no MCU)
	if (DEBUG_MODE == 0 && heartbeat_timeout && current_state != STATE_OFF && current_state != STATE_CRITICAL) begin
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
		booted_once <= 1'b0;
		current_state <= STATE_OFF;
	end else begin
		current_state <= next_state;

		// handling shutdown caused by battery
		if (battery_critical_sync) begin
			battery_fault_latch <= 1'b1;
		end else if (next_state == STATE_NORMAL) begin
			battery_fault_latch <= 1'b0;
		end

		// remember the first boot since power-on, STATE_OFF is final after it
		if (next_state == STATE_BOOT) begin
			booted_once <= 1'b1;
		end
	end
end





// block to update output signals on clock edge or reset signal
always_ff @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		system_enable   <= 1'b0;
		normal_led      <= 1'b0;
		warning_led     <= 1'b0;
		critical_led    <= 1'b0;
		buzzer_alert    <= 1'b0;
		recovery_mode   <= 1'b0;
	end else begin
		system_enable   <= system_enable_next;
		normal_led      <= normal_led_next;
		warning_led     <= warning_led_next;
		critical_led    <= critical_led_next;
		buzzer_alert    <= buzzer_alert_next;
		recovery_mode   <= recovery_mode_next;
	end
end

endmodule