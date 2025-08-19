`timescale 1ns / 1ps
// sdram_init_controller.sv
// This module manages the initial power-up delay and triggers the
// SDRAM command FSM to start the initialization sequence.

module sdram_init_controller #(
    // Initial Power-Up Delay Parameter (in HCLK cycles)
    // This is typically specified in the SDRAM datasheet (e.g., 200us after power stable).
    // For a 100MHz HCLK (10ns period) and 200us delay:
    // Delay cycles = (200 us / 10 ns) = 20,000 cycles.
    parameter INIT_POWER_UP_DELAY_CYCLES = 20000 // Example: 200us for 100MHz HCLK
) (
    input                       HCLK,           // System Clock
    input                       HRESETn,        // Active Low Reset

    // Input from SDRAM Command FSM
    input                       sdram_ready_i,  // Indicates if SDRAM FSM is idle and ready for init command
    input                       sdram_init_ack_i, // NEW: Acknowledgment from SDRAM FSM that init has started/accepted

    // Output to SDRAM Command FSM
    output reg                  init_start_o    // Signal to start SDRAM initialization
);

    // Internal register for the power-up delay timer
    reg [31:0]  init_timer;
    reg         init_done; // Flag to ensure initialization only happens once per reset

    // --- Initialization Logic ---
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            init_timer   <= INIT_POWER_UP_DELAY_CYCLES; // Load initial delay
            init_done    <= 1'b0;    // Initialization not yet done
            init_start_o <= 1'b0;    // No initialization request
        end else begin
            // Default to low, will be asserted when conditions met
            init_start_o <= 1'b0; // This ensures it's de-asserted unless re-asserted by logic below

            if (!init_done) begin // Only proceed if initialization is not yet complete
                if (init_timer > 0) begin
                    init_timer <= init_timer - 1; // Count down the delay
                end else begin
                    // Delay has expired
                    if (sdram_ready_i && !init_start_o) begin
                        // If SDRAM FSM is ready AND we haven't already asserted init_start_o
                        // (i.e., we are ready to send the command), assert it.
                        init_start_o <= 1'b1;
                    end else if (init_start_o && sdram_init_ack_i) begin
                        // If init_start_o is asserted AND we receive acknowledgment,
                        // then we can de-assert init_start_o and mark initialization as complete.
                        init_start_o <= 1'b0;
                        init_done    <= 1'b1;
                    end
                    // If sdram_ready_i is not high, or if init_start_o is already high
                    // but no ack, the system waits.
                    // The init_timer will stay at 0 after expiration.
                end
            end
            // Once init_done is 1'b1, init_start_o will remain 0 due to the default assignment
            // and the `if (!init_done)` gate.
        end
    end

endmodule