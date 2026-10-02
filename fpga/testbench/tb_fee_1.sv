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

    // read a fault's debounce threshold constant from inside the dut
    function automatic int get_threshold(input int fault_id);
        case (fault_id)
            0:       return int'(dut.overcurrent_threshold);
            1:       return int'(dut.overvoltage_threshold);
            2:       return int'(dut.undervoltage_threshold);
            3:       return int'(dut.overtemperature_threshold);
            4:       return int'(dut.fan_failure_threshold);
            5:       return int'(dut.sensor_failure_threshold);
            6:       return int'(dut.communication_timeout_threshold);
            default: return 0;
        endcase
    endfunction

    // jump a fault's debounce counter to just below its threshold, the real comparator finishes the rest
    task automatic skip_debounce(input int fault_id);
        case (fault_id)
            0: force dut.overcurrent_counter           = int'(dut.overcurrent_threshold) - 3;
            1: force dut.overvoltage_counter           = int'(dut.overvoltage_threshold) - 3;
            2: force dut.undervoltage_counter          = int'(dut.undervoltage_threshold) - 3;
            3: force dut.overtemperature_counter       = int'(dut.overtemperature_threshold) - 3;
            4: force dut.fan_failure_counter           = int'(dut.fan_failure_threshold) - 3;
            5: force dut.sensor_failure_counter        = int'(dut.sensor_failure_threshold) - 3;
            6: force dut.communication_timeout_counter = int'(dut.communication_timeout_threshold) - 3;
        endcase
        @(posedge clk);
        case (fault_id)
            0: release dut.overcurrent_counter;
            1: release dut.overvoltage_counter;
            2: release dut.undervoltage_counter;
            3: release dut.overtemperature_counter;
            4: release dut.fan_failure_counter;
            5: release dut.sensor_failure_counter;
            6: release dut.communication_timeout_counter;
        endcase
    endtask

    // assert one fault, skip its debounce wait, check the result, then clear it
    task automatic check_fault(
        ref logic fault_pin,
        input int fault_id,
        input int expect_threshold,
        input logic [2:0] expect_code,
        input logic [1:0] expect_pattern,
        input bit is_critical
    );
        // the threshold constant must match the spec, since the wait is skipped
        assert (get_threshold(fault_id) == expect_threshold) else $error("debounce threshold does not match the spec");

        fault_pin = 1'b1;
        repeat (5) @(posedge clk);
        skip_debounce(fault_id);
        repeat (10) @(posedge clk);
        assert (fault_code_bus == expect_code) else $error("wrong fault_code_bus for this fault");
        assert (buzzer_pattern == expect_pattern) else $error("wrong buzzer_pattern for this fault");
        if (is_critical) begin
            assert (critical_response == 1'b1) else $error("critical_response not set");
        end else if (expect_pattern == PATTERN_SHUTDOWN) begin
            assert (shutdown_response == 1'b1) else $error("shutdown_response not set");
        end else begin
            assert (warning_response == 1'b1) else $error("warning_response not set");
        end

        // hold the fault so the result stays visible in the waveform
        repeat (20) @(posedge clk);

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
        check_fault(overcurrent,           0, 50,        CODE_OVERCURRENT,           PATTERN_CRITICAL, 1);
        $display("[%0t] overcurrent checked", $time);

        check_fault(overvoltage,           1, 50,        CODE_OVERVOLTAGE,           PATTERN_CRITICAL, 1);
        $display("[%0t] overvoltage checked", $time);

        check_fault(undervoltage,          2, 50_000,    CODE_UNDERVOLTAGE,          PATTERN_WARNING,  0);
        $display("[%0t] undervoltage checked", $time);

        check_fault(overtemperature,       3, 50_000,    CODE_OVERTEMPERATURE,       PATTERN_SHUTDOWN, 0);
        $display("[%0t] overtemperature checked", $time);

        check_fault(fan_failure,           4, 500_000,   CODE_FAN_FAILURE,           PATTERN_WARNING,  0);
        $display("[%0t] fan_failure checked", $time);

        check_fault(sensor_failure,        5, 50_000,    CODE_SENSOR_FAILURE,        PATTERN_SHUTDOWN, 0);
        $display("[%0t] sensor_failure checked", $time);

        check_fault(communication_timeout, 6, 1_500_000, CODE_COMMUNICATION_TIMEOUT, PATTERN_WARNING,  0);
        $display("[%0t] communication_timeout checked", $time);

        $display("[%0t] all 7 faults swept back to back with no reset_n, test passed", $time);
        $finish;
    end

endmodule
