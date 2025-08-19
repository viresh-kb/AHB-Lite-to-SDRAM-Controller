`timescale 1ns / 1ps
// ahb_lite_interface.sv
// This module acts as the AHB-Lite slave interface for the SDRAM controller.
// It receives requests from the AHB-Lite master, buffers data, and
// provides control/data signals to the internal SDRAM controller logic.

module ahb_lite_interface #(
    parameter ADDR_WIDTH = 32,  // AHB-Lite Address Bus Width
    parameter DATA_WIDTH = 32,  // AHB-Lite Data Bus Width
    parameter W_FIFO_DEPTH = 8, // Depth of the write data FIFO (for buffering HWDATA)
    parameter R_FIFO_DEPTH = 8  // Depth of the read data FIFO (for buffering HRDATA)
) (
    // AHB-Lite Slave Interface Signals (Inputs from AHB-Lite Master)
    input                           HCLK,       // System Clock
    input                           HRESETn,    // Active Low Reset
    input  [1:0]                    HTRANS,     // Transfer Type (IDLE, BUSY, NON-SEQ, SEQ)
    input  [ADDR_WIDTH-1:0]         HADDR,      // Address Bus
    input                           HWRITE,     // Write (1) / Read (0) Transfer
    input  [2:0]                    HSIZE,      // Transfer Size (Byte, Half-word, Word)
    input  [2:0]                    HBURST,     // Burst Type and Length
    input  [DATA_WIDTH-1:0]         HWDATA,     // Write Data Bus

    // AHB-Lite Slave Interface Signals (Outputs to AHB-Lite Master)
    output reg                      HREADYOUT,  // Ready Output (1=Ready, 0=Wait)
    output reg [DATA_WIDTH-1:0]     HRDATA,     // Read Data Bus
    output reg                      HRESP,      // Transfer Response (0=OKAY, 1=ERROR)

    // Interface to Internal SDRAM Controller Logic (Outputs)
    output reg [ADDR_WIDTH-1:0]     ahb_addr_o,         // Address for SDRAM controller
    output reg                      ahb_write_o,        // Write enable for SDRAM controller
    output reg [2:0]                ahb_size_o,         // Transfer size for SDRAM controller
    output reg [2:0]                ahb_burst_o,        // Burst type for SDRAM controller
    output reg                      ahb_valid_o,        // Indicates a valid AHB request to SDRAM controller
    output wire [DATA_WIDTH-1:0]    ahb_wdata_o,        // Write data from FIFO to SDRAM controller
    output wire                     ahb_wdata_valid_o,  // Indicates valid write data available

    // Interface from Internal SDRAM Controller Logic (Inputs)
    input  [DATA_WIDTH-1:0]         sdram_rdata_i,      // Read data from SDRAM core
    input                           sdram_rdata_valid_i,// Indicates valid read data from SDRAM core
    input                           sdram_ready_i,      // Indicates if SDRAM controller is ready for new request
    input                           sdram_error_i       // Indicates an error from SDRAM controller
);

    // Custom function to calculate ceiling of log2 (for pointer width)
    function integer clogb2;
        input integer value;
        integer i;
        begin
            if (value == 0) clogb2 = 0;
            else begin
                clogb2 = 0;
                for (i = 0; (1 << i) < value; i = i + 1) begin
                    clogb2 = i + 1;
                end
            end
        end
    endfunction

    // --- Internal Signals ---
    // Registers to hold the current AHB-Lite transaction information
    reg  [ADDR_WIDTH-1:0]   ahb_addr_next; // Use next-state registers for pipelining
    reg                     ahb_write_next;
    reg  [2:0]              ahb_size_next;
    reg  [2:0]              ahb_burst_next;

    // AHB-Lite Transfer Type decoding
    localparam HTRANS_IDLE    = 2'b00;
    localparam HTRANS_BUSY    = 2'b01;
    localparam HTRANS_NONSEQ  = 2'b10;
    localparam HTRANS_SEQ     = 2'b11;

    // --- Write FIFO (AHB-Lite to SDRAM Controller) ---
    localparam W_PTR_WIDTH = clogb2(W_FIFO_DEPTH);
    reg [DATA_WIDTH-1:0] w_fifo_mem [0:W_FIFO_DEPTH-1];
    reg [W_PTR_WIDTH:0]  w_fifo_wr_ptr, w_fifo_rd_ptr; // Pointer + 1 bit for full/empty logic
    reg [W_PTR_WIDTH:0]  w_fifo_count;
    wire                 w_fifo_full;
    wire                 w_fifo_empty;
    wire                 w_fifo_write_en; // Signal to write into FIFO
    wire                 w_fifo_read_en;  // Signal to read from FIFO

    assign w_fifo_full = (w_fifo_count == W_FIFO_DEPTH);
    assign w_fifo_empty = (w_fifo_count == 0);

    // Write enable for FIFO: AHB master wants to write AND FIFO is not full AND interface is ready
    // HSEL replaced with 1'b1
    assign w_fifo_write_en = 1'b1 && HWRITE && HREADYOUT && (HTRANS == HTRANS_NONSEQ || HTRANS == HTRANS_SEQ) && !w_fifo_full;
    // Read enable for FIFO: SDRAM controller is ready AND FIFO is not empty
    assign w_fifo_read_en = sdram_ready_i && !w_fifo_empty;

    // Output data from FIFO (Combinational assignment for wires)
    assign ahb_wdata_o       = w_fifo_mem[w_fifo_rd_ptr[W_PTR_WIDTH-1:0]];
    assign ahb_wdata_valid_o = !w_fifo_empty; // Data valid if FIFO is not empty

    // Write FIFO Logic (Sequential)
    integer j; 
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            w_fifo_wr_ptr <= {W_PTR_WIDTH+1{1'b0}};
            w_fifo_rd_ptr <= {W_PTR_WIDTH+1{1'b0}};
            w_fifo_count  <= {W_PTR_WIDTH+1{1'b0}};
            // Initialize FIFO memory to avoid 'X' propagation
            for (j = 0; j < W_FIFO_DEPTH; j = j + 1) begin
                w_fifo_mem[j] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            // Write operation
            if (w_fifo_write_en) begin
                w_fifo_mem[w_fifo_wr_ptr[W_PTR_WIDTH-1:0]] <= HWDATA;
                w_fifo_wr_ptr <= w_fifo_wr_ptr + 1;
                w_fifo_count  <= w_fifo_count + 1;
            end

            // Read operation
            if (w_fifo_read_en) begin
                w_fifo_rd_ptr <= w_fifo_rd_ptr + 1;
                w_fifo_count  <= w_fifo_count - 1;
            end
        end
    end

    // --- Read FIFO (SDRAM Controller to AHB-Lite) ---
    localparam R_PTR_WIDTH = clogb2(R_FIFO_DEPTH);
    reg [DATA_WIDTH-1:0] r_fifo_mem [0:R_FIFO_DEPTH-1];
    reg [R_PTR_WIDTH:0]  r_fifo_wr_ptr, r_fifo_rd_ptr;
    reg [R_PTR_WIDTH:0]  r_fifo_count;
    wire                 r_fifo_full;
    wire                 r_fifo_empty;
    wire                 r_fifo_write_en; // Signal to write into FIFO
    wire                 r_fifo_read_en;  // Signal to read from FIFO

    assign r_fifo_full = (r_fifo_count == R_FIFO_DEPTH);
    assign r_fifo_empty = (r_fifo_count == 0);

    // Write enable for FIFO: SDRAM core has valid data AND FIFO is not full
    assign r_fifo_write_en = sdram_rdata_valid_i && !r_fifo_full;
    // Read enable for FIFO: AHB master is reading AND FIFO is not empty AND interface is ready
    // HSEL replaced with 1'b1
    assign r_fifo_read_en = !HWRITE && 1'b1 && HREADYOUT && (HTRANS == HTRANS_NONSEQ || HTRANS == HTRANS_SEQ) && !r_fifo_empty;

    // Read FIFO Logic (Sequential)
    integer k; // Declared outside for loop for Verilog-2001 compatibility
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            r_fifo_wr_ptr <= {R_PTR_WIDTH+1{1'b0}};
            r_fifo_rd_ptr <= {R_PTR_WIDTH+1{1'b0}};
            r_fifo_count  <= {R_PTR_WIDTH+1{1'b0}};
            HRDATA        <= {DATA_WIDTH{1'b0}};
            // Initialize FIFO memory to avoid 'X' propagation
            for (k = 0; k < R_FIFO_DEPTH; k = k + 1) begin
                r_fifo_mem[k] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            // Write operation
            if (r_fifo_write_en) begin
                r_fifo_mem[r_fifo_wr_ptr[R_PTR_WIDTH-1:0]] <= sdram_rdata_i;
                r_fifo_wr_ptr <= r_fifo_wr_ptr + 1;
                r_fifo_count  <= r_fifo_count + 1;
            end

            // Read operation
            if (r_fifo_read_en) begin
                r_fifo_rd_ptr <= r_fifo_rd_ptr + 1;
                r_fifo_count  <= r_fifo_count - 1;
            end

            // Output data from FIFO
            HRDATA <= r_fifo_mem[r_fifo_rd_ptr[R_PTR_WIDTH-1:0]];
        end
    end

    // --- AHB-Lite Slave Logic (HREADYOUT and HRESP) ---
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HREADYOUT       <= 1'b1;        // Ready by default on reset
            HRESP           <= 1'b0;       // OKAY response
            ahb_addr_o      <= {ADDR_WIDTH{1'b0}};
            ahb_write_o     <= 1'b0;
            ahb_size_o      <= 3'b000;
            ahb_burst_o     <= 3'b000;
            ahb_valid_o     <= 1'b0; // No valid request on reset
            ahb_addr_next   <= {ADDR_WIDTH{1'b0}};
            ahb_write_next  <= 1'b0;
            ahb_size_next   <= 3'b000;
            ahb_burst_next  <= 3'b000;
        end else begin
            // Default HREADYOUT to 1'b1 (ready)
            HREADYOUT <= 1'b1;
            HRESP     <= 1'b0; // Default to OKAY response

            // Latch AHB-Lite request for next cycle's output
            ahb_addr_next   <= ahb_addr_next; // Retain previous value by default
            ahb_write_next  <= ahb_write_next;
            ahb_size_next   <= ahb_size_next;
            ahb_burst_next  <= ahb_burst_next;

            // HREADYOUT control:
            // The slave must assert HREADYOUT when it is ready to complete the transfer.
            // For reads,  data is available in the read FIFO.
            // For writes, write FIFO has space.
            // HSEL replaced with 1'b1
            if (1'b1 && (HTRANS == HTRANS_NONSEQ || HTRANS == HTRANS_SEQ)) begin
                if (HWRITE) begin
                    // Ready if write FIFO is not full
                    if (!w_fifo_full) begin
                        HREADYOUT <= 1'b1;
                    end else begin
                        HREADYOUT <= 1'b0; // Not ready, insert wait state
                    end
                end else begin // Read transfer
                    // Ready if read FIFO is not empty
                    if (!r_fifo_empty) begin
                        HREADYOUT <= 1'b1;
                    end else begin
                        HREADYOUT <= 1'b0; // Not ready, insert wait state
                    end
                end
            end else if (HTRANS == HTRANS_BUSY) begin 
                // For BUSY transfers, the slave must always return HREADYOUT high.
                HREADYOUT <= 1'b1;
            end else begin 
                // For IDLE transfers, HREADYOUT is always high.
                HREADYOUT <= 1'b1;
            end

            // Latch AHB-Lite request if HREADYOUT is high (previous transfer complete)
            // and it's a new non-idle/busy transfer.
            
            if (1'b1 && HREADYOUT && (HTRANS == HTRANS_NONSEQ || HTRANS == HTRANS_SEQ)) begin
                ahb_addr_next   <= HADDR;
                ahb_write_next  <= HWRITE;
                ahb_size_next   <= HSIZE;
                ahb_burst_next  <= HBURST;
                ahb_valid_o     <= 1'b1; // Signal a new valid request to the SDRAM core
            end else begin
                ahb_valid_o     <= 1'b0; // No new request or transfer not ready
            end

            // Transfer latched 'next' values to 'current' outputs for the SDRAM controller
            ahb_addr_o      <= ahb_addr_next;
            ahb_write_o     <= ahb_write_next;
            ahb_size_o      <= ahb_size_next;
            ahb_burst_o     <= ahb_burst_next;

            // Handle HRESP (Error response from SDRAM controller)
            if (sdram_error_i) begin
                HRESP <= 1'b1; // ERROR response
            end else begin
                HRESP <= 1'b0; // OKAY response
            end
        end
    end

endmodule