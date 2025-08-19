`timescale 1ns / 1ps
// ahb_lite_interface_tb.v
// Very Simplified Testbench for the ahb_lite_interface module.
// Focuses on basic AHB-Lite slave functionality with direct signal driving.
// Robust initialization to avoid 'X' conditions.

module ahb_lite_interface_tb;

    // --- Testbench Parameters (Match DUT parameters) ---
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam W_FIFO_DEPTH = 8; // Must match DUT's W_FIFO_DEPTH
    localparam R_FIFO_DEPTH = 8; // Must match DUT's R_FIFO_DEPTH

    // --- Clock and Reset Generation ---
    reg HCLK;
    reg HRESETn;
    localparam CLK_PERIOD = 10; // 10ns for 100MHz clock

    initial begin
        HCLK = 0;
        forever #(CLK_PERIOD / 2) HCLK = ~HCLK; // Generate 100MHz clock
    end

    // --- AHB-Lite Master Signals (Testbench outputs, DUT inputs) ---
    // HSEL removed from here as it's removed from DUT
    reg  [1:0] HTRANS;
    reg  [ADDR_WIDTH-1:0] HADDR;
    reg  HWRITE;
    reg  [2:0] HSIZE;
    reg  [2:0] HBURST;
    reg  [DATA_WIDTH-1:0] HWDATA;

    // --- AHB-Lite Slave Signals (Testbench inputs, DUT outputs) ---
    wire HREADYOUT;
    wire [DATA_WIDTH-1:0] HRDATA;
    wire [1:0] HRESP;

    // --- SDRAM Core Interface Signals (Testbench outputs, DUT inputs) ---
    reg  [DATA_WIDTH-1:0] sdram_rdata_i;
    reg  sdram_rdata_valid_i;
    reg  sdram_ready_i; // Simulates SDRAM core's readiness to accept commands/data
    reg  sdram_error_i;

    // --- SDRAM Controller Logic Interface Signals (Testbench inputs, DUT outputs) ---
    wire [ADDR_WIDTH-1:0] ahb_addr_o;
    wire ahb_write_o;
    wire [2:0] ahb_size_o;
    wire [2:0] ahb_burst_o;
    wire ahb_valid_o;
    wire [DATA_WIDTH-1:0] ahb_wdata_o;
    wire ahb_wdata_valid_o;


    // --- Instantiate the DUT ---
    ahb_lite_interface #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .W_FIFO_DEPTH   (W_FIFO_DEPTH),
        .R_FIFO_DEPTH   (R_FIFO_DEPTH)
    ) dut (
        .HCLK               (HCLK),
        .HRESETn            (HRESETn),
        // .HSEL removed from instantiation
        .HTRANS             (HTRANS),
        .HADDR              (HADDR),
        .HWRITE             (HWRITE),
        .HSIZE              (HSIZE),
        .HBURST             (HBURST),
        .HWDATA             (HWDATA),
        .HREADYOUT          (HREADYOUT),
        .HRDATA             (HRDATA),
        .HRESP              (HRESP),

        .ahb_addr_o         (ahb_addr_o),
        .ahb_write_o        (ahb_write_o),
        .ahb_size_o         (ahb_size_o),
        .ahb_burst_o        (ahb_burst_o),
        .ahb_valid_o        (ahb_valid_o),
        .ahb_wdata_o        (ahb_wdata_o),
        .ahb_wdata_valid_o  (ahb_wdata_valid_o),

        .sdram_rdata_i      (sdram_rdata_i),
        .sdram_rdata_valid_i(sdram_rdata_valid_i),
        .sdram_ready_i      (sdram_ready_i),
        .sdram_error_i      (sdram_error_i)
    );

    // --- SDRAM Core Behavior (Simplified) ---
    // This block simulates the SDRAM core's readiness and data provision.
    // No internal memory model for simplicity, just fixed dummy data.
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            sdram_ready_i       <= 0; // Not ready during reset
            sdram_rdata_valid_i <= 0; // No valid read data
            sdram_rdata_i       <= {DATA_WIDTH{1'b0}};
            sdram_error_i       <= 0;
        end else begin
            // SDRAM core is ready by default, unless explicitly made busy by testbench
            sdram_ready_i <= 1; // Always drive sdram_ready_i to a known value
            sdram_error_i <= 0; // No error by default

            // Simulate SDRAM core consuming write data from DUT
            if (ahb_wdata_valid_o && ahb_valid_o && ahb_write_o) begin
                $display("TB: @%0t: SDRAM Core: Received Write Data 0x%h for Addr 0x%h", $time, ahb_wdata_o, ahb_addr_o);
                sdram_ready_i <= 0; // Simulate processing delay
                # (CLK_PERIOD * 2); // Simulate 2 cycle processing delay
                sdram_ready_i <= 1;
            end

            // Simulate SDRAM core providing read data to DUT
            sdram_rdata_valid_i <= 0; // Default to not valid
            if (ahb_valid_o && !ahb_write_o) begin
                $display("TB: @%0t: SDRAM Core: Initiating Read for Addr 0x%h", $time, ahb_addr_o);
                sdram_ready_i <= 0; // Simulate processing delay
                # (CLK_PERIOD * 3); // Simulate CAS Latency (e.g., 3 cycles)
                sdram_rdata_i <= 32'hFEED_BEEF; // Provide fixed dummy data
                sdram_rdata_valid_i <= 1; // Data is now valid
                $display("TB: @%0t: SDRAM Core: Provided Read Data 0x%h", $time, sdram_rdata_i);
                sdram_ready_i <= 1;
            end
        end
    end

    // --- Test Scenario ---
    initial begin
        // Initialize all AHB master signals to a known state at time 0
        // HSEL removed from here
        HTRANS = 2'b00; // IDLE
        HADDR = 0;
        HWDATA = 0;
        HWRITE = 0;
        HSIZE = 0;
        HBURST = 0;

        // Reset sequence
        HRESETn = 0; // Assert reset
        #200;        // Hold reset for 200ns
        HRESETn = 1; // De-assert reset
        #100;        // Wait a bit after reset de-assertion to stabilize

        $display("TB: @%0t: Reset complete. Starting test scenario.", $time);

        # (CLK_PERIOD * 5); // Wait some idle cycles

        // --- Test 1: Single AHB Write Transaction ---
        $display("TB: @%0t: --- Test 1: Single AHB Write (Addr 0x1000) ---", $time);
        @(posedge HCLK);
        HADDR  = 32'h1000;
        HWDATA = 32'hABCD_1234;
        HWRITE = 1;
        HSIZE  = 3'b010; // Word access
        HBURST = 3'b000; // Single burst
        HTRANS = 2'b10;  // NONSEQ
        // HSEL removed from here
        
        @(posedge HCLK); // Address phase starts
        while (HREADYOUT == 0) @(posedge HCLK); // Wait for slave to be ready (data phase)
        $display("TB: @%0t: AHB Write transaction completed.", $time);

        @(posedge HCLK); // End of transaction, transition to IDLE
        // HSEL removed from here
        HTRANS = 2'b00; // IDLE
        # (CLK_PERIOD * 5); // Wait some idle cycles

        // --- Test 2: Single AHB Read Transaction ---
        $display("TB: @%0t: --- Test 2: Single AHB Read (Addr 0x1000) ---", $time);
        @(posedge HCLK);
        HADDR  = 32'h1000;
        HWRITE = 0;
        HSIZE  = 3'b010; // Word access
        HBURST = 3'b000; // Single burst
        HTRANS = 2'b10;  // NONSEQ
        // HSEL removed from here
        
        @(posedge HCLK); // Address phase starts
        while (HREADYOUT == 0) @(posedge HCLK); // Wait for slave to be ready (data phase)
        $display("TB: @%0t: AHB Read transaction completed. ReadData=0x%h", $time, HRDATA);

        @(posedge HCLK); // End of transaction, transition to IDLE
        // HSEL removed from here
        HTRANS = 2'b00; // IDLE
        # (CLK_PERIOD * 5); // Wait some idle cycles

        $display("TB: @%0t: Test scenario complete.", $time);
        #100;
        $finish; // End simulation
    end

    // --- Monitoring ---
    always @(posedge HCLK) begin
        // HSEL removed from display
        $display("MON: @%0t: HTRANS=%b, HADDR=0x%h, HWRITE=%b, HWDATA=0x%h, HREADYOUT=%b, HRDATA=0x%h, HRESP=%b",
                 $time, HTRANS, HADDR, HWRITE, HWDATA, HREADYOUT, HRDATA, HRESP);
        $display("MON: @%0t: ahb_valid_o=%b, ahb_write_o=%b, ahb_addr_o=0x%h, ahb_wdata_o=0x%h, ahb_wdata_valid_o=%b",
                 $time, ahb_valid_o, ahb_write_o, ahb_addr_o, ahb_wdata_o, ahb_wdata_valid_o);
        $display("MON: @%0t: sdram_rdata_i=0x%h, sdram_rdata_valid_i=%b, sdram_ready_i=%b, sdram_error_i=%b",
                 $time, sdram_rdata_i, sdram_rdata_valid_i, sdram_ready_i, sdram_error_i);
        $display("--------------------------------------------------------------------------------------------------");
    end

endmodule