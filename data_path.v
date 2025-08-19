`timescale 1ns / 1ps
// data_path.sv
// This module handles the data path between the AHB-Lite interface
// and the physical SDRAM data pins (DQ). It manages the bidirectional
// nature of the SDRAM DQ bus.

module data_path #(
    parameter DATA_WIDTH = 32, // Width of the AHB-Lite data bus (e.g., 32)
    parameter DQ_WIDTH   = 32  // Width of the physical SDRAM DQ pins (e.g., 16 or 32)
                               // For simplicity, assuming DQ_WIDTH == DATA_WIDTH for now.
) (
    input                           HCLK,           // System Clock
    input                           HRESETn,        // Active Low Reset

    // Inputs from AHB-Lite Interface
    input  [DATA_WIDTH-1:0]         ahb_wdata_i,        // Write data from AHB-Lite interface
    input                           ahb_wdata_valid_i,  // Valid signal for AHB write data

    // Inputs from SDRAM Command FSM
    input                           cmd_write_active_i, // Indicates SDRAM WRITE command is active
    input                           cmd_read_active_i,  // Indicates SDRAM READ command is active
    input                           sdram_rdata_valid_i,// Valid signal for read data from SDRAM (after CAS latency)

    // Outputs to AHB-Lite Interface
    output reg [DATA_WIDTH-1:0]     sdram_rdata_o,      // Read data to AHB-Lite interface
    output reg                      sdram_rdata_valid_o,// Valid signal for read data to AHB-Lite interface

    // Bidirectional SDRAM Data Pins
    inout  [DQ_WIDTH-1:0]           SDRAM_DQ            // Physical SDRAM Data Bus
);

    // Internal signals for driving and receiving SDRAM_DQ
    reg  [DQ_WIDTH-1:0] sdram_dq_out;   // Data to drive onto SDRAM_DQ
    reg                 sdram_dq_en;    // Output enable for SDRAM_DQ (1=output, 0=input/high-Z)

    // Assign SDRAM_DQ based on direction
    assign SDRAM_DQ = sdram_dq_en ? sdram_dq_out : {DQ_WIDTH{1'bz}}; // Tri-state buffer

    // --- Data Path Logic ---
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            sdram_dq_out        <= {DQ_WIDTH{1'b0}}; // Reset output data
            sdram_dq_en         <= 1'b0;             // Disable output (make it input)
            sdram_rdata_o       <= {DATA_WIDTH{1'b0}}; // Reset read data
            sdram_rdata_valid_o <= 1'b0;             // Reset read data valid
        end else begin
            // Default to input mode (high-Z)
            sdram_dq_en <= 1'b0;

            // Handle Write Operations
            if (cmd_write_active_i && ahb_wdata_valid_i) begin
                // If a write command is active and AHB write data is valid,
                // drive the data onto SDRAM_DQ.
                sdram_dq_out <= ahb_wdata_i; // Assuming DATA_WIDTH == DQ_WIDTH
                sdram_dq_en  <= 1'b1;        // Enable output driver
            end

            // Handle Read Operations
            // Capture data from SDRAM_DQ when a read command is active.
            // The sdram_rdata_valid_i from FSM indicates when the data is stable/valid
            // after CAS latency.
            if (cmd_read_active_i) begin
                sdram_rdata_o <= SDRAM_DQ; // Capture data from the bidirectional bus
            end

            // Pass through the read data valid signal from the SDRAM Command FSM
            sdram_rdata_valid_o <= sdram_rdata_valid_i;
        end
    end

endmodule
