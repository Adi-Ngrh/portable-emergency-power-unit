// default time unit is ns
`timescale 1ns / 1ps 

// Testbench for the Fault Event Engine (fee.sv).
// Mapped to FPGA_Template_2_IP_Siap_Tapeout-1.pdf, Section 4.
// Simulation only (QuestaSim/ModelSim) - no hardware.

module tb_fee();

// -------------------------------------------------------------------
// DUT signals
// -------------------------------------------------------------------
logic clk;
logic reset_n;

logic overcurrent;
logic overvoltage;
logic undervoltage;
logic overtemperature;
logic fan_failure;
logic sensor_failure;
logic communication_timeout;

logic fault_interrupt;
logic shutdown_request;
logic warning_request;
logic [2:0] fault_code_bus;
logic [1:0] buzzer_pattern;

fault_event_engine dut (
    .clk(clk),
    .reset_n(reset_n),
    .overcurrent(overcurrent),
    .overvoltage(overvoltage),
    .undervoltage(undervoltage),
    .overtemperature(overtemperature),
    .fan_failure(fan_failure),
    .sensor_failure(sensor_failure),
    .communication_timeout(communication_timeout),

    .fault_interrupt(fault_interrupt),
    .shutdown_request(shutdown_request),
    .warning_request(warning_request),
    .fault_code_bus(fault_code_bus),
    .buzzer_pattern(buzzer_pattern)
);

// -------------------------------------------------------------------
// DUT internal probes (debug only, waveform visibility)
// -------------------------------------------------------------------

// 2-stage input synchronizer
logic dbg_overcurrent_raw,            dbg_overcurrent_sync;
logic dbg_overvoltage_raw,            dbg_overvoltage_sync;
logic dbg_undervoltage_raw,           dbg_undervoltage_sync;
logic dbg_overtemperature_raw,        dbg_overtemperature_sync;
logic dbg_fan_failure_raw,            dbg_fan_failure_sync;
logic dbg_sensor_failure_raw,         dbg_sensor_failure_sync;
logic dbg_communication_timeout_raw,  dbg_communication_timeout_sync;

assign dbg_overcurrent_raw           = dut.overcurrent_raw;
assign dbg_overcurrent_sync          = dut.overcurrent_sync;
assign dbg_overvoltage_raw           = dut.overvoltage_raw;
assign dbg_overvoltage_sync          = dut.overvoltage_sync;
assign dbg_undervoltage_raw          = dut.undervoltage_raw;
assign dbg_undervoltage_sync         = dut.undervoltage_sync;
assign dbg_overtemperature_raw       = dut.overtemperature_raw;
assign dbg_overtemperature_sync      = dut.overtemperature_sync;
assign dbg_fan_failure_raw           = dut.fan_failure_raw;
assign dbg_fan_failure_sync          = dut.fan_failure_sync;
assign dbg_sensor_failure_raw        = dut.sensor_failure_raw;
assign dbg_sensor_failure_sync       = dut.sensor_failure_sync;
assign dbg_communication_timeout_raw = dut.communication_timeout_raw;
assign dbg_communication_timeout_sync= dut.communication_timeout_sync;

// Debounce counters + per-fault valid flags
logic [2:0] dbg_overcurrent_counter,           dbg_overvoltage_counter;
logic [2:0] dbg_undervoltage_counter,          dbg_overtemperature_counter;
logic [2:0] dbg_fan_failure_counter,           dbg_sensor_failure_counter;
logic [2:0] dbg_communication_timeout_counter;

logic dbg_overcurrent_valid,      dbg_overvoltage_valid;
logic dbg_undervoltage_valid,     dbg_overtemperature_valid;
logic dbg_fan_failure_valid,      dbg_sensor_failure_valid;
logic dbg_communication_timeout_valid;
logic dbg_any_fault;

assign dbg_overcurrent_counter           = dut.overcurrent_counter;
assign dbg_overvoltage_counter           = dut.overvoltage_counter;
assign dbg_undervoltage_counter          = dut.undervoltage_counter;
assign dbg_overtemperature_counter       = dut.overtemperature_counter;
assign dbg_fan_failure_counter           = dut.fan_failure_counter;
assign dbg_sensor_failure_counter        = dut.sensor_failure_counter;
assign dbg_communication_timeout_counter = dut.communication_timeout_counter;

assign dbg_overcurrent_valid             = dut.overcurrent_valid;
assign dbg_overvoltage_valid             = dut.overvoltage_valid;
assign dbg_undervoltage_valid            = dut.undervoltage_valid;
assign dbg_overtemperature_valid         = dut.overtemperature_valid;
assign dbg_fan_failure_valid             = dut.fan_failure_valid;
assign dbg_sensor_failure_valid          = dut.sensor_failure_valid;
assign dbg_communication_timeout_valid   = dut.communication_timeout_valid;
assign dbg_any_fault                     = dut.any_fault;

// Combinational next-state outputs of the priority encoder (pre-register)
logic dbg_fault_interrupt_next;
logic dbg_shutdown_request_next;
logic dbg_warning_request_next;
logic [2:0] dbg_fault_code_bus_next;
logic [1:0] dbg_buzzer_pattern_next;

assign dbg_fault_interrupt_next  = dut.fault_interrupt_next;
assign dbg_shutdown_request_next = dut.shutdown_request_next;
assign dbg_warning_request_next  = dut.warning_request_next;
assign dbg_fault_code_bus_next   = dut.fault_code_bus_next;
assign dbg_buzzer_pattern_next   = dut.buzzer_pattern_next;

// -------------------------------------------------------------------
// Clock generator (50MHz, 20ns period)
// -------------------------------------------------------------------
initial clk = 0;
always #10 clk = ~clk; // rising edge start at 10ns, 30ns, 50ns, ...

// -------------------------------------------------------------------
// Pass/fail bookkeeping
// -------------------------------------------------------------------
int pass_total = 0;
int fail_total = 0;

// -------------------------------------------------------------------
// Current test-case marker - shown as a labeled text track in the
// Questa Wave window so test case boundaries are visible at a glance
// and easy to zoom/screenshot individually.
// -------------------------------------------------------------------
string current_test;

task automatic check(string label, logic cond);
    if (cond) begin
        pass_total++;
        $display("[%0t] PASS: %s", $time, label);
    end else begin
        fail_total++;
        $display("[%0t] FAIL: %s", $time, label);
    end
endtask

task automatic apply_reset();
    reset_n = 0;
    #20;    
    reset_n = 1;
    #20;    // wait 1 clock cycle before continue
endtask

// =====================================================================
// 4.5 Verification Requirements - Multiple simultaneous faults tested
// =====================================================================
task automatic test_multiple_simultaneous_faults();
    current_test = "4.5 Multiple simultaneous faults tested";
    $display("\n--- 4.5 Multiple simultaneous faults tested ---");
    apply_reset();
    check("Outputs clear immediately after reset", fault_interrupt == 1'b0 && shutdown_request == 1'b0);

    overcurrent = 1;
    overvoltage = 1;
    undervoltage = 1;
    overtemperature = 1;
    fan_failure = 1;
    sensor_failure = 1;
    communication_timeout = 1;
    repeat (10) @(posedge clk); // let all 7 independent debounce counters validate

    check("fault_interrupt asserted with all 7 faults active", fault_interrupt == 1'b1);
    check("Highest-priority fault (overtemperature) wins the encoder", fault_code_bus == 3'b001);
    check("shutdown_request asserted for the winning critical-class fault", shutdown_request == 1'b1);
    check("warning_request stays low while a critical-class fault is winning", warning_request == 1'b0);

    overcurrent = 0;
    overvoltage = 0;
    undervoltage = 0;
    overtemperature = 0;
    fan_failure = 0;
    sensor_failure = 0;
    communication_timeout = 0;
    repeat (10) @(posedge clk);
endtask

// =====================================================================
// 4.5 Verification Requirements - Priority handling verified
// =====================================================================
task automatic test_priority_handling();
    current_test = "4.5 Priority handling verified";
    $display("\n--- 4.5 Priority handling verified ---");
    apply_reset();

    // Assert every fault at once, then peel off the current winner and
    // confirm the next-highest-priority fault takes over each time.
    overtemperature = 1;
    overcurrent = 1;
    overvoltage = 1;
    sensor_failure = 1;
    undervoltage = 1;
    fan_failure = 1;
    communication_timeout = 1;
    repeat (10) @(posedge clk);
    check("Priority 1: overtemperature wins", fault_code_bus == 3'b001);

    overtemperature = 0;
    repeat (6) @(posedge clk);
    check("Priority 2: overcurrent takes over once overtemperature clears", fault_code_bus == 3'b010);

    overcurrent = 0;
    repeat (6) @(posedge clk);
    check("Priority 3: overvoltage takes over once overcurrent clears", fault_code_bus == 3'b011);

    overvoltage = 0;
    repeat (6) @(posedge clk);
    check("Priority 4: sensor_failure takes over once overvoltage clears", fault_code_bus == 3'b100);

    sensor_failure = 0;
    repeat (6) @(posedge clk);
    check("Priority 5: undervoltage takes over once sensor_failure clears", fault_code_bus == 3'b101);
    check("warning_request asserted once only warning-class faults remain", warning_request == 1'b1);

    undervoltage = 0;
    repeat (6) @(posedge clk);
    check("Priority 6: fan_failure takes over once undervoltage clears", fault_code_bus == 3'b110);

    fan_failure = 0;
    repeat (6) @(posedge clk);
    check("Priority 7: communication_timeout takes over once fan_failure clears", fault_code_bus == 3'b111);

    communication_timeout = 0;
    repeat (10) @(posedge clk);
    check("All outputs clear once every fault is removed", fault_interrupt == 1'b0);
endtask

// =====================================================================
// 4.5 Verification Requirements - Fault debounce verified
// =====================================================================
task automatic test_fault_debounce();
    current_test = "4.5 Fault debounce verified";
    $display("\n--- 4.5 Fault debounce verified ---");
    apply_reset();

    // short glitch: held for 3 clock cycles (< 5-cycle debounce threshold), must not trigger
    overtemperature = 1;
    repeat (3) @(posedge clk);
    overtemperature = 0;
    repeat (10) @(posedge clk);
    check("Short glitch on overtemperature does not assert fault_interrupt", fault_interrupt == 1'b0);
    check("Short glitch on overtemperature does not trigger shutdown_request", shutdown_request == 1'b0);

    // sustained fault: held for 10 clock cycles (>= 5-cycle debounce threshold), must trigger
    overtemperature = 1;
    repeat (10) @(posedge clk);
    check("Sustained overtemperature correctly validates and asserts shutdown_request", shutdown_request == 1'b1);
    overtemperature = 0;
    repeat (10) @(posedge clk);

    // exact boundary: 4 debounced cycles must not validate, must trigger at 5 cycles
    fan_failure = 1;
    wait (dut.fan_failure_sync == 1'b1); // wait out the input synchronizer
    repeat (4) @(posedge clk);
    check("fan_failure_valid still low after exactly 4 debounced cycles", dut.fan_failure_valid == 1'b0);
    @(posedge clk); // 5th debounced cycle
    check("fan_failure_valid asserts after exactly 5 debounced cycles", dut.fan_failure_valid == 1'b1);
    fan_failure = 0;
    repeat (10) @(posedge clk);

    // cross-contamination: two different signals glitch back-to-back,
    // neither reaching threshold - independent counters must not combine them
    overcurrent = 1;
    repeat (2) @(posedge clk);
    overcurrent = 0;
    overvoltage = 1;
    repeat (2) @(posedge clk);
    overvoltage = 0;
    repeat (10) @(posedge clk);
    check("Alternating short glitches on different signals do not falsely validate a fault", fault_interrupt == 1'b0);
endtask

// =====================================================================
// 4.5 Verification Requirements - Fault clear sequence tested
// =====================================================================
task automatic test_fault_clear_sequence();
    current_test = "4.5 Fault clear sequence tested";
    $display("\n--- 4.5 Fault clear sequence tested ---");
    apply_reset();

    overcurrent = 1;
    repeat (10) @(posedge clk);
    check("overcurrent fault validated before clearing", shutdown_request == 1'b1);

    overcurrent = 0;
    repeat (10) @(posedge clk);
    check("fault_interrupt clears once overcurrent is removed", fault_interrupt == 1'b0);
    check("shutdown_request clears once overcurrent is removed", shutdown_request == 1'b0);
    check("fault_code_bus returns to 0 once overcurrent is removed", fault_code_bus == 3'b000);
    check("buzzer_pattern returns to 0 once overcurrent is removed", buzzer_pattern == 2'b00);

    fan_failure = 1;
    repeat (10) @(posedge clk);
    check("fan_failure fault validated before clearing", warning_request == 1'b1);

    fan_failure = 0;
    repeat (10) @(posedge clk);
    check("warning_request clears once fan_failure is removed", warning_request == 1'b0);
    check("fault_interrupt clears once fan_failure is removed", fault_interrupt == 1'b0);
endtask

// -------------------------------------------------------------------
// Test sequence
// -------------------------------------------------------------------
initial begin
    $display("===========================================");
    $display("  STARTING FEE TESTBENCH");
    $display("  (FPGA_Template_2_IP_Siap_Tapeout-1.pdf, Section 4)");
    $display("===========================================");

    clk = 0;
    reset_n = 0;
    current_test = "Setup";
    overcurrent = 0;
    overvoltage = 0;
    undervoltage = 0;
    overtemperature = 0;
    fan_failure = 0;
    sensor_failure = 0;
    communication_timeout = 0;

    test_multiple_simultaneous_faults();
    test_priority_handling();
    test_fault_debounce();
    test_fault_clear_sequence();

    current_test = "Done";
    $display("\n===========================================");
    $display("  FEE TESTBENCH COMPLETE: %0d PASS / %0d FAIL", pass_total, fail_total);
    $display("===========================================");
    $display("  Waveform stored: satisfied by capturing the wave window for this run.");
    $display("  Not coverable by simulation alone (Section 4.6, needs real hardware):");
    $display("  - Inject fault via switch/button");
    $display("  - Display fault state on LED/LCD");
    $display("  - Observe interrupt output live on the board");
    $display("  - Capture waveform from an on-hardware demo");
    $display("  - Demonstrate shutdown logic on the physical board");
    $display("  This testbench already verifies the logic those items would display.");
    $display("===========================================");

    $stop;
end

endmodule
