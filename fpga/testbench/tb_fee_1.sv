`timescale 1ns / 1ps

// FEE test case 1: debounce and classification sweep across all 7 faults, no reset_n in between
module tb_fee_1;

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
    localparam logic [2:0] CODE_DEFAULT             = 3'b000;
    localparam logic [2:0] CODE_OVERCURRENT         = 3'b001;
    localparam logic [2:0] CODE_OVERVOLTAGE         = 3'b010;
    localparam logic [2:0] CODE_OVERTEMPERATURE     = 3'b011;
    localparam logic [2:0] CODE_SENSOR_FAILURE      = 3'b100;
    localparam logic [2:0] CODE_UNDERVOLTAGE        = 3'b101;
    localparam logic [2:0] CODE_FAN_FAILURE         = 3'b110;
    localparam logic [2:0] CODE_COMMUNICATION_TIMEOUT = 3'b111;

    // buzzer_pattern codes, must match fault_event_engine
    localparam logic [1:0] PATTERN_DEFAULT  = 2'b00;
    localparam logic [1:0] PATTERN_WARNING  = 2'b01;
    localparam logic [1:0] PATTERN_SHUTDOWN = 2'b10;
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

    // assert one fault, wait past its debounce threshold, check the result, then clear it
    task automatic check_fault(
        ref logic fault_pin,
        input int threshold,
        input logic [2:0] expect_code,
        input logic [1:0] expect_pattern,
        input bit is_critical
    );
        fault_pin = 1'b1;
        repeat (threshold + 5) @(posedge clk);
        assert (fault_code_bus == expect_code) else $error("wrong fault_code_bus for this fault");
        assert (buzzer_pattern == expect_pattern) else $error("wrong buzzer_pattern for this fault");
        if (is_critical) begin
            assert (critical_response == 1'b1) else $error("critical_response not set");
        end else if (expect_pattern == PATTERN_SHUTDOWN) begin
            assert (shutdown_response == 1'b1) else $error("shutdown_response not set");
        end else begin
            assert (warning_response == 1'b1) else $error("warning_response not set");
        end

        fault_pin = 1'b0;
        // let the fault actually clear through sync+debounce before pulsing critical_clear
        repeat (5) @(posedge clk);
        if (is_critical) begin
            // critical_response is latched, only critical_clear releases it
            critical_clear = 1'b1;
            @(posedge clk);
            critical_clear = 1'b0;
            repeat (5) @(posedge clk);
        end
        assert (fault_code_bus == CODE_DEFAULT) else $error("fault_code_bus did not clear");
        assert (buzzer_pattern == PATTERN_DEFAULT) else $error("buzzer_pattern did not clear");
        assert (critical_response == 1'b0) else $error("critical_response did not clear");
        assert (shutdown_response == 1'b0) else $error("shutdown_response did not clear");
        assert (warning_response == 1'b0) else $error("warning_response did not clear");
    endtask

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

        // sweep every fault back to back, no reset_n in between
        check_fault(overcurrent,           50,      CODE_OVERCURRENT,         PATTERN_CRITICAL, 1);
        $display("[%0t] overcurrent checked", $time);

        check_fault(overvoltage,           50,      CODE_OVERVOLTAGE,         PATTERN_CRITICAL, 1);
        $display("[%0t] overvoltage checked", $time);

        check_fault(undervoltage,          50_000,  CODE_UNDERVOLTAGE,        PATTERN_WARNING,  0);
        $display("[%0t] undervoltage checked", $time);

        check_fault(overtemperature,       50_000,  CODE_OVERTEMPERATURE,     PATTERN_SHUTDOWN, 0);
        $display("[%0t] overtemperature checked", $time);

        check_fault(fan_failure,           500_000, CODE_FAN_FAILURE,         PATTERN_WARNING,  0);
        $display("[%0t] fan_failure checked", $time);

        check_fault(sensor_failure,        50_000,  CODE_SENSOR_FAILURE,      PATTERN_SHUTDOWN, 0);
        $display("[%0t] sensor_failure checked", $time);

        check_fault(communication_timeout, 1_500_000, CODE_COMMUNICATION_TIMEOUT, PATTERN_WARNING, 0);
        $display("[%0t] communication_timeout checked", $time);

        $display("[%0t] all 7 faults swept back to back with no reset_n, test passed", $time);
        $finish;
    end

endmodule
