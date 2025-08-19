`timescale 1ns / 1ps
// sdram_refresh_controller.sv
// This module generates periodic refresh requests for the SDRAM controller.

module sdram_refresh_controller #(
    // Refresh Interval Parameter (in HCLK cycles)
    // This is derived from the SDRAM's tREFI (e.g., 64ms for common SDR SDRAM)
    // divided by the number of rows that need to be refreshed per tREFI period.
    // For a 100MHz HCLK (10ns period) and tREFI = 64ms, with 8192 rows (typical for 256Mbit SDRAM):
    // Refresh interval = (64ms / 8192 rows) = 7.8125 us per row
    // In clock cycles: (7.8125 us / 10 ns) = 781.25 cycles. Round up to 782 cycles.
    // This parameter MUST be calculated based on your specific SDRAM datasheet and HCLK frequency.
    parameter T_REFRESH_INTERVAL_CYCLES = 782 // Example: 7.8125us for 100MHz HCLK
) (
    input                       HCLK,           // System Clock
    input                       HRESETn,        // Active Low Reset

    // Input from SDRAM Command FSM
    input                       sdram_ready_i,  // Indicates if SDRAM FSM is idle and ready for a refresh

    // Output to SDRAM Command FSM
    output reg                  refresh_req_o   // Request for auto-refresh
);

    // Internal register for the refresh timer
    reg [31:0] refresh_timer;

    // --- Refresh Logic ---
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            refresh_timer <= 32'd0; // Reset timer
            refresh_req_o <= 1'b0;  // No refresh request
        end else begin
            // Decrement timer if not zero
            if (refresh_timer > 0) begin
                refresh_timer <= refresh_timer - 1;
                refresh_req_o <= 1'b0; // De-assert request while counting
            end else begin
                // Timer has reached zero, a refresh is due
                if (sdram_ready_i) begin
                    // If SDRAM FSM is ready, assert refresh request and reload timer
                    refresh_req_o <= 1'b1;
                    refresh_timer <= T_REFRESH_INTERVAL_CYCLES - 1; // Reload timer
                end else begin
                    // If SDRAM FSM is not ready, keep request low and wait for readiness
                    refresh_req_o <= 1'b0;
                    // The timer remains at 0, waiting for sdram_ready_i to go high
                end
            end
        end
    end

endmodule