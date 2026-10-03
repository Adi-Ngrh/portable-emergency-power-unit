`timescale 1ns / 1ps

// top level: declares the FSM and FEE instances only, not wired together yet
module portable_emergency_power_unit (
    input  logic clk,
    input  logic reset_n,

    // FSM inputs
    input  logic boot_success,
    input  logic mcu_heartbeat,
    input  logic battery_low,
    input  logic battery_critical,
    input  logic warning_request,
    input  logic shutdown_request,
    input  logic critical_request,
    input  logic manual_power,
    input  logic manual_shutdown,
    input  logic shutdown_success,

    // FSM outputs
    output logic system_enable,
    output logic warning_led,
    output logic fsm_critical_clear,
    output logic buzzer_alert,
    output logic recovery_mode,
    output logic [6:0] state_debug_bus,

    // FEE inputs
    input  logic overcurrent,
    input  logic overvoltage,
    input  logic undervoltage,
    input  logic overtemperature,
    input  logic fan_failure,
    input  logic sensor_failure,
    input  logic communication_timeout,
    input  logic fee_critical_clear,

    // FEE outputs
    output logic shutdown_response,
    output logic warning_response,
    output logic critical_response,
    output logic [2:0] fault_code_bus,
    output logic [1:0] buzzer_pattern
);

    // ==========================================
    // FSM (Power-State Machine) Instance
    // ==========================================
    power_state_machine u_fsm (
        .clk               (clk),
        .reset_n           (reset_n),
        .boot_success      (boot_success),
        .mcu_heartbeat     (mcu_heartbeat),
        .battery_low       (battery_low),
        .battery_critical  (battery_critical),
        .warning_request   (warning_request),
        .shutdown_request  (shutdown_request),
        .critical_request  (critical_request),
        .manual_power      (manual_power),
        .manual_shutdown   (manual_shutdown),
        .shutdown_success  (shutdown_success),

        .system_enable     (system_enable),
        .warning_led       (warning_led),
        .critical_clear    (fsm_critical_clear),
        .buzzer_alert      (buzzer_alert),
        .recovery_mode     (recovery_mode),
        .state_debug_bus   (state_debug_bus)
    );

    // ==========================================
    // FEE (Fault Event Engine) Instance
    // ==========================================
    fault_event_engine u_fee (
        .clk                   (clk),
        .reset_n               (reset_n),
        .overcurrent           (overcurrent),
        .overvoltage           (overvoltage),
        .undervoltage          (undervoltage),
        .overtemperature       (overtemperature),
        .fan_failure           (fan_failure),
        .sensor_failure        (sensor_failure),
        .communication_timeout (communication_timeout),
        .critical_clear        (fee_critical_clear),

        .shutdown_response     (shutdown_response),
        .warning_response      (warning_response),
        .critical_response     (critical_response),
        .fault_code_bus        (fault_code_bus),
        .buzzer_pattern        (buzzer_pattern)
    );

endmodule
