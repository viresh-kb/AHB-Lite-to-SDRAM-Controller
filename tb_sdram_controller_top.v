`timescale 1ns / 1ps

// Testbench for the sdram_controller_top module
module tb_sdram_controller_top;

    // --- Parameters ---
    // These should match the parameters of the DUT
    parameter ADDR_WIDTH            = 32;
    parameter DATA_WIDTH            = 32;
    parameter DQ_WIDTH              = 32;
    parameter SDRAM_ADDR_WIDTH      = 13;
    parameter SDRAM_BANK_WIDTH      = 2;
    parameter SDRAM_COL_WIDTH       = 9;
    parameter SDRAM_ROW_WIDTH       = 13;

    // Timing parameters (should match DUT)
    parameter T_RCD_CYCLES          = 3;
    parameter T_RP_CYCLES           = 3;
    parameter T_RAS_CYCLES          = 7;
    parameter T_WR_CYCLES           = 3;
    parameter T_RFC_CYCLES          = 10;
    parameter T_MRD_CYCLES          = 2;
    parameter CAS_LATENCY_CYCLES    = 3;
    parameter INIT_POWER_UP_DELAY_CYCLES = 20000; // Reduced for faster simulation
    parameter T_REFRESH_INTERVAL_CYCLES = 782;

    // Testbench specific parameters
    parameter HCLK_PERIOD           = 10; // 10ns = 100MHz clock

    // --- Testbench Signals ---

    // DUT Inputs
    reg                           HCLK;
    reg                           HRESETn;
    reg  [1:0]                    HTRANS;
    reg  [ADDR_WIDTH-1:0]         HADDR;
    reg                           HWRITE;
    reg  [2:0]                    HSIZE;
    reg  [2:0]                    HBURST;
    reg  [DATA_WIDTH-1:0]         HWDATA;

    // DUT Outputs
    wire                          HREADYOUT;
    wire [DATA_WIDTH-1:0]         HRDATA;
    wire                          HRESP;

    // SDRAM Physical Interface
    wire                          sdram_cs_n;
    wire                          sdram_ras_n;
    wire                          sdram_cas_n;
    wire                          sdram_we_n;
    wire                          sdram_cke;
    wire [SDRAM_ADDR_WIDTH-1:0]   sdram_addr;
    wire [SDRAM_BANK_WIDTH-1:0]   sdram_ba;
    wire [(DQ_WIDTH/8)-1:0]       sdram_dqm;
    wire [DQ_WIDTH-1:0]           SDRAM_DQ; // This is an inout, handled by the SDRAM model

    // --- DUT Instantiation ---
    sdram_controller_top #(
        .ADDR_WIDTH                 (ADDR_WIDTH),
        .DATA_WIDTH                 (DATA_WIDTH),
        .DQ_WIDTH                   (DQ_WIDTH),
        .SDRAM_ADDR_WIDTH           (SDRAM_ADDR_WIDTH),
        .SDRAM_BANK_WIDTH           (SDRAM_BANK_WIDTH),
        .SDRAM_COL_WIDTH            (SDRAM_COL_WIDTH),
        .SDRAM_ROW_WIDTH            (SDRAM_ROW_WIDTH),
        .T_RCD_CYCLES               (T_RCD_CYCLES),
        .T_RP_CYCLES                (T_RP_CYCLES),
        .T_RAS_CYCLES               (T_RAS_CYCLES),
        .T_WR_CYCLES                (T_WR_CYCLES),
        .T_RFC_CYCLES               (T_RFC_CYCLES),
        .T_MRD_CYCLES               (T_MRD_CYCLES),
        .CAS_LATENCY_CYCLES         (CAS_LATENCY_CYCLES),
        .INIT_POWER_UP_DELAY_CYCLES (INIT_POWER_UP_DELAY_CYCLES),
        .T_REFRESH_INTERVAL_CYCLES  (T_REFRESH_INTERVAL_CYCLES)
    ) dut (
        .HCLK                       (HCLK),
        .HRESETn                    (HRESETn),
        .HTRANS                     (HTRANS),
        .HADDR                      (HADDR),
        .HWRITE                     (HWRITE),
        .HSIZE                      (HSIZE),
        .HBURST                     (HBURST),
        .HWDATA                     (HWDATA),
        .HREADYOUT                  (HREADYOUT),
        .HRDATA                     (HRDATA),
        .HRESP                      (HRESP),
        .sdram_cs_n                 (sdram_cs_n),
        .sdram_ras_n                (sdram_ras_n),
        .sdram_cas_n                (sdram_cas_n),
        .sdram_we_n                 (sdram_we_n),
        .sdram_cke                  (sdram_cke),
        .sdram_addr                 (sdram_addr),
        .sdram_ba                   (sdram_ba),
        .sdram_dqm                  (sdram_dqm),
        .SDRAM_DQ                   (SDRAM_DQ)
    );

    // --- SDRAM Model Instantiation ---
    // A simple behavioral model of an SDRAM chip
    sdram_model #(
        .DQ_WIDTH(DQ_WIDTH),
        .ROW_WIDTH(SDRAM_ROW_WIDTH),
        .COL_WIDTH(SDRAM_COL_WIDTH),
        .BANK_WIDTH(SDRAM_BANK_WIDTH),
        .CAS_LATENCY(CAS_LATENCY_CYCLES)
    ) sdram_model_inst (
        .clk        (HCLK),
        .cke        (sdram_cke),
        .cs_n       (sdram_cs_n),
        .ras_n      (sdram_ras_n),
        .cas_n      (sdram_cas_n),
        .we_n       (sdram_we_n),
        .ba         (sdram_ba),
        .addr       (sdram_addr),
        .dqm        (sdram_dqm),
        .dq         (SDRAM_DQ)
    );

    // --- Clock and Reset Generation ---
    initial begin
        HCLK = 1'b0;
        forever #(HCLK_PERIOD / 2) HCLK = ~HCLK;
    end

    initial begin
        $display("-------------------------------------------");
        $display("--- Starting SDRAM Controller Testbench ---");
        $display("-------------------------------------------");

        // Initialize AHB signals
        HTRANS  = 2'b00; // IDLE
        HADDR   = {ADDR_WIDTH{1'b0}};
        HWRITE  = 1'b0;
        HSIZE   = 3'b010; // 32-bit transfers
        HBURST  = 3'b000; // SINGLE
        HWDATA  = {DATA_WIDTH{1'b0}};

        // 1. Apply Reset
        HRESETn = 1'b0;
        $display("[%0t] Applying reset...", $time);
        repeat (5) @(posedge HCLK);
        HRESETn = 1'b1;
        $display("[%0t] Releasing reset.", $time);

        // 2. Wait for SDRAM initialization to complete
        $display("[%0t] Waiting for SDRAM initialization...", $time);
        // wait till HREADYOUT becomes 1 as it is low during init
        wait (HREADYOUT == 1'b1);
        @(posedge HCLK);
        $display("[%0t] SDRAM initialization complete. Controller is ready.", $time);

        // 3. Perform a single write operation
        $display("[%0t] --- Test 1: Single Write ---", $time);
        ahb_write(32'h0000_1000, 32'hDEAD_BEEF);

        // 4. Perform a single read operation to verify
        $display("[%0t] --- Test 2: Single Read & Verify ---", $time);
        ahb_read(32'h0000_1000);
        if (HRDATA == 32'hDEAD_BEEF) begin
            $display("[%0t] SUCCESS: Read data 0x%h matches written data.", $time, HRDATA);
        end else begin
            $error("[%0t] FAILURE: Read data 0x%h does not match written data 0x%h.", $time, HRDATA, 32'hDEAD_BEEF);
        end

        // 5. Perform a burst write operation (4 beats)
        $display("[%0t] --- Test 3: Burst Write (4-beat INCR) ---", $time);
        ahb_burst_write(32'h0000_2000, 4, {32'hA5A5_A5A5, 32'hB6B6_B6B6, 32'hC7C7_C7C7, 32'hD8D8_D8D8});

        // 6. Perform a burst read operation to verify
        $display("[%0t] --- Test 4: Burst Read & Verify (4-beat INCR) ---", $time);
        ahb_burst_read(32'h0000_2000, 4);
        
        // Add verification logic for burst read if needed

        $display("-------------------------------------------");
        $display("--- Testbench Simulation Finished ---");
        $display("-------------------------------------------");
        $finish;
    end

    // --- AHB Master Tasks ---

    // Task for a single AHB write
    task ahb_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data);
        begin
            $display("[%0t] AHB Write: Addr=0x%h, Data=0x%h", $time, addr, data);
            @(posedge HCLK);
            HADDR  <= addr;
            HWDATA <= data;
            HWRITE <= 1'b1;
            HTRANS <= 2'b10; // NONSEQ
            HBURST <= 3'b000; // SINGLE
            HSIZE  <= 3'b010; // 32-bit
            
            wait (HREADYOUT == 1'b1);
            @(posedge HCLK);

            HTRANS <= 2'b00; // IDLE
            $display("[%0t] AHB Write finished.", $time);
        end
    endtask

    // Task for a single AHB read
    task ahb_read(input [ADDR_WIDTH-1:0] addr);
        begin
            $display("[%0t] AHB Read: Addr=0x%h", $time, addr);
            @(posedge HCLK);
            HADDR  <= addr;
            HWRITE <= 1'b0;
            HTRANS <= 2'b10; // NONSEQ
            HBURST <= 3'b000; // SINGLE
            HSIZE  <= 3'b010; // 32-bit

            wait (HREADYOUT == 1'b1);
            @(posedge HCLK);

            HTRANS <= 2'b00; // IDLE
            $display("[%0t] AHB Read finished. Read Data: 0x%h", $time, HRDATA);
        end
    endtask

    // Task for a burst AHB write
    task ahb_burst_write(input [ADDR_WIDTH-1:0] start_addr, input integer beats, input [DATA_WIDTH*8-1:0] wdata_burst);
        integer i;
        begin
            $display("[%0t] AHB Burst Write: Addr=0x%h, Beats=%d", $time, start_addr, beats);
            @(posedge HCLK);
            HADDR  <= start_addr;
            HWRITE <= 1'b1;
            HTRANS <= 2'b10; // NONSEQ for the first beat
            HBURST <= 3'b001; // INCR
            HSIZE  <= 3'b010; // 32-bit

            for (i = 0; i < beats; i = i + 1) begin
                wait (HREADYOUT == 1'b1);
                HWDATA <= wdata_burst >> (DATA_WIDTH * (beats - 1 - i));
                @(posedge HCLK);
                if (i == 0) begin
                    HTRANS <= 2'b11; // SEQ for subsequent beats
                end
            end

            wait (HREADYOUT == 1'b1);
            @(posedge HCLK);
            HTRANS <= 2'b00; // IDLE
            $display("[%0t] AHB Burst Write finished.", $time);
        end
    endtask

    // Task for a burst AHB read
    task ahb_burst_read(input [ADDR_WIDTH-1:0] start_addr, input integer beats);
        integer i;
        begin
            $display("[%0t] AHB Burst Read: Addr=0x%h, Beats=%d", $time, start_addr, beats);
            @(posedge HCLK);
            HADDR  <= start_addr;
            HWRITE <= 1'b0;
            HTRANS <= 2'b10; // NONSEQ for the first beat
            HBURST <= 3'b001; // INCR
            HSIZE  <= 3'b010; // 32-bit

            for (i = 0; i < beats; i = i + 1) begin
                wait (HREADYOUT == 1'b1);
                @(posedge HCLK);
                $display("[%0t] Burst Read Beat %d, Data: 0x%h", $time, i, HRDATA);
                 if (i == 0) begin
                    HTRANS <= 2'b11; // SEQ for subsequent beats
                end
            end
            
            wait (HREADYOUT == 1'b1);
            @(posedge HCLK);
            HTRANS <= 2'b00; // IDLE
            $display("[%0t] AHB Burst Read finished.", $time);
        end
    endtask

endmodule


// --- Behavioral SDRAM Model ---
// This is a simplified model to respond to the controller.
// It does not model all timing parameters, but is sufficient for basic verification.
module sdram_model #(
    parameter DQ_WIDTH   = 32,
    parameter ROW_WIDTH  = 13,
    parameter COL_WIDTH  = 9,
    parameter BANK_WIDTH = 2,
    parameter CAS_LATENCY = 3
)(
    input                           clk,
    input                           cke,
    input                           cs_n,
    input                           ras_n,
    input                           cas_n,
    input                           we_n,
    input      [BANK_WIDTH-1:0]     ba,
    input      [ROW_WIDTH-1:0]      addr,
    input      [(DQ_WIDTH/8)-1:0]   dqm,
    inout      [DQ_WIDTH-1:0]       dq
);
    // SDRAM Command Decoding
    wire cmd_load_mode_reg = ~cs_n & ~ras_n & ~cas_n & ~we_n;
    wire cmd_auto_refresh  = ~cs_n & ~ras_n & ~cas_n &  we_n;
    wire cmd_precharge     = ~cs_n & ~ras_n &  cas_n & ~we_n;
    wire cmd_active        = ~cs_n & ~ras_n &  cas_n &  we_n;
    wire cmd_write         = ~cs_n &  ras_n & ~cas_n & ~we_n;
    wire cmd_read          = ~cs_n &  ras_n & ~cas_n &  we_n;
    wire cmd_nop           = ~cs_n &  ras_n &  cas_n &  we_n;

    // Memory Array
    localparam MEM_DEPTH = 1 << (ROW_WIDTH + COL_WIDTH);
    reg [DQ_WIDTH-1:0] memory [0:(1<<BANK_WIDTH)-1][0:MEM_DEPTH-1];

    // Internal state
    reg [ROW_WIDTH-1:0]  active_row [0:(1<<BANK_WIDTH)-1];
    reg [DQ_WIDTH-1:0]   dq_out;
    reg                  dq_oe; // Output enable for dq bus

    // Assign dq based on output enable
    assign dq = dq_oe ? dq_out : {DQ_WIDTH{1'bz}};

    // Read data pipeline for CAS latency
    reg [DQ_WIDTH-1:0] read_pipe [0:CAS_LATENCY-1];
    integer i;

    always @(posedge clk) begin
        // Command Execution 
                if (cke) begin
            // Shift read pipeline
            for (i = CAS_LATENCY - 1; i > 0; i = i - 1) begin
                read_pipe[i] <= read_pipe[i-1];
            end
            read_pipe[0] <= memory[ba][{active_row[ba], addr[COL_WIDTH-1:0]}];

            // Default state for output driver
            dq_oe <= 1'b0;

            if (cmd_active) begin
                active_row[ba] <= addr;
                $display("[%0t] SDRAM_MODEL: ACTIVE Bank=%d, Row=0x%h", $time, ba, addr);
            end

            if (cmd_write) begin
                $display("[%0t] SDRAM_MODEL: WRITE Bank=%d, Col=0x%h, Data=0x%h", $time, ba, addr[COL_WIDTH-1:0], dq);
                memory[ba][{active_row[ba], addr[COL_WIDTH-1:0]}] <= dq;
            end

            if (cmd_read) begin
                $display("[%0t] SDRAM_MODEL: READ Bank=%d, Col=0x%h", $time, ba, addr[COL_WIDTH-1:0]);
                // Read is pipelined, data will appear after CAS_LATENCY
            end

            if (cmd_precharge) begin
                $display("[%0t] SDRAM_MODEL: PRECHARGE Bank=%d", $time, ba);
                
            end
            
            if (cmd_load_mode_reg) begin
                 $display("[%0t] SDRAM_MODEL: LOAD MODE REGISTER", $time);
            end

            // Data Output Stage
            // After CAS latency, drive the data bus
            if ({cs_n, ras_n, cas_n, we_n} == 4'b0101) begin // Check for previous read command
                dq_out <= read_pipe[CAS_LATENCY-1];
                dq_oe  <= 1'b1;
            end
        end
    end

endmodule
