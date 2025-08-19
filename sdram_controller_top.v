`timescale 1ns / 1ps
// sdram_controller_top.sv
// Top-level module for the AHB-Lite to SDRAM Controller.
// Integrates the AHB-Lite interface, SDRAM command FSM,
// refresh controller, init controller, and data path.

module sdram_controller_top #(
    // --- Global Parameters ---
    parameter ADDR_WIDTH            = 32,   // AHB-Lite Address Bus Width
    parameter DATA_WIDTH            = 32,   // AHB-Lite Data Bus Width (e.g., 32-bit)
    parameter DQ_WIDTH              = 32,   // Physical SDRAM DQ pins width (e.g., 16 or 32)

    // --- SDRAM Specific Parameters (MUST BE DERIVED FROM SDRAM DATASHEET) ---
    parameter SDRAM_ADDR_WIDTH      = 13,   // Total SDRAM Address Pins (e.g., A0-A12)
    parameter SDRAM_BANK_WIDTH      = 2,    // Number of SDRAM Bank Address Pins (e.g., BA0, BA1 for 4 banks)
    parameter SDRAM_COL_WIDTH       = 9,    // Number of SDRAM Column Address Pins (e.g., A0-A8)
    parameter SDRAM_ROW_WIDTH       = 13,   // Number of SDRAM Row Address Pins (e.g., A0-A12)

    // --- SDRAM Timing Parameters (in HCLK cycles, based on HCLK frequency) ---
    // Example values for a 100MHz HCLK and typical SDR SDRAM:
    parameter T_RCD_CYCLES          = 3,    // tRCD: Active to Read/Write delay
    parameter T_RP_CYCLES           = 3,    // tRP: Precharge command period
    parameter T_RAS_CYCLES          = 7,    // tRAS: Row Active time
    parameter T_WR_CYCLES           = 3,    // tWR: Write Recovery time
    parameter T_RFC_CYCLES          = 10,   // tRFC: Auto-Refresh Cycle time
    parameter T_MRD_CYCLES          = 2,    // tMRD: Load Mode Register to Active/Refresh/Read/Write delay
    parameter CAS_LATENCY_CYCLES    = 3,    // CAS Latency (CL) in clock cycles
    parameter INIT_POWER_UP_DELAY_CYCLES = 200000, // Initial power-up delay for init controller (e.g., 200us for 100MHz clock)
    parameter T_REFRESH_INTERVAL_CYCLES = 782 // Refresh interval for refresh controller (e.g., 7.8125us for 100MHz HCLK)

) (
    // --- System Interface ---
    input                           HCLK,       // System Clock
    input                           HRESETn,    // Active Low Reset (Synchronous to HCLK)

    // --- AHB-Lite Slave Interface (Connects to AHB-Lite Master) ---
    // HSEL removed from top-level port list
    input  [1:0]                    HTRANS,     // Transfer Type
    input  [ADDR_WIDTH-1:0]         HADDR,      // Address Bus
    input                           HWRITE,     // Write (1) / Read (0) Transfer
    input  [2:0]                    HSIZE,      // Transfer Size
    input  [2:0]                    HBURST,     // Burst Type and Length
    input  [DATA_WIDTH-1:0]         HWDATA,     // Write Data Bus
    output                          HREADYOUT,  // Ready Output (changed from output reg to output)
    output [DATA_WIDTH-1:0]         HRDATA,     // Read Data Bus (changed from output reg to output)
    output [1:0]                    HRESP,      // Transfer Response (changed from output reg to output)

    // --- SDRAM Physical Interface (Connects to SDRAM Chip) ---
    output                          sdram_cs_n,     // Chip Select (active low) (changed from output reg to output)
    output                          sdram_ras_n,    // Row Address Strobe (active low) (changed from output reg to output)
    output                          sdram_cas_n,    // Column Address Strobe (active low) (changed from output reg to output)
    output                          sdram_we_n,     // Write Enable (active low) (changed from output reg to output)
    output                          sdram_cke,      // Clock Enable (changed from output reg to output)
    output [SDRAM_ADDR_WIDTH-1:0]   sdram_addr,     // SDRAM Address Bus (changed from output reg to output)
    output [SDRAM_BANK_WIDTH-1:0]   sdram_ba,       // SDRAM Bank Address Bus (changed from output reg to output)
    output [(DQ_WIDTH/8)-1:0]       sdram_dqm,      // Data Mask (active high, one bit per byte) (changed from output reg to output)
    inout  [DQ_WIDTH-1:0]           SDRAM_DQ        // Bidirectional SDRAM Data Bus
);

    // --- Internal Wires for Module Interconnection ---

    // Wires between ahb_lite_interface and sdram_cmd_fsm
    wire [ADDR_WIDTH-1:0]   ahb_addr_to_fsm;
    wire                    ahb_write_to_fsm;
    wire [2:0]              ahb_size_to_fsm;
    wire [2:0]              ahb_burst_to_fsm;
    wire                    ahb_valid_to_fsm;
    wire [DATA_WIDTH-1:0]   ahb_wdata_to_fsm;
    wire                    ahb_wdata_valid_to_fsm;

    // sdram_rdata_from_fsm_unused removed as sdram_rdata_o is removed from FSM
    wire                    sdram_rdata_valid_from_fsm;
    wire                    sdram_ready_from_fsm;
    wire                    sdram_error_from_fsm;

    // Wires between sdram_refresh_controller and sdram_cmd_fsm
    wire                    refresh_req_to_fsm;

    // Wires between sdram_init_controller and sdram_cmd_fsm
    wire                    init_start_to_fsm;

    // Wires between sdram_cmd_fsm and data_path
    wire                    cmd_write_active_to_dp;
    wire                    cmd_read_active_to_dp;

    // Wires between data_path and ahb_lite_interface
    wire [DATA_WIDTH-1:0]   sdram_rdata_from_dp;
    wire                    sdram_rdata_valid_from_dp;

    // Wires between address_mapper and sdram_cmd_fsm
    wire [SDRAM_BANK_WIDTH-1:0] mapped_bank_addr;
    wire [SDRAM_ROW_WIDTH-1:0]  mapped_row_addr;
    wire [SDRAM_COL_WIDTH-1:0]  mapped_col_addr;

    // Internal wires to capture outputs from ahb_lite_interface instance
    wire ahb_hreadyout_w;
    wire [DATA_WIDTH-1:0] ahb_hrdata_w;
    wire [1:0] ahb_hresp_w;

    // Internal wires to capture outputs from sdram_cmd_fsm instance (for top-level SDRAM pins)
    wire sdram_cs_n_w;
    wire sdram_ras_n_w;
    wire sdram_cas_n_w;
    wire sdram_we_n_w;
    wire sdram_cke_w;
    wire [SDRAM_ADDR_WIDTH-1:0] sdram_addr_w;
    wire [SDRAM_BANK_WIDTH-1:0] sdram_ba_w;
    wire [(DQ_WIDTH/8)-1:0] sdram_dqm_w;


    // --- Module Instantiations ---

    // 1. AHB-Lite Interface Module
    ahb_lite_interface #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH)
        // W_FIFO_DEPTH and R_FIFO_DEPTH can be left at default or explicitly set
    ) ahb_if_inst (
        .HCLK               (HCLK),
        .HRESETn            (HRESETn),
        // .HSEL removed from instantiation
        .HTRANS             (HTRANS),
        .HADDR              (HADDR),
        .HWRITE             (HWRITE),
        .HSIZE              (HSIZE),
        .HBURST             (HBURST),
        .HWDATA             (HWDATA),
        .HREADYOUT          (ahb_hreadyout_w),        // Connect to internal wire
        .HRDATA             (ahb_hrdata_w),           // Connect to internal wire
        .HRESP              (ahb_hresp_w),            // Connect to internal wire

        .ahb_addr_o         (ahb_addr_to_fsm),
        .ahb_write_o        (ahb_write_to_fsm),
        .ahb_size_o         (ahb_size_to_fsm),
        .ahb_burst_o        (ahb_burst_to_fsm),
        .ahb_valid_o        (ahb_valid_to_fsm),
        .ahb_wdata_o        (ahb_wdata_to_fsm),
        .ahb_wdata_valid_o  (ahb_wdata_valid_to_fsm),

        .sdram_rdata_i      (sdram_rdata_from_dp),      // Read data from data_path
        .sdram_rdata_valid_i(sdram_rdata_valid_from_dp),// Read data valid from data_path
        .sdram_ready_i      (sdram_ready_from_fsm),     // Ready from FSM
        .sdram_error_i      (sdram_error_from_fsm)      // Error from FSM
    );

    // 2. Address Mapper Module
    address_mapper #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),
        .SDRAM_BANK_WIDTH   (SDRAM_BANK_WIDTH),
        .SDRAM_COL_WIDTH    (SDRAM_COL_WIDTH),
        .SDRAM_ROW_WIDTH    (SDRAM_ROW_WIDTH)
    ) addr_mapper_inst (
        .ahb_addr_i         (ahb_addr_to_fsm),          // Input from AHB-Lite interface
        .sdram_bank_addr_o  (mapped_bank_addr),         // To FSM
        .sdram_row_addr_o   (mapped_row_addr),          // To FSM
        .sdram_col_addr_o   (mapped_col_addr)           // To FSM
    );


    // 3. SDRAM Command FSM Module
    sdram_cmd_fsm #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),
        .SDRAM_ADDR_WIDTH   (SDRAM_ADDR_WIDTH),
        .SDRAM_BANK_WIDTH   (SDRAM_BANK_WIDTH),
        .SDRAM_COL_WIDTH    (SDRAM_COL_WIDTH),
        .SDRAM_ROW_WIDTH    (SDRAM_ROW_WIDTH),
        .T_RCD_CYCLES       (T_RCD_CYCLES),
        .T_RP_CYCLES        (T_RP_CYCLES),
        .T_RAS_CYCLES       (T_RAS_CYCLES),
        .T_WR_CYCLES        (T_WR_CYCLES),
        .T_RFC_CYCLES       (T_RFC_CYCLES),
        .T_MRD_CYCLES       (T_MRD_CYCLES),
        .CAS_LATENCY_CYCLES (CAS_LATENCY_CYCLES),
        .INIT_DELAY_CYCLES  (INIT_POWER_UP_DELAY_CYCLES) // FSM init delay parameter is now used for init_controller
    ) sdram_fsm_inst (
        .HCLK                   (HCLK),
        .HRESETn                (HRESETn),

        .ahb_addr_i             (ahb_addr_to_fsm), // Still pass full AHB address for latching
        .ahb_write_i            (ahb_write_to_fsm),
        .ahb_size_i             (ahb_size_to_fsm),
        .ahb_burst_i            (ahb_burst_to_fsm),
        .ahb_valid_i            (ahb_valid_to_fsm),
        .ahb_wdata_i            (ahb_wdata_to_fsm),
        .ahb_wdata_valid_i      (ahb_wdata_valid_to_fsm),

        .ahb_bank_addr_i        (mapped_bank_addr), // From address_mapper
        .ahb_row_addr_i         (mapped_row_addr),  // From address_mapper
        .ahb_col_addr_i         (mapped_col_addr),  // From address_mapper

        .refresh_req_i          (refresh_req_to_fsm),
        .init_start_i           (init_start_to_fsm), // From init_controller

        // Removed sdram_rdata_o from FSM instantiation
        .sdram_rdata_valid_o    (sdram_rdata_valid_from_fsm),// To ahb_lite_interface
        .sdram_ready_o          (sdram_ready_from_fsm),     // To ahb_lite_interface & refresh_controller & init_controller
        .sdram_error_o          (sdram_error_from_fsm),     // To ahb_lite_interface

        .cmd_write_active_o     (cmd_write_active_to_dp),   // To data_path
        .cmd_read_active_o      (cmd_read_active_to_dp),    // To data_path

        .sdram_cs_n_o           (sdram_cs_n_w),       // Connect to internal wire
        .sdram_ras_n_o          (sdram_ras_n_w),      // Connect to internal wire
        .sdram_cas_n_o          (sdram_cas_n_w),      // Connect to internal wire
        .sdram_we_n_o           (sdram_we_n_w),       // Connect to internal wire
        .sdram_cke_o            (sdram_cke_w),        // Connect to internal wire
        .sdram_addr_o           (sdram_addr_w),       // Connect to internal wire
        .sdram_ba_o             (sdram_ba_w),         // Connect to internal wire
        .sdram_dqm_o            (sdram_dqm_w)         // Connect to internal wire
    );

    // 4. SDRAM Refresh Controller Module
    sdram_refresh_controller #(
        .T_REFRESH_INTERVAL_CYCLES (T_REFRESH_INTERVAL_CYCLES)
    ) refresh_ctrl_inst (
        .HCLK               (HCLK),
        .HRESETn            (HRESETn),
        .sdram_ready_i      (sdram_ready_from_fsm), // Ready from FSM
        .refresh_req_o      (refresh_req_to_fsm)    // To FSM
    );

    // 5. SDRAM Initialization Controller Module
    sdram_init_controller #(
        .INIT_POWER_UP_DELAY_CYCLES (INIT_POWER_UP_DELAY_CYCLES)
    ) init_ctrl_inst (
        .HCLK               (HCLK),
        .HRESETn            (HRESETn),
        .sdram_ready_i      (sdram_ready_from_fsm), // Ready from FSM
        .init_start_o       (init_start_to_fsm)     // To FSM
    );

    // 6. Data Path Module
    data_path #(
        .DATA_WIDTH (DATA_WIDTH),
        .DQ_WIDTH   (DQ_WIDTH)
    ) dp_inst (
        .HCLK                   (HCLK),
        .HRESETn                (HRESETn),

        .ahb_wdata_i            (ahb_wdata_to_fsm),         // Write data from AHB interface
        .ahb_wdata_valid_i      (ahb_wdata_valid_to_fsm),   // Write data valid from AHB interface

        .cmd_write_active_i     (cmd_write_active_to_dp),   // Write active from FSM
        .cmd_read_active_i      (cmd_read_active_to_dp),    // Read active from FSM
        .sdram_rdata_valid_i    (sdram_rdata_valid_from_fsm),// Read data valid from FSM (after CAS latency)

        .sdram_rdata_o          (sdram_rdata_from_dp),      // Read data to AHB interface
        .sdram_rdata_valid_o    (sdram_rdata_valid_from_dp),// Read data valid to AHB interface

        .SDRAM_DQ               (SDRAM_DQ)                  // Bidirectional SDRAM Data Bus
    );

    // --- Connect Internal Wires to Top-Level AHB-Lite Outputs ---
    // These assignments resolve the Vivado synthesis error.
    assign HREADYOUT = ahb_hreadyout_w;
    assign HRDATA    = ahb_hrdata_w;
    assign HRESP     = ahb_hresp_w;

    // --- Connect Internal Wires to Top-Level SDRAM Physical Outputs ---
    // These assignments resolve the Vivado synthesis error.
    assign sdram_cs_n  = sdram_cs_n_w;
    assign sdram_ras_n = sdram_ras_n_w;
    assign sdram_cas_n = sdram_cas_n_w;
    assign sdram_we_n  = sdram_we_n_w;
    assign sdram_cke   = sdram_cke_w;
    assign sdram_addr  = sdram_addr_w;
    assign sdram_ba    = sdram_ba_w;
    assign sdram_dqm   = sdram_dqm_w;

endmodule