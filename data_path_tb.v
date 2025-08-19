`timescale 1ns / 1ps
// data_path_tb.sv
// Testbench for the data_path module.

module data_path_tb;

    // Parameters for the testbench - MUST match DUT parameters
    parameter DATA_WIDTH_TB = 32;
    parameter DQ_WIDTH_TB   = 32;

    // Declare signals for DUT inputs
    reg  HCLK;
    reg  HRESETn;
    reg  [DATA_WIDTH_TB-1:0] ahb_wdata_i;
    reg  ahb_wdata_valid_i;
    reg  cmd_write_active_i;
    reg  cmd_read_active_i;
    reg  sdram_rdata_valid_i;

    // Declare wires for DUT outputs
    wire [DATA_WIDTH_TB-1:0] sdram_rdata_o;
    wire sdram_rdata_valid_o;

    // Declare wire for the bidirectional SDRAM_DQ bus
    // This needs to be a wire in the testbench, as it's an inout in the DUT.
    // We will use a 'reg' to drive it when simulating external data.
    wire [DQ_WIDTH_TB-1:0] SDRAM_DQ_tb; // Testbench side of the DQ bus

    // Connect the DUT's inout port to the testbench wire
    // This allows the testbench to monitor and also drive the bus.
    assign SDRAM_DQ_tb = dut.SDRAM_DQ;

    // Internal reg to drive SDRAM_DQ_tb when simulating read data
    reg [DQ_WIDTH_TB-1:0] sdram_dq_driver;
    reg sdram_dq_driver_en; // Enable for the testbench driver

    // Tri-state driver for simulating external data on SDRAM_DQ
    // This assigns to the DUT's SDRAM_DQ directly when sdram_dq_driver_en is high.
    // When sdram_dq_driver_en is low, it means the DUT can drive SDRAM_DQ.
    assign dut.SDRAM_DQ = sdram_dq_driver_en ? sdram_dq_driver : {DQ_WIDTH_TB{1'bz}};


    // Instantiate the Device Under Test (DUT)
    data_path #(
        .DATA_WIDTH(DATA_WIDTH_TB),
        .DQ_WIDTH  (DQ_WIDTH_TB)
    ) dut (
        .HCLK               (HCLK),
        .HRESETn            (HRESETn),
        .ahb_wdata_i        (ahb_wdata_i),
        .ahb_wdata_valid_i  (ahb_wdata_valid_i),
        .cmd_write_active_i (cmd_write_active_i),
        .cmd_read_active_i  (cmd_read_active_i),
        .sdram_rdata_valid_i(sdram_rdata_valid_i),
        .sdram_rdata_o      (sdram_rdata_o),
        .sdram_rdata_valid_o(sdram_rdata_valid_o),
        .SDRAM_DQ           (SDRAM_DQ_tb) // Connect to the testbench wire
    );

    // Clock generation
    parameter HCLK_PERIOD = 10; // 10ns for 100MHz HCLK
    initial begin
        HCLK = 1'b0;
        forever #(HCLK_PERIOD / 2) HCLK = ~HCLK;
    end

    // Test sequence
    initial begin
        $display("-----------------------------------------------------");
        $display("Starting Data Path Testbench");
        $display("DATA_WIDTH: %0d, DQ_WIDTH: %0d", DATA_WIDTH_TB, DQ_WIDTH_TB);
        $display("-----------------------------------------------------");

        // 1. Initial Reset State
        HRESETn             = 1'b0; // Assert active-low reset
        ahb_wdata_i         = {DATA_WIDTH_TB{1'b0}};
        ahb_wdata_valid_i   = 1'b0;
        cmd_write_active_i  = 1'b0;
        cmd_read_active_i   = 1'b0;
        sdram_rdata_valid_i = 1'b0;
        sdram_dq_driver     = {DQ_WIDTH_TB{1'b0}};
        sdram_dq_driver_en  = 1'b0; // Testbench not driving DQ initially

        #(HCLK_PERIOD * 5); // Hold reset for a few clock cycles
        $display("[%0t] After reset, sdram_dq_en (DUT) = %b, sdram_rdata_o = 0x%H, sdram_rdata_valid_o = %b",
                 $time, dut.sdram_dq_en, sdram_rdata_o, sdram_rdata_valid_o);
        // Expected: dut.sdram_dq_en=0, sdram_rdata_o=0, sdram_rdata_valid_o=0

        // 2. De-assert Reset and enter idle state
        HRESETn = 1'b1; // De-assert reset
        #(HCLK_PERIOD);
        $display("[%0t] After reset de-assertion (Idle state). sdram_dq_en (DUT) = %b, SDRAM_DQ_tb = %z",
                 $time, dut.sdram_dq_en, SDRAM_DQ_tb);
        // Expected: dut.sdram_dq_en=0, SDRAM_DQ_tb=z (driven by DUT's high-Z)

        // 3. Test Write Operation
        $display("-----------------------------------------------------");
        $display("[%0t] Test Case: Write Operation", $time);
        ahb_wdata_i        = 32'hDEADBEEF;
        ahb_wdata_valid_i  = 1'b1;
        cmd_write_active_i = 1'b1;
        #(HCLK_PERIOD); // Apply inputs for one clock cycle
        $display("[%0t] Write Cycle 1: ahb_wdata_i=0x%H, ahb_wdata_valid_i=%b, cmd_write_active_i=%b",
                 $time, ahb_wdata_i, ahb_wdata_valid_i, cmd_write_active_i);
        $display("[%0t] Write Cycle 1: DUT sdram_dq_en=%b, SDRAM_DQ_tb=0x%H",
                 $time, dut.sdram_dq_en, SDRAM_DQ_tb);
        // Expected: dut.sdram_dq_en=1, SDRAM_DQ_tb=0xDEADBEEF

        // De-assert write signals
        ahb_wdata_valid_i  = 1'b0;
        cmd_write_active_i = 1'b0;
        #(HCLK_PERIOD);
        $display("[%0t] After Write: ahb_wdata_valid_i=%b, cmd_write_active_i=%b",
                 $time, ahb_wdata_valid_i, cmd_write_active_i);
        $display("[%0t] After Write: DUT sdram_dq_en=%b, SDRAM_DQ_tb=%z",
                 $time, dut.sdram_dq_en, SDRAM_DQ_tb);
        // Expected: dut.sdram_dq_en=0, SDRAM_DQ_tb=z (DUT should release bus)

        // 4. Test Read Operation
        $display("-----------------------------------------------------");
        $display("[%0t] Test Case: Read Operation", $time);

        // Simulate external data on SDRAM_DQ from the testbench
        sdram_dq_driver_en = 1'b1; // Enable testbench driver
        sdram_dq_driver    = 32'hCAFEF00D; // Data to be read

        cmd_read_active_i  = 1'b1; // Assert read command
        #(HCLK_PERIOD * 2); // Allow time for CAS latency (simulated)
        $display("[%0t] Read Cycle (before valid): cmd_read_active_i=%b, SDRAM_DQ_tb=0x%H",
                 $time, cmd_read_active_i, SDRAM_DQ_tb);
        // Expected: sdram_rdata_o should have captured 0xCAFEF00D, but sdram_rdata_valid_o is 0

        sdram_rdata_valid_i = 1'b1; // Assert read data valid from FSM
        #(HCLK_PERIOD);
        $display("[%0t] Read Cycle (valid): sdram_rdata_valid_i=%b", $time, sdram_rdata_valid_i);
        $display("[%0t] Read Cycle (valid): sdram_rdata_o=0x%H, sdram_rdata_valid_o=%b",
                 $time, sdram_rdata_o, sdram_rdata_valid_o);
        // Expected: sdram_rdata_o=0xCAFEF00D, sdram_rdata_valid_o=1

        // De-assert read signals and testbench driver
        cmd_read_active_i   = 1'b0;
        sdram_rdata_valid_i = 1'b0;
        sdram_dq_driver_en  = 1'b0; // Disable testbench driver
        #(HCLK_PERIOD);
        $display("[%0t] After Read: sdram_rdata_o=0x%H, sdram_rdata_valid_o=%b",
                 $time, sdram_rdata_o, sdram_rdata_valid_o);
        $display("[%0t] After Read: SDRAM_DQ_tb=%z", $time, SDRAM_DQ_tb);
        // Expected: sdram_rdata_valid_o=0, SDRAM_DQ_tb=z

        // 5. Test simultaneous read and write (should not happen in real FSM, but good for robustness)
        $display("-----------------------------------------------------");
        $display("[%0t] Test Case: Simultaneous Read/Write (Error Condition)", $time);
        ahb_wdata_i        = 32'hAAAAAAAA;
        ahb_wdata_valid_i  = 1'b1;
        cmd_write_active_i = 1'b1;
        cmd_read_active_i  = 1'b1;
        sdram_dq_driver_en = 1'b1;
        sdram_dq_driver    = 32'hBBBBBBBB;
        #(HCLK_PERIOD);
        $display("[%0t] Simultaneous: DUT sdram_dq_en=%b, SDRAM_DQ_tb=0x%H, sdram_rdata_o=0x%H",
                 $time, dut.sdram_dq_en, SDRAM_DQ_tb, sdram_rdata_o);
        // Expected: DUT should prioritize write, so sdram_dq_en=1, SDRAM_DQ_tb=0xAAAAAAAA
        // sdram_rdata_o will capture 0xAAAAAAAA (what DUT drives)

        // Clean up
        ahb_wdata_valid_i  = 1'b0;
        cmd_write_active_i = 1'b0;
        cmd_read_active_i  = 1'b0;
        sdram_dq_driver_en = 1'b0;
        #(HCLK_PERIOD);
        $display("-----------------------------------------------------");
        $display("[%0t] Testbench finished.", $time);
        $finish; // End simulation
    end

    // Monitor signals (optional, but good for debugging)
    initial begin
        $monitor("Time: %0t | HCLK: %b | HRESETn: %b | ahb_wdata_i: 0x%H | ahb_wdata_valid_i: %b | cmd_write_active_i: %b | cmd_read_active_i: %b | sdram_rdata_valid_i: %b | SDRAM_DQ (TB): 0x%H | SDRAM_DQ (DUT): 0x%H | sdram_dq_en (DUT): %b | sdram_rdata_o: 0x%H | sdram_rdata_valid_o: %b",
                 $time, HCLK, HRESETn, ahb_wdata_i, ahb_wdata_valid_i, cmd_write_active_i, cmd_read_active_i, sdram_rdata_valid_i, SDRAM_DQ_tb, dut.SDRAM_DQ, dut.sdram_dq_en, sdram_rdata_o, sdram_rdata_valid_o);
    end

endmodule