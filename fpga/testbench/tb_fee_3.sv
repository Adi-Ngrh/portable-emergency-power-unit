`timescale 1ns / 1ps

// FEE test case 3: critical latch survives unrelated faults coming and going, only critical_clear releases it
module tb_fee_3;

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
    localparam logic [2:0] CODE_DEFAULT         = 3'b000;
    localparam logic [2:0] CODE_OVERCURRENT     = 3'b001;
    localparam logic [2:0] CODE_OVERTEMPERATURE = 3'b011;
    localparam logic [2:0] CODE_UNDERVOLTAGE    = 3'b101;

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

        // a critical fault latches critical_response
        overcurrent = 1'b1;
        repeat (50 + 5) @(posedge clk);
        assert (critical_response == 1'b1) else $error("critical_response not set");
        assert (fault_code_bus == CODE_OVERCURRENT) else $error("fault_code_bus did not pick overcurrent");
        // hold the fault so the result stays visible in the waveform
        repeat (20) @(posedge clk);

        // the fault itself clears, but critical_response must stay latched
        overcurrent = 1'b0;
        repeat (5) @(posedge clk);
        assert (critical_response == 1'b1) else $error("critical_response dropped on its own, latch is missing");
        assert (fault_code_bus == CODE_DEFAULT) else $error("fault_code_bus should follow the live fault, not the latch");
        $display("[%0t] overcurrent cleared, critical_response still latched", $time);

        // an unrelated warning fault passes through while the latch is still set
        undervoltage = 1'b1;
        repeat (5) @(posedge clk);
        // skip the debounce wait, the real comparator finishes the last few counts
        force dut.undervoltage_counter = int'(dut.undervoltage_threshold) - 3;
        @(posedge clk);
        release dut.undervoltage_counter;
        repeat (10) @(posedge clk);
        assert (warning_response  == 1'b1) else $error("warning_response not set for undervoltage");
        assert (fault_code_bus == CODE_UNDERVOLTAGE) else $error("fault_code_bus did not follow the new live fault");
        assert (buzzer_pattern == PATTERN_WARNING) else $error("buzzer_pattern did not follow the new live fault");
        assert (critical_response == 1'b1) else $error("critical_response disturbed by an unrelated fault");
        // hold the fault so the result stays visible in the waveform
        repeat (20) @(posedge clk);
        undervoltage = 1'b0;
        repeat (5) @(posedge clk);
        assert (warning_response  == 1'b0) else $error("warning_response did not clear");
        assert (critical_response == 1'b1) else $error("critical_response disturbed after the unrelated fault cleared");
        $display("[%0t] undervoltage came and went, critical_response still latched", $time);

        // a second unrelated fault, this time shutdown-class, same expectation
        overtemperature = 1'b1;
        repeat (5) @(posedge clk);
        // skip the debounce wait, the real comparator finishes the last few counts
        force dut.overtemperature_counter = int'(dut.overtemperature_threshold) - 3;
        @(posedge clk);
        release dut.overtemperature_counter;
        repeat (10) @(posedge clk);
        assert (shutdown_response == 1'b1) else $error("shutdown_response not set for overtemperature");
        assert (fault_code_bus == CODE_OVERTEMPERATURE) else $error("fault_code_bus did not follow overtemperature");
        assert (buzzer_pattern == PATTERN_SHUTDOWN) else $error("buzzer_pattern did not follow overtemperature");
        assert (critical_response == 1'b1) else $error("critical_response disturbed by overtemperature");
        // hold the fault so the result stays visible in the waveform
        repeat (20) @(posedge clk);
        overtemperature = 1'b0;
        repeat (5) @(posedge clk);
        assert (shutdown_response == 1'b0) else $error("shutdown_response did not clear");
        assert (critical_response == 1'b1) else $error("critical_response disturbed after overtemperature cleared");
        $display("[%0t] overtemperature came and went, critical_response still latched", $time);

        // only critical_clear actually releases it
        critical_clear = 1'b1;
        @(posedge clk);
        critical_clear = 1'b0;
        repeat (5) @(posedge clk);
        assert (critical_response == 1'b0) else $error("critical_response did not clear on critical_clear");
        $display("[%0t] critical_clear released the latch, test passed", $time);

        $finish;
    end

endmodule
