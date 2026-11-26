`timescale 1ns / 1ps

// top level: FSM, FEE, sensor readers and FPGA heartbeat wired together internally
module portable_emergency_power_unit #(
    parameter CLK_FREQ_HZ = 27_000_000   // 27 MHz internal clock (tang nano 4k), 50 MHz external clock preferred
)(
    input  logic clk,
    input  logic reset_n,

    // FSM inputs
    input  logic boot_success,
    input  logic mcu_heartbeat,
    input  logic battery_low,
    input  logic battery_critical,
    input  logic manual_power,
    input  logic manual_shutdown,
    input  logic shutdown_success,

    // FSM outputs
    output logic system_enable,
    output logic normal_led,      // on in NORMAL
    output logic warning_led,     // on in WARNING, SHUTDOWN, RECOVERY
    output logic critical_led,    // on in CRITICAL
    output logic buzzer_alert,
    output logic recovery_mode,
    //output logic [6:0] state_debug_bus,

    // heartbeat output to the MCU
    output logic fpga_heartbeat,  // toggles every 250 ms while the FPGA runs, MCU blocks BOOT without it

    // FEE inputs
    inout  wire  ina226_scl,  // INA226 voltage/current sensor I2C clock pin (open-drain)
    inout  wire  ina226_sda,  // INA226 voltage/current sensor I2C data pin (open-drain)
    inout  wire  ds18b20_dq,  // DS18B20 temperature sensor data pin (needs external 4.7k pull-up to 3.3V)
    input  logic fan_failure,
    input  logic sensor_failure,
    input  logic communication_timeout,

    // FEE outputs
    output logic shutdown_response,
    output logic warning_response,
    output logic critical_response,
    output logic [2:0] fault_code_bus,
    output logic [1:0] buzzer_pattern
);

    // current resolution shared by ina226_reader and the FEE (microampere per bit), both must use the same value
    localparam INA226_CURRENT_LSB_UA = 1000;

    // internal net: FSM critical_clear -> FEE critical_clear
    logic fsm_critical_clear;

    // internal nets: INA226 reader -> FEE
    logic [15:0] bus_voltage;         // 1 LSB = 1.25 mV
    logic signed [15:0] current;      // 1 LSB = INA226_CURRENT_LSB_UA microampere
    logic measurement_valid;
    logic measurement_error;

    // internal nets: DS18B20 reader -> FEE
    logic signed [15:0] temperature;  // 1 LSB = 1/16 °C
    logic temperature_valid;
    logic temperature_error;

    // ==========================================
    // FSM (Power-State Machine) Instance
    // ==========================================
    power_state_machine #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_fsm (
        .clk               (clk),
        .reset_n           (reset_n),
        .boot_success      (boot_success),
        .mcu_heartbeat     (mcu_heartbeat),
        .battery_low       (battery_low),
        .battery_critical  (battery_critical),
        .warning_request   (warning_response), // FEE warning -> FSM
        .shutdown_request  (shutdown_response), // FEE shutdown -> FSM
        .critical_request  (critical_response), // FEE latch -> FSM
        .manual_power      (manual_power),
        .manual_shutdown   (manual_shutdown),
        .shutdown_success  (shutdown_success),

        .system_enable     (system_enable),
        .normal_led        (normal_led),
        .warning_led       (warning_led),
        .critical_led      (critical_led),
        .critical_clear    (fsm_critical_clear),
        .buzzer_alert      (buzzer_alert),
        .recovery_mode     (recovery_mode)
        //.state_debug_bus   (state_debug_bus)
    );

    // ==========================================
    // FPGA Heartbeat Instance (proof of life for the MCU)
    // ==========================================
    fpga_heartbeat #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_heartbeat (
        .clk               (clk),
        .reset_n           (reset_n),

        .heartbeat         (fpga_heartbeat)
    );

    // ==========================================
    // DS18B20 Temperature Reader Instance
    // ==========================================
    ds18b20_reader #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ)
    ) u_ds18b20 (
        .clk               (clk),
        .reset_n           (reset_n),
        .dq                (ds18b20_dq),

        .temperature       (temperature),
        .temperature_valid (temperature_valid),
        .temperature_error (temperature_error)
    );

    // ==========================================
    // INA226 Voltage/Current Reader Instance
    // ==========================================
    ina226_reader #(
    .CLK_FREQ_HZ    (CLK_FREQ_HZ),
    .CURRENT_LSB_UA (INA226_CURRENT_LSB_UA)
    ) u_ina226 (
        .clk               (clk),
        .reset_n           (reset_n),
        .scl               (ina226_scl),
        .sda               (ina226_sda),

        .bus_voltage       (bus_voltage),
        .current           (current),
        .measurement_valid (measurement_valid),
        .measurement_error (measurement_error)
    );

    // ==========================================
    // FEE (Fault Event Engine) Instance
    // ==========================================
    fault_event_engine #(
    .CLK_FREQ_HZ    (CLK_FREQ_HZ),
    .CURRENT_LSB_UA (INA226_CURRENT_LSB_UA)
    ) u_fee (
        .clk                   (clk),
        .reset_n               (reset_n),
        .bus_voltage           (bus_voltage),       // INA226 reader -> FEE
        .current               (current),           // INA226 reader -> FEE
        .measurement_valid     (measurement_valid), // INA226 reader -> FEE
        .measurement_error     (measurement_error), // INA226 reader -> FEE
        .temperature           (temperature),       // DS18B20 reader -> FEE
        .temperature_valid     (temperature_valid), // DS18B20 reader -> FEE
        .temperature_error     (temperature_error), // DS18B20 reader -> FEE
        .fan_failure           (fan_failure),
        .sensor_failure        (sensor_failure),
        .communication_timeout (communication_timeout),
        .critical_clear        (fsm_critical_clear), // FSM retry pulse -> FEE latch clear

        .shutdown_response     (shutdown_response),
        .warning_response      (warning_response),
        .critical_response     (critical_response),
        .fault_code_bus        (fault_code_bus),
        .buzzer_pattern        (buzzer_pattern)
    );

endmodule
