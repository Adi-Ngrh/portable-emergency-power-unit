`timescale 1ns / 1ps

// FEE test case 2: simultaneous faults, mixed severity then same severity
module tb_fee_2;

    // clock and reset
    logic clk;
    logic reset_n;

    // dut inputs
    logic overcurrent;
    logic overvoltage;
    logic undervoltage;
    logic overtemperature;
    logic fan_failure;
    logic sensor_failure;
    logic communication_timeout;
    logic critical_clear;

    // dut outputs
    logic shutdown_response;
    logic warning_response;
    logic critical_response;
    logic [2:0] fault_code_bus;
    logic [1:0] buzzer_pattern;

    // fault_code_bus codes, must match fault_event_engine
    localparam logic [2:0] CODE_DEFAULT      = 3'b000;
    localparam logic [2:0] CODE_OVERCURRENT  = 3'b001;
    localparam logic [2:0] CODE_UNDERVOLTAGE = 3'b101;

    // buzzer_pattern codes, must match fault_event_engine
    localparam logic [1:0] PATTERN_DEFAULT  = 2'b00;
    localparam logic [1:0] PATTERN_WARNING  = 2'b01;
    localparam logic [1:0] PATTERN_CRITICAL = 2'b11;

    // 20 ns clock period, 50 MHz
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // device under test
    fault_event_engine dut (
        .clk                    (clk),
        .reset_n                (reset_n),
        .overcurrent            (overcurrent),
        .overvoltage            (overvoltage),
        .undervoltage           (undervoltage),
        .overtemperature        (overtemperature),
        .fan_failure            (fan_failure),
        .sensor_failure         (sensor_failure),
        .communication_timeout  (communication_timeout),
        .critical_clear         (critical_clear),
        .shutdown_response      (shutdown_response),
        .warning_response       (warning_response),
        .critical_response      (critical_response),
        .fault_code_bus         (fault_code_bus),
        .buzzer_pattern         (buzzer_pattern)
    );

    initial begin
        // default every input low
        reset_n               = 1'b0;
        overcurrent            = 1'b0;
        overvoltage            = 1'b0;
        undervoltage           = 1'b0;
        overtemperature        = 1'b0;
        fan_failure            = 1'b0;
        sensor_failure         = 1'b0;
        communication_timeout  = 1'b0;
        critical_clear         = 1'b0;

        // one reset at the very start only
        repeat (3) @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // phase 1: mixed severity, one fault from each class at once
        overcurrent     = 1'b1; // critical
        overtemperature = 1'b1; // shutdown
        undervoltage    = 1'b1; // warning
        repeat (5) @(posedge clk);

        // skip the debounce wait, the real comparators finish the last few counts
        force dut.overcurrent_counter     = int'(dut.overcurrent_threshold) - 3;
        force dut.overtemperature_counter = int'(dut.overtemperature_threshold) - 3;
        force dut.undervoltage_counter    = int'(dut.undervoltage_threshold) - 3;
        @(posedge clk);
        release dut.overcurrent_counter;
        release dut.overtemperature_counter;
        release dut.undervoltage_counter;
        repeat (10) @(posedge clk);

        $display("[%0t] mixed severity faults asserted together", $time);
        assert (critical_response == 1'b1) else $error("critical_response not set during mixed fault");
        assert (shutdown_response == 1'b1) else $error("shutdown_response not set during mixed fault");
        assert (warning_response  == 1'b1) else $error("warning_response not set during mixed fault");
        assert (fault_code_bus == CODE_OVERCURRENT) else $error("fault_code_bus did not pick the critical fault");
        assert (buzzer_pattern == PATTERN_CRITICAL) else $error("buzzer_pattern did not pick the critical fault");

        // hold the faults so the result stays visible in the waveform
        repeat (20) @(posedge clk);

        overcurrent     = 1'b0;
        overtemperature = 1'b0;
        undervoltage    = 1'b0;
        // let the faults actually clear through sync+debounce before pulsing critical_clear
        repeat (5) @(posedge clk);
        critical_clear  = 1'b1;
        @(posedge clk);
        critical_clear  = 1'b0;
        repeat (5) @(posedge clk);
        assert (critical_response == 1'b0) else $error("critical_response did not clear");
        assert (shutdown_response == 1'b0) else $error("shutdown_response did not clear");
        assert (warning_response  == 1'b0) else $error("warning_response did not clear");
        assert (fault_code_bus == CODE_DEFAULT) else $error("fault_code_bus did not clear");
        $display("[%0t] mixed severity phase passed", $time);

        // phase 2: two faults from the same severity class at once
        undervoltage = 1'b1;
        fan_failure  = 1'b1;
        repeat (5) @(posedge clk);

        // skip the debounce wait, the real comparators finish the last few counts
        force dut.undervoltage_counter = int'(dut.undervoltage_threshold) - 3;
        force dut.fan_failure_counter  = int'(dut.fan_failure_threshold) - 3;
        @(posedge clk);
        release dut.undervoltage_counter;
        release dut.fan_failure_counter;
        repeat (10) @(posedge clk);

        $display("[%0t] same severity faults asserted together", $time);
        assert (warning_response  == 1'b1) else $error("warning_response not set");
        assert (shutdown_response == 1'b0) else $error("shutdown_response incorrectly set");
        assert (critical_response == 1'b0) else $error("critical_response incorrectly set");
        assert (fault_code_bus == CODE_UNDERVOLTAGE) else $error("fault_code_bus did not pick the higher priority fault");
        assert (buzzer_pattern == PATTERN_WARNING) else $error("buzzer_pattern not PATTERN_WARNING");

        // hold the faults so the result stays visible in the waveform
        repeat (20) @(posedge clk);

        undervoltage = 1'b0;
        fan_failure  = 1'b0;
        repeat (5) @(posedge clk);
        assert (warning_response == 1'b0) else $error("warning_response did not clear");
        assert (fault_code_bus == CODE_DEFAULT) else $error("fault_code_bus did not clear");
        $display("[%0t] same severity phase passed, test passed", $time);

        $finish;
    end

endmodule
