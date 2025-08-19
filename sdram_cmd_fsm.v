`timescale 1ns / 1ps
// sdram_cmd_fsm.sv
// This module implements the Finite State Machine for controlling SDRAM commands.
// It handles initialization, refresh, and basic read/write operations,
// adhering to SDRAM timing specifications.

module sdram_cmd_fsm #(
    parameter ADDR_WIDTH        = 32,   // AHB-Lite Address Bus Width
    parameter DATA_WIDTH        = 32,   // AHB-Lite Data Bus Width (e.g., 32-bit for AHB)
    parameter SDRAM_ADDR_WIDTH  = 13,   // Total SDRAM Address Pins (e.g., A0-A12)
    parameter SDRAM_BANK_WIDTH  = 2,    // Number of SDRAM Bank Address Pins (e.g., BA0, BA1 for 4 banks)
    parameter SDRAM_COL_WIDTH   = 9,    // Number of SDRAM Column Address Pins (e.g., A0-A8)
    parameter SDRAM_ROW_WIDTH   = 13,   // Number of SDRAM Row Address Pins (e.g., A0-A12)
                                        // Note: SDRAM_ADDR_WIDTH is usually max(SDRAM_COL_WIDTH, SDRAM_ROW_WIDTH)

    // SDRAM Timing Parameters (in HCLK cycles) - ***MUST BE DERIVED FROM SDRAM DATASHEET***
    // Example values for a 100MHz HCLK and typical SDR SDRAM:
    parameter T_RCD_CYCLES      = 3,    // tRCD: Active to Read/Write delay
    parameter T_RP_CYCLES       = 3,    // tRP: Precharge command period
    parameter T_RAS_CYCLES      = 7,    // tRAS: Row Active time
    parameter T_WR_CYCLES       = 3,    // tWR: Write Recovery time
    parameter T_RFC_CYCLES      = 10,   // tRFC: Auto-Refresh Cycle time
    parameter T_MRD_CYCLES      = 2,    // tMRD: Load Mode Register to Active/Refresh/Read/Write delay
    parameter CAS_LATENCY_CYCLES= 3,    // CAS Latency (CL) in clock cycles
    parameter INIT_DELAY_CYCLES = 200000 // Initial power-up delay (now managed by init_controller)
) (
    input                           HCLK,       // System Clock
    input                           HRESETn,    // Active Low Reset

    // Inputs from AHB-Lite Interface
    input  [ADDR_WIDTH-1:0]         ahb_addr_i,         // Full AHB Address (for latching)
    input                           ahb_write_i,        // Write (1) / Read (0) from AHB-Lite
    input  [2:0]                    ahb_size_i,         // Transfer Size from AHB-Lite
    input  [2:0]                    ahb_burst_i,        // Burst Type from AHB-Lite
    input                           ahb_valid_i,        // Valid request from AHB-Lite interface
    input  [DATA_WIDTH-1:0]         ahb_wdata_i,        // Write data from AHB-Lite interface FIFO
    input                           ahb_wdata_valid_i,  // Write data valid from AHB-Lite interface FIFO

    // Inputs from Address Mapper
    input  [SDRAM_BANK_WIDTH-1:0]   ahb_bank_addr_i,    // Bank address from mapper
    input  [SDRAM_ROW_WIDTH-1:0]    ahb_row_addr_i,     // Row address from mapper
    input  [SDRAM_COL_WIDTH-1:0]    ahb_col_addr_i,     // Column address from mapper

    // Inputs from Refresh Controller
    input                           refresh_req_i,      // Request for auto-refresh

    // Input from Init Controller
    input                           init_start_i,       // Signal to start initialization sequence

    // Outputs to AHB-Lite Interface
    // Removed sdram_rdata_o as data_path handles this directly
    output reg                      sdram_rdata_valid_o,// Read data valid to AHB-Lite interface FIFO
    output reg                      sdram_ready_o,      // SDRAM controller ready for new AHB request
    output reg                      sdram_error_o,      // Error signal to AHB-Lite interface

    // Outputs for Data Path
    output reg                      cmd_write_active_o, // Indicates SDRAM WRITE command is active
    output reg                      cmd_read_active_o,  // Indicates SDRAM READ command is active

    // Outputs to SDRAM Device (Physical Pins)
    output reg                      sdram_cs_n_o,       // Chip Select (active low)
    output reg                      sdram_ras_n_o,      // Row Address Strobe (active low)
    output reg                      sdram_cas_n_o,      // Column Address Strobe (active low)
    output reg                      sdram_we_n_o,       // Write Enable (active low)
    output reg                      sdram_cke_o,        // Clock Enable
    output reg [SDRAM_ADDR_WIDTH-1:0] sdram_addr_o,     // SDRAM Address Bus
    output reg [SDRAM_BANK_WIDTH-1:0] sdram_ba_o,       // SDRAM Bank Address Bus
    output reg [(DATA_WIDTH/8)-1:0] sdram_dqm_o         // Data Mask (active high, one bit per byte)
);

    // --- FSM State Definitions ---
    localparam [4:0] // Adjust width based on number of states
        // Initialization States
        // S_INIT_POWER_UP_DELAY is now handled by sdram_init_controller
        S_INIT_PRECHARGE_ALL    = 5'd1,
        S_INIT_LOAD_MODE_REG    = 5'd2,
        S_INIT_AUTO_REFRESH1    = 5'd3,
        S_INIT_AUTO_REFRESH2    = 5'd4,
        S_IDLE                  = 5'd5,

        // Command Processing States
        S_ACTIVE                = 5'd6,
        S_READ                  = 5'd7,
        S_WRITE                 = 5'd8,
        S_PRECHARGE_BANK        = 5'd9,
        S_AUTO_REFRESH          = 5'd10,

        // Wait States (for timing parameters)
        S_WAIT_T_RCD            = 5'd11,
        S_WAIT_T_RP             = 5'd12,
        S_WAIT_T_RAS            = 5'd13, // For active command
        S_WAIT_T_WR             = 5'd14,
        S_WAIT_T_RFC            = 5'd15,
        S_WAIT_T_MRD            = 5'd16,
        S_WAIT_CAS_LATENCY      = 5'd17;

    reg [4:0] current_state, next_state;

    // --- Internal Registers and Counters ---
    reg [ADDR_WIDTH-1:0]    latched_ahb_addr;
    reg                     latched_ahb_write;
    reg  [2:0]              latched_ahb_size;
    reg  [2:0]              latched_ahb_burst;
    reg                     ahb_request_pending; // Flag to indicate an AHB request is waiting

    reg [SDRAM_ROW_WIDTH-1:0]   current_row_addr;
    reg [SDRAM_COL_WIDTH-1:0]   current_col_addr;
    reg [SDRAM_BANK_WIDTH-1:0]  current_bank_addr;
    reg [SDRAM_ROW_WIDTH-1:0]   active_bank_state [0:((1<<SDRAM_BANK_WIDTH)-1)]; // Tracks which row is active in each bank

    reg [31:0]              timer_count; // Generic timer for delays
    reg                     refresh_in_progress; // Flag for refresh cycle

    // --- SDRAM Command Decoding (Mode Register) ---
    localparam [SDRAM_ADDR_WIDTH-1:0] SDRAM_MODE_REG_VALUE = {
        4'b0000, // Burst Type (Sequential)
        3'b011,  // CAS Latency (CL=3)
        3'b011,  // Burst Length (8)
        1'b0,    // Op Mode (Standard)
        3'b000   // Write Burst Mode (Programmed Burst Length)
    };

    // --- Output Assignments (Combinational Logic) ---
    always @(*) begin
        sdram_cs_n_o    = 1'b1;
        sdram_ras_n_o   = 1'b1;
        sdram_cas_n_o   = 1'b1;
        sdram_we_n_o    = 1'b1;
        sdram_cke_o     = 1'b1; // Assume CKE is always high after initial power-up
        sdram_addr_o    = {SDRAM_ADDR_WIDTH{1'b0}};
        sdram_ba_o      = {SDRAM_BANK_WIDTH{1'b0}};
        sdram_dqm_o     = {(DATA_WIDTH/8){1'b0}}; // No data mask by default

        // sdram_rdata_o removed as data_path drives actual data to AHB IF
        sdram_rdata_valid_o = 1'b0;
        sdram_ready_o       = 1'b0; // Default to not ready
        sdram_error_o       = 1'b0; // Default to no error

        cmd_write_active_o  = 1'b0; // Default to inactive
        cmd_read_active_o   = 1'b0; // Default to inactive

        // Assign outputs based on current state
        case (current_state)
            S_INIT_PRECHARGE_ALL: begin
                sdram_cs_n_o    = 1'b0;
                sdram_ras_n_o   = 1'b0;
                sdram_cas_n_o   = 1'b1;
                sdram_we_n_o    = 1'b0;
                sdram_addr_o    = {SDRAM_ADDR_WIDTH-1'd1,{1'b0}, 1'b1}; // A10 high for Precharge All
            end
            S_INIT_LOAD_MODE_REG: begin
                sdram_cs_n_o    = 1'b0;
                sdram_ras_n_o   = 1'b0;
                sdram_cas_n_o   = 1'b0;
                sdram_we_n_o    = 1'b0;
                sdram_addr_o    = SDRAM_MODE_REG_VALUE;
            end
            S_INIT_AUTO_REFRESH1, S_INIT_AUTO_REFRESH2, S_AUTO_REFRESH: begin
                sdram_cs_n_o    = 1'b0;
                sdram_ras_n_o   = 1'b0;
                sdram_cas_n_o   = 1'b0;
                sdram_we_n_o    = 1'b1; // RAS, CAS low, WE high for Auto Refresh
            end
            S_ACTIVE: begin
                sdram_cs_n_o    = 1'b0;
                sdram_ras_n_o   = 1'b0;
                sdram_cas_n_o   = 1'b1;
                sdram_we_n_o    = 1'b1;
                sdram_addr_o    = current_row_addr;
                sdram_ba_o      = current_bank_addr;
            end
            S_READ: begin
                sdram_cs_n_o    = 1'b0;
                sdram_ras_n_o   = 1'b1;
                sdram_cas_n_o   = 1'b0;
                sdram_we_n_o    = 1'b1;
                sdram_addr_o    = current_col_addr;
                sdram_ba_o      = current_bank_addr;
                sdram_rdata_valid_o = (timer_count == 0); // Data valid when timer reaches 0 after CAS Latency
                cmd_read_active_o   = 1'b1; // Assert read active to data_path
            end
            S_WRITE: begin
                sdram_cs_n_o    = 1'b0;
                sdram_ras_n_o   = 1'b1;
                sdram_cas_n_o   = 1'b0;
                sdram_we_n_o    = 1'b0;
                sdram_addr_o    = current_col_addr;
                sdram_ba_o      = current_bank_addr;
                sdram_dqm_o     = {(DATA_WIDTH/8){1'b0}}; // Data mask low for all bytes (write all)
                cmd_write_active_o  = 1'b1; // Assert write active to data_path
            end
            S_PRECHARGE_BANK: begin
                sdram_cs_n_o    = 1'b0;
                sdram_ras_n_o   = 1'b0;
                sdram_cas_n_o   = 1'b1;
                sdram_we_n_o    = 1'b0;
                sdram_addr_o    = {SDRAM_ADDR_WIDTH-1'd1,{1'b0}, 1'b0}; // A10 high for Precharge Single Bank
                sdram_ba_o      = current_bank_addr;
            end
            default: begin
                // All other states (IDLE, WAIT states) are NOPs for SDRAM
                sdram_cs_n_o    = 1'b1;
                sdram_ras_n_o   = 1'b1;
                sdram_cas_n_o   = 1'b1;
                sdram_we_n_o    = 1'b1;
                sdram_addr_o    = {SDRAM_ADDR_WIDTH{1'b0}};
                sdram_ba_o      = {SDRAM_BANK_WIDTH{1'b0}};
                sdram_dqm_o     = {(DATA_WIDTH/8){1'b0}};
            end
        endcase

        // sdram_ready_o is high when in IDLE state and no refresh is pending
        sdram_ready_o = (current_state == S_IDLE && !refresh_in_progress);
        sdram_error_o = 1'b0; // Simplified: no error detection in this FSM
    end

    // --- FSM Sequential Logic ---
    integer i; // Declare loop variable outside the for loop for Verilog-2001 compatibility

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            current_state       <= S_IDLE; // Start in IDLE, init_controller will trigger init
            latched_ahb_addr    <= {ADDR_WIDTH{1'b0}};
            latched_ahb_write   <= 1'b0;
            latched_ahb_size    <= 3'b000;
            latched_ahb_burst   <= 3'b000;
            ahb_request_pending <= 1'b0;
            timer_count         <= 32'd0;
            refresh_in_progress <= 1'b0;
            // Explicitly reset address registers to clear "set/reset with same priority" warning
            current_row_addr    <= {SDRAM_ROW_WIDTH{1'b0}};
            current_col_addr    <= {SDRAM_COL_WIDTH{1'b0}};
            current_bank_addr   <= {SDRAM_BANK_WIDTH{1'b0}};

            // Initialize active_bank_state (all banks are inactive)
            for (i = 0; i < (1<<SDRAM_BANK_WIDTH); i=i+1) begin
                active_bank_state[i] <= {SDRAM_ROW_WIDTH{1'b0}}; // Indicates no row active
            end
        end else begin
            // State Register
            current_state <= next_state;

            // Timer for delays
            if (timer_count > 0) begin
                timer_count <= timer_count - 1;
            end

            // Latch AHB request if in IDLE and valid request comes in
            if (current_state == S_IDLE && ahb_valid_i && !ahb_request_pending) begin
                latched_ahb_addr    <= ahb_addr_i;
                latched_ahb_write   <= ahb_write_i;
                latched_ahb_size    <= ahb_size_i;
                latched_ahb_burst   <= ahb_burst_i;
                ahb_request_pending <= 1'b1; // Mark request as pending
            end

            // Update current row/col/bank addresses based on latched AHB address
            // These now come from the address_mapper module
            current_col_addr    <= ahb_col_addr_i;
            current_row_addr    <= ahb_row_addr_i;
            current_bank_addr   <= ahb_bank_addr_i;

            // --- Next State Logic (Sequential Part of FSM) ---
            case (current_state)
                S_IDLE: begin
                    if (init_start_i) begin // Check for initialization request
                        timer_count <= T_RP_CYCLES; // Wait tRP after precharge all
                        next_state  <= S_INIT_PRECHARGE_ALL;
                    end else if (refresh_req_i) begin
                        timer_count         <= T_RFC_CYCLES;
                        refresh_in_progress <= 1'b1;
                        next_state          <= S_AUTO_REFRESH;
                    end else if (ahb_request_pending) begin
                        // Check if the requested bank/row is already active
                        if (active_bank_state[ahb_bank_addr_i] == ahb_row_addr_i) begin
                            // Row hit: proceed directly to Read/Write
                            if (latched_ahb_write) begin
                                next_state <= S_WRITE;
                            end else begin
                                timer_count <= CAS_LATENCY_CYCLES; // Start CAS latency timer
                                next_state <= S_READ;
                            end
                        end else begin
                            // Row miss: need to precharge (if active) and then activate
                            if (active_bank_state[ahb_bank_addr_i] != {SDRAM_ROW_WIDTH{1'b0}}) begin // If any row is active in this bank
                                timer_count <= T_RP_CYCLES; // Precharge delay
                                next_state  <= S_PRECHARGE_BANK;
                            end else begin
                                timer_count <= T_RCD_CYCLES; // Active to Read/Write delay
                                next_state  <= S_ACTIVE;
                            end
                        end
                        ahb_request_pending <= 1'b0; // Consume the request
                    end else begin
                        next_state <= S_IDLE;
                    end
                end

                S_INIT_PRECHARGE_ALL: begin
                    if (timer_count == 0) begin
                        timer_count <= T_RP_CYCLES; // Wait tRP after precharge all
                        next_state  <= S_INIT_LOAD_MODE_REG;
                    end else begin
                        next_state  <= S_INIT_PRECHARGE_ALL; // Continue waiting if timer not 0
                    end
                end
                S_INIT_LOAD_MODE_REG: begin
                    if (timer_count == 0) begin
                        timer_count <= T_MRD_CYCLES; // Wait tMRD after mode register load
                        next_state  <= S_INIT_AUTO_REFRESH1;
                    end else begin
                        next_state  <= S_INIT_LOAD_MODE_REG; // Continue waiting
                    end
                end
                S_INIT_AUTO_REFRESH1: begin
                    if (timer_count == 0) begin
                        timer_count <= T_RFC_CYCLES; // Wait tRFC after refresh
                        next_state  <= S_INIT_AUTO_REFRESH2;
                    end else begin
                        next_state  <= S_INIT_AUTO_REFRESH1; // Continue waiting
                    end
                end
                S_INIT_AUTO_REFRESH2: begin
                    if (timer_count == 0) begin
                        timer_count <= T_RFC_CYCLES; // Wait tRFC after refresh
                        next_state  <= S_IDLE; // Initialization complete
                    end else begin
                        next_state  <= S_INIT_AUTO_REFRESH2; // Continue waiting
                    end
                end

                S_PRECHARGE_BANK: begin
                    if (timer_count == 0) begin
                        active_bank_state[current_bank_addr] <= {SDRAM_ROW_WIDTH{1'b0}}; // Mark bank as inactive
                        timer_count <= T_RCD_CYCLES; // Wait tRCD after precharge for next active
                        next_state  <= S_ACTIVE;
                    end else begin
                        next_state <= S_WAIT_T_RP; // Wait for precharge to complete
                    end
                end
                S_ACTIVE: begin
                    if (timer_count == 0) begin
                        active_bank_state[current_bank_addr] <= current_row_addr; // Mark row as active
                        if (latched_ahb_write) begin
                            next_state <= S_WRITE;
                        end else begin
                            timer_count <= CAS_LATENCY_CYCLES; // Start CAS latency timer
                            next_state <= S_READ;
                        end
                    end else begin
                        next_state <= S_WAIT_T_RCD; // Wait for active to complete
                    end
                end
                S_READ: begin
                    // In a real burst, this state would loop for burst length.
                    // For simplicity, assuming single word read for now.
                    if (timer_count == 0) begin
                        // Data is now valid and sent to AHB interface.
                        // For a burst, you'd increment column address and loop.
                        // For single read, go back to IDLE or prepare for next command.
                        next_state <= S_IDLE;
                    end else begin
                        next_state <= S_WAIT_CAS_LATENCY;
                    end
                end
                S_WRITE: begin
                    // In a real burst, this state would loop for burst length.
                    // For simplicity, assuming single word write for now.
                    timer_count <= T_WR_CYCLES; // Start write recovery timer
                    next_state  <= S_WAIT_T_WR;
                end
                S_WAIT_T_WR: begin
                    if (timer_count == 0) begin
                        next_state <= S_IDLE;
                    end else begin
                        next_state <= S_WAIT_T_WR;
                    end
                end
                S_AUTO_REFRESH: begin
                    if (timer_count == 0) begin
                        refresh_in_progress <= 1'b0;
                        next_state          <= S_IDLE;
                    end else begin
                        next_state <= S_WAIT_T_RFC;
                    end
                end

                // Generic Wait States (just decrement timer)
                S_WAIT_T_RCD: begin
                    if (timer_count == 0) next_state <= S_ACTIVE;
                    else next_state <= S_WAIT_T_RCD;
                end
                S_WAIT_T_RP: begin
                    if (timer_count == 0) next_state <= S_ACTIVE;
                    else next_state <= S_WAIT_T_RP;
                end
                S_WAIT_T_RAS: begin
                    if (timer_count == 0) next_state <= S_IDLE;
                    else next_state <= S_WAIT_T_RAS;
                end
                S_WAIT_T_RFC: begin
                    if (timer_count == 0) next_state <= S_IDLE;
                    else next_state <= S_WAIT_T_RFC;
                end
                S_WAIT_T_MRD: begin
                    if (timer_count == 0) next_state <= S_INIT_AUTO_REFRESH1;
                    else next_state <= S_WAIT_T_MRD;
                end
                S_WAIT_CAS_LATENCY: begin
                    if (timer_count == 0) next_state <= S_IDLE;
                    else next_state <= S_WAIT_CAS_LATENCY;
                end

                default: next_state = S_IDLE; // Should not happen, but for safety
            endcase
        end
    end

endmodule