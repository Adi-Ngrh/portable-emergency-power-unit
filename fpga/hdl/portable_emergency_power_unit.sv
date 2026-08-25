`timescale 1ns / 1ps

module portable_emergency_power_unit (
    input  logic clk,
    input  logic reset_n,
    
    // External Sensor & Event Inputs
    input  logic battery_low,
    input  logic battery_critical,
    input  logic overtemp,
    input  logic overcurrent,
    input  logic overvoltage,
    input  logic undervoltage,
    input  logic fan_failure,
    input  logic sensor_failure,
    input  logic communication_timeout,
    input  logic charger_connected,
    input  logic manual_shutdown,

    // External System Outputs
    output logic system_enable,
    output logic warning_led,
    output logic shutdown_signal,
    output logic buzzer_alert,
    output logic recovery_mode,
    output logic [6:0] state_debug_bus,

    // FEE Specific Outputs
    output logic fault_interrupt,
    output logic shutdown_request,
    output logic warning_request,
    output logic [2:0] fault_code_bus,
    output logic [1:0] buzzer_pattern
);

    // ==========================================
    // FSM (Power-State Machine) Instance
    // ==========================================
    power_state_machine u_fsm (
        .clk(clk),
        .reset_n(reset_n),
        .battery_low(battery_low),
        .battery_critical(battery_critical),
        .overtemp(overtemp),
        .overcurrent(overcurrent),
        .charger_connected(charger_connected),
        .manual_shutdown(manual_shutdown),

        .system_enable(system_enable),
        .warning_led(warning_led),
        .shutdown_signal(shutdown_signal),
        .buzzer_alert(buzzer_alert),
        .recovery_mode(recovery_mode),
        .state_debug_bus(state_debug_bus)
    );

    // ==========================================
    // FEE (Fault Event Engine) Instance
    // ==========================================
    fault_event_engine u_fee (
        .clk(clk),
        .reset_n(reset_n),
        .overcurrent(overcurrent),
        .overvoltage(overvoltage),
        .undervoltage(undervoltage),
        .overtemperature(overtemp),          // Shared sensor input
        .fan_failure(fan_failure),
        .sensor_failure(sensor_failure),
        .communication_timeout(communication_timeout),
        
        .fault_interrupt(fault_interrupt),
        .shutdown_request(shutdown_request),
        .warning_request(warning_request),
        .fault_code_bus(fault_code_bus),
        .buzzer_pattern(buzzer_pattern)
    );

endmodule
