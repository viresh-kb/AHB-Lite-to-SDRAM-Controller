`timescale 1ns / 1ps

// sdram_cmd_fsm_tb.v
// Testbench for the sdram_cmd_fsm module, Verilog-2001 compatible.

module sdram_cmd_fsm_tb;

    // --- Testbench Parameters (Override DUT parameters for faster simulation) ---
    // These localparams define the values that will be passed to the DUT's parameters.
    localparam ADDR_WIDTH_TB       = 32;
    localparam DATA_WIDTH_TB       = 32;
    localparam SDRAM_ADDR_WIDTH_TB = 13;
    localparam SDRAM_BANK_WIDTH_TB = 2; // For 4 banks
    localparam SDRAM_COL_WIDTH_TB  = 9;
    localparam SDRAM_ROW_WIDTH_TB  = 13;

    // Reduced Timing Parameters for Testbench (e.g., 10 cycles for RFC, 2-3 cycles for others)
    localparam T_RCD_CYCLES_TB       = 2;
    localparam T_RP_CYCLES_TB        = 2;
    localparam T_RAS_CYCLES_TB       = 5; // Must be >= tRCD + tWR (for write)
    localparam T_WR_CYCLES_TB        = 2;
    localparam T_RFC_CYCLES_TB       = 5; // Reduced for faster refresh test
    localparam T_MRD_CYCLES_TB       = 2;
    localparam CAS_LATENCY_CYCLES_TB = 2;
    // This parameter is NOT used by cmd_fsm, but kept for clarity in DUT instantiation.
    localparam INIT_DELAY_CYCLES_TB  = 1; 

    localparam HCLK_PERIOD = 10; // 10ns for 100MHz HCLK

    // --- Testbench Signals (declared as 'reg' for inputs, 'wire' for outputs) ---
    reg HCLK;
    reg HRESETn;

    // Inputs from AHB-Lite Interface
    reg [ADDR_WIDTH_TB-1:0] ahb_addr_i;
    reg ahb_write_i;
    reg [2:0] ahb_size_i;
    reg [2:0] ahb_burst_i;
    reg ahb_valid_i;
    reg [DATA_WIDTH_TB-1:0] ahb_wdata_i;
    reg ahb_wdata_valid_i;

    // Inputs from Address Mapper
    reg [SDRAM_BANK_WIDTH_TB-1:0] ahb_bank_addr_i;
    reg [SDRAM_ROW_WIDTH_TB-1:0]  ahb_row_addr_i;
    reg [SDRAM_COL_WIDTH_TB-1:0]  ahb_col_addr_i;

    // Inputs from Refresh Controller
    reg refresh_req_i;

    // Input from Init Controller
    reg init_start_i;

    // Outputs from DUT (declared as wire as they are driven by the DUT instance)
    wire sdram_rdata_valid_o;
    wire sdram_ready_o;
    wire sdram_error_o;
    wire cmd_write_active_o;
    wire cmd_read_active_o;
    wire sdram_cs_n_o;
    wire sdram_ras_n_o;
    wire sdram_cas_n_o;
    wire sdram_we_n_o;
    wire sdram_cke_o;
    wire [SDRAM_ADDR_WIDTH_TB-1:0] sdram_addr_o;
    wire [SDRAM_BANK_WIDTH_TB-1:0] sdram_ba_o;
    wire [(DATA_WIDTH_TB/8)-1:0] sdram_dqm_o;

    // Internal wires to observe FSM state (for debugging/verification)
    // Accessing internal signals of the DUT requires hierarchical referencing (dut.signal_name)
    // and declaring them as 'wire' in the testbench if they are 'reg' in the DUT.
    wire [4:0] current_state_i;
    wire [4:0] next_state_i;
    wire [31:0] timer_count_i;
    wire refresh_in_progress_i;
    wire ahb_request_pending_i;
    // For active_bank_state, we need to access individual elements or the whole array
    // Vivado might have issues with directly dumping `dut.active_bank_state` as an array.
    // Accessing individual elements is safer for older Verilog versions.
    wire [SDRAM_ROW_WIDTH_TB-1:0] active_bank_state_0_i;
    wire [SDRAM_ROW_WIDTH_TB-1:0] active_bank_state_1_i;
    wire [SDRAM_ROW_WIDTH_TB-1:0] active_bank_state_2_i;
    wire [SDRAM_ROW_WIDTH_TB-1:0] active_bank_state_3_i;


    // Instantiate the Unit Under Test (DUT)
    sdram_cmd_fsm #(
        .ADDR_WIDTH             (ADDR_WIDTH_TB),
        .DATA_WIDTH             (DATA_WIDTH_TB),
        .SDRAM_ADDR_WIDTH       (SDRAM_ADDR_WIDTH_TB),
        .SDRAM_BANK_WIDTH       (SDRAM_BANK_WIDTH_TB),
        .SDRAM_COL_WIDTH        (SDRAM_COL_WIDTH_TB),
        .SDRAM_ROW_WIDTH        (SDRAM_ROW_WIDTH_TB),
        .T_RCD_CYCLES           (T_RCD_CYCLES_TB),
        .T_RP_CYCLES            (T_RP_CYCLES_TB),
        .T_RAS_CYCLES           (T_RAS_CYCLES_TB),
        .T_WR_CYCLES            (T_WR_CYCLES_TB),
        .T_RFC_CYCLES           (T_RFC_CYCLES_TB),
        .T_MRD_CYCLES           (T_MRD_CYCLES_TB),
        .CAS_LATENCY_CYCLES     (CAS_LATENCY_CYCLES_TB),
        .INIT_DELAY_CYCLES      (INIT_DELAY_CYCLES_TB)
    ) dut (
        .HCLK                  (HCLK),
        .HRESETn               (HRESETn),

        .ahb_addr_i            (ahb_addr_i),
        .ahb_write_i           (ahb_write_i),
        .ahb_size_i            (ahb_size_i),
        .ahb_burst_i           (ahb_burst_i),
        .ahb_valid_i           (ahb_valid_i),
        .ahb_wdata_i           (ahb_wdata_i),
        .ahb_wdata_valid_i     (ahb_wdata_valid_i),

        .ahb_bank_addr_i       (ahb_bank_addr_i),
        .ahb_row_addr_i        (ahb_row_addr_i),
        .ahb_col_addr_i        (ahb_col_addr_i),

        .refresh_req_i         (refresh_req_i),
        .init_start_i          (init_start_i),

        .sdram_rdata_valid_o   (sdram_rdata_valid_o),
        .sdram_ready_o         (sdram_ready_o),
        .sdram_error_o         (sdram_error_o),
        .cmd_write_active_o    (cmd_write_active_o),
        .cmd_read_active_o     (cmd_read_active_o),
        .sdram_cs_n_o          (sdram_cs_n_o),
        .sdram_ras_n_o         (sdram_ras_n_o),
        .sdram_cas_n_o         (sdram_cas_n_o),
        .sdram_we_n_o          (sdram_we_n_o),
        .sdram_cke_o           (sdram_cke_o),
        .sdram_addr_o          (sdram_addr_o),
        .sdram_ba_o            (sdram_ba_o),
        .sdram_dqm_o           (sdram_dqm_o)
    );

    // Wires to probe internal signals (for enhanced debugging)
    assign current_state_i       = dut.current_state;
    assign next_state_i          = dut.next_state;
    assign timer_count_i         = dut.timer_count;
    assign refresh_in_progress_i = dut.refresh_in_progress;
    assign ahb_request_pending_i = dut.ahb_request_pending;
    assign active_bank_state_0_i = dut.active_bank_state[0];
    assign active_bank_state_1_i = dut.active_bank_state[1];
    assign active_bank_state_2_i = dut.active_bank_state[2];
    assign active_bank_state_3_i = dut.active_bank_state[3];


    // Clock Generation
    always #((HCLK_PERIOD / 2)) HCLK = ~HCLK;

    // Helper task for clock cycles
    // 'automatic' keyword is removed for Verilog-2001 compatibility
    task clock_cycles;
        input integer num_cycles;
        integer i; // 'integer' is standard Verilog-2001
        begin
            for (i = 0; i < num_cycles; i = i + 1) begin
                @(posedge HCLK);
            end
        end
    endtask

    // Helper task to check SDRAM command signals
    // 'string' and 'logic' replaced with 'integer' and 'reg'
    task check_sdram_cmd;
        input integer cmd_code; // Use an integer to identify the command
        input reg expected_cs_n;
        input reg expected_ras_n;
        input reg expected_cas_n;
        input reg expected_we_n;
        input reg [SDRAM_ADDR_WIDTH_TB-1:0] expected_addr;
        input reg [SDRAM_BANK_WIDTH_TB-1:0] expected_ba;
        begin
            @(posedge HCLK); // Wait for the next positive clock edge

            // You can use a case statement here if you want to print specific command names
            // based on cmd_code, but for simplicity, we'll just print the code.
            $display("Time %0t: Checking command (Code: %0d)", $time, cmd_code);
            $display("  Expected: CS_n=%b, RAS_n=%b, CAS_n=%b, WE_n=%b, ADDR=0x%h, BA=0x%h",
                     expected_cs_n, expected_ras_n, expected_cas_n, expected_we_n, expected_addr, expected_ba);
            $display("  Actual:   CS_n=%b, RAS_n=%b, CAS_n=%b, WE_n=%b, ADDR=0x%h, BA=0x%h",
                     sdram_cs_n_o, sdram_ras_n_o, sdram_cas_n_o, sdram_we_n_o, sdram_addr_o, sdram_ba_o);

            if (sdram_cs_n_o !== expected_cs_n ||
                sdram_ras_n_o !== expected_ras_n ||
                sdram_cas_n_o !== expected_cas_n ||
                sdram_we_n_o !== expected_we_n ||
                sdram_addr_o !== expected_addr ||
                sdram_ba_o !== expected_ba) begin
                $error("Time %0t: FAIL: Command %0d signals mismatch.", $time, cmd_code);
                $finish;
            end else begin
                $display("Time %0t: PASS: Command %0d signals correct.", $time, cmd_code);
            end
        end
    endtask

    // --- Test Sequence ---
    initial begin
        // Initialize all inputs
        HCLK = 1'b0;
        HRESETn = 1'b0; // Assert reset
        ahb_addr_i = {ADDR_WIDTH_TB{1'b0}};
        ahb_write_i = 1'b0;
        ahb_size_i = 3'b0;
        ahb_burst_i = 3'b0;
        ahb_valid_i = 1'b0;
        ahb_wdata_i = {DATA_WIDTH_TB{1'b0}};
        ahb_wdata_valid_i = 1'b0;
        ahb_bank_addr_i = {SDRAM_BANK_WIDTH_TB{1'b0}};
        ahb_row_addr_i = {SDRAM_ROW_WIDTH_TB{1'b0}};
        ahb_col_addr_i = {SDRAM_COL_WIDTH_TB{1'b0}};
        refresh_req_i = 1'b0;
        init_start_i = 1'b0;

        $display("--------------------------------------------------");
        $display("Starting SDRAM Command FSM Testbench (Verilog-2001)");
        $display("HCLK Period: %0d ns", HCLK_PERIOD);
        $display("Reduced Timing Parameters:");
        $display("  tRCD: %0d, tRP: %0d, tRAS: %0d, tWR: %0d, tRFC: %0d, tMRD: %0d, CL: %0d",
                 T_RCD_CYCLES_TB, T_RP_CYCLES_TB, T_RAS_CYCLES_TB, T_WR_CYCLES_TB, T_RFC_CYCLES_TB, T_MRD_CYCLES_TB, CAS_LATENCY_CYCLES_TB);
        $display("--------------------------------------------------");

        @(posedge HCLK);
        #1; // Small delay after clock edge to ensure stable values for reset
        HRESETn = 1'b1; // De-assert reset

        $display("\nTime %0t: HRESETn de-asserted. Expected S_IDLE (State 5).", $time);
        @(posedge HCLK);
        if (current_state_i !== 5'd5 /*S_IDLE*/) begin
            $error("Time %0t: FAIL: Did not enter S_IDLE after reset. Current state: %0d", $time, current_state_i);
            $finish;
        end
        if (sdram_ready_o !== 1'b1) begin
            $error("Time %0t: FAIL: sdram_ready_o not high in IDLE state.", $time);
            $finish;
        end
        $display("Time %0t: Current state: %0d (S_IDLE). sdram_ready_o = %b", $time, current_state_i, sdram_ready_o);

        // --- Test Scenario 1: Initialization Sequence ---
        $display("\n--- Test Scenario 1: Initialization Sequence ---");
        init_start_i = 1'b1; // Trigger initialization
        $display("Time %0t: init_start_i asserted.", $time);
        @(posedge HCLK);
        init_start_i = 1'b0; // De-assert init_start_i after one cycle

        $display("Time %0t: Entering S_INIT_PRECHARGE_ALL (State 1).", $time);
        // Command Code 1: PRECHARGE_ALL
        check_sdram_cmd(1, 1'b0, 1'b0, 1'b1, 1'b0, {SDRAM_ADDR_WIDTH_TB-1'd1,1'b0,1'b1}, {SDRAM_BANK_WIDTH_TB{1'b0}});
        clock_cycles(T_RP_CYCLES_TB);

        $display("Time %0t: Entering S_INIT_LOAD_MODE_REG (State 2).", $time);
        // Command Code 2: LOAD_MODE_REG
        check_sdram_cmd(2, 1'b0, 1'b0, 1'b0, 1'b0, dut.SDRAM_MODE_REG_VALUE, {SDRAM_BANK_WIDTH_TB{1'b0}});
        clock_cycles(T_MRD_CYCLES_TB);

        $display("Time %0t: Entering S_INIT_AUTO_REFRESH1 (State 3).", $time);
        // Command Code 3: AUTO_REFRESH1
        check_sdram_cmd(3, 1'b0, 1'b0, 1'b0, 1'b1, {SDRAM_ADDR_WIDTH_TB{1'b0}}, {SDRAM_BANK_WIDTH_TB{1'b0}});
        clock_cycles(T_RFC_CYCLES_TB);

        $display("Time %0t: Entering S_INIT_AUTO_REFRESH2 (State 4).", $time);
        // Command Code 4: AUTO_REFRESH2
        check_sdram_cmd(4, 1'b0, 1'b0, 1'b0, 1'b1, {SDRAM_ADDR_WIDTH_TB{1'b0}}, {SDRAM_BANK_WIDTH_TB{1'b0}});
        clock_cycles(T_RFC_CYCLES_TB);

        $display("Time %0t: Back to S_IDLE (State 5) after Initialization.", $time);
        if (current_state_i !== 5'd5 /*S_IDLE*/) begin
            $error("Time %0t: FAIL: Did not return to S_IDLE after initialization. Current state: %0d", $time, current_state_i);
            $finish;
        end
        if (sdram_ready_o !== 1'b1) begin
            $error("Time %0t: FAIL: sdram_ready_o not high after initialization.", $time);
            $finish;
        end
        $display("Time %0t: Current state: %0d (S_IDLE). sdram_ready_o = %b", $time, current_state_i, sdram_ready_o);


        // --- Test Scenario 2: Write Operation (Row Miss - Bank 0, Row 10, Col 5) ---
        $display("\n--- Test Scenario 2: Write Operation (Row Miss) ---");
        ahb_bank_addr_i = 2'd0;
        ahb_row_addr_i = 13'd10;
        ahb_col_addr_i = 9'd5;
        ahb_write_i = 1'b1; // Write request
        ahb_valid_i = 1'b1; // AHB request valid
        $display("Time %0t: AHB Write Request: Bank %0d, Row %0d, Col %0d", $time, ahb_bank_addr_i, ahb_row_addr_i, ahb_col_addr_i);
        @(posedge HCLK); // FSM latches request, moves from IDLE
        ahb_valid_i = 1'b0; // De-assert AHB valid after one cycle
        if (ahb_request_pending_i !== 1'b1) begin
            $error("Time %0t: FAIL: AHB request not pending.", $time);
            $finish;
        end
        $display("Time %0t: AHB request latched. current_state: %0d", $time, current_state_i);

        // Precharge Bank 0 (as active_bank_state[0] is not 13'd10, it's 0 by reset)
        $display("Time %0t: Entering S_PRECHARGE_BANK (State 9, Bank %0d).", $time, ahb_bank_addr_i);
        // Command Code 5: PRECHARGE_BANK
        check_sdram_cmd(5, 1'b0, 1'b0, 1'b1, 1'b0, {SDRAM_ADDR_WIDTH_TB-1'd1,1'b0,1'b0}, ahb_bank_addr_i);
        clock_cycles(T_RP_CYCLES_TB);

        // Activate Row
        $display("Time %0t: Entering S_ACTIVE (State 6, Bank %0d, Row %0d).", $time, ahb_bank_addr_i, ahb_row_addr_i);
        // Command Code 6: ACTIVE
        check_sdram_cmd(6, 1'b0, 1'b0, 1'b1, 1'b1, ahb_row_addr_i, ahb_bank_addr_i);
        clock_cycles(T_RCD_CYCLES_TB);

        // Write Command
        $display("Time %0t: Entering S_WRITE (State 8, Bank %0d, Col %0d).", $time, ahb_bank_addr_i, ahb_col_addr_i);
        // Command Code 7: WRITE
        check_sdram_cmd(7, 1'b0, 1'b1, 1'b0, 1'b0, ahb_col_addr_i, ahb_bank_addr_i);
        if (cmd_write_active_o !== 1'b1) begin
            $error("Time %0t: FAIL: cmd_write_active_o not asserted.", $time);
            $finish;
        end else begin
            $display("Time %0t: PASS: cmd_write_active_o asserted.", $time);
        end
        clock_cycles(T_WR_CYCLES_TB);
        $display("Time %0t: cmd_write_active_o = %b", $time, cmd_write_active_o); // Should be de-asserted by default

        $display("Time %0t: Back to S_IDLE (State 5) after Write.", $time);
        if (current_state_i !== 5'd5 /*S_IDLE*/) begin
            $error("Time %0t: FAIL: Did not return to S_IDLE after write operation. Current state: %0d", $time, current_state_i);
            $finish;
        end
        $display("Time %0t: active_bank_state[0] = %0d (expected %0d)", $time, active_bank_state_0_i, ahb_row_addr_i);
        if (active_bank_state_0_i !== ahb_row_addr_i) begin
            $error("Time %0t: FAIL: active_bank_state[0] not updated correctly after active command.", $time);
            $finish;
        end

        // --- Test Scenario 3: Read Operation (Row Hit - Bank 0, Row 10, Col 6) ---
        $display("\n--- Test Scenario 3: Read Operation (Row Hit) ---");
        ahb_bank_addr_i = 2'd0; // Same bank
        ahb_row_addr_i = 13'd10; // Same row (should be a hit)
        ahb_col_addr_i = 9'd6;
        ahb_write_i = 1'b0; // Read request
        ahb_valid_i = 1'b1;
        $display("Time %0t: AHB Read Request (Row Hit): Bank %0d, Row %0d, Col %0d", $time, ahb_bank_addr_i, ahb_row_addr_i, ahb_col_addr_i);
        @(posedge HCLK); // FSM latches request, should bypass precharge/active
        ahb_valid_i = 1'b0;
        $display("Time %0t: AHB request latched. current_state: %0d", $time, current_state_i);

        // Should go directly to S_READ
        $display("Time %0t: Entering S_READ (State 7, Bank %0d, Col %0d).", $time, ahb_bank_addr_i, ahb_col_addr_i);
        // Command Code 8: READ
        check_sdram_cmd(8, 1'b0, 1'b1, 1'b0, 1'b1, ahb_col_addr_i, ahb_bank_addr_i);
        if (cmd_read_active_o !== 1'b1) begin
            $error("Time %0t: FAIL: cmd_read_active_o not asserted.", $time);
            $finish;
        end else begin
            $display("Time %0t: PASS: cmd_read_active_o asserted.", $time);
        end
        
        clock_cycles(CAS_LATENCY_CYCLES_TB - 1); // Wait until 1 cycle before data valid
        $display("Time %0t: sdram_rdata_valid_o (before final cycle) = %b", $time, sdram_rdata_valid_o);
        if (sdram_rdata_valid_o !== 1'b0) begin
             $error("Time %0t: FAIL: sdram_rdata_valid_o asserted too early.", $time);
             $finish;
        end
        @(posedge HCLK); // Final cycle for CAS latency
        $display("Time %0t: sdram_rdata_valid_o (after CAS latency) = %b", $time, sdram_rdata_valid_o);
        if (sdram_rdata_valid_o !== 1'b1) begin
            $error("Time %0t: FAIL: sdram_rdata_valid_o not asserted after CAS latency.", $time);
            $finish;
        end else begin
            $display("Time %0t: PASS: sdram_rdata_valid_o asserted correctly.", $time);
        end
        $display("Time %0t: cmd_read_active_o = %b", $time, cmd_read_active_o); // Should be de-asserted by default
        
        @(posedge HCLK); // Move out of S_READ
        $display("Time %0t: Back to S_IDLE (State 5) after Read.", $time);
        if (current_state_i !== 5'd5 /*S_IDLE*/) begin
            $error("Time %0t: FAIL: Did not return to S_IDLE after read operation. Current state: %0d", $time, current_state_i);
            $finish;
        end

        // --- Test Scenario 4: Auto-Refresh Request ---
        $display("\n--- Test Scenario 4: Auto-Refresh Request ---");
        refresh_req_i = 1'b1;
        $display("Time %0t: refresh_req_i asserted.", $time);
        @(posedge HCLK);
        refresh_req_i = 1'b0; // De-assert after one cycle
        
        $display("Time %0t: Entering S_AUTO_REFRESH (State 10). refresh_in_progress = %b", $time, refresh_in_progress_i);
        if (refresh_in_progress_i !== 1'b1) begin
            $error("Time %0t: FAIL: refresh_in_progress not set.", $time);
            $finish;
        end
        if (sdram_ready_o !== 1'b0) begin
            $error("Time %0t: FAIL: sdram_ready_o not low during refresh.", $time);
            $finish;
        end else begin
            $display("Time %0t: PASS: sdram_ready_o correctly low during refresh.", $time);
        end
        // Command Code 9: AUTO_REFRESH
        check_sdram_cmd(9, 1'b0, 1'b0, 1'b0, 1'b1, {SDRAM_ADDR_WIDTH_TB{1'b0}}, {SDRAM_BANK_WIDTH_TB{1'b0}});
        clock_cycles(T_RFC_CYCLES_TB);

        $display("Time %0t: Back to S_IDLE (State 5) after Refresh. refresh_in_progress = %b", $time, refresh_in_progress_i);
        if (current_state_i !== 5'd5 /*S_IDLE*/) begin
            $error("Time %0t: FAIL: Did not return to S_IDLE after refresh. Current state: %0d", $time, current_state_i);
            $finish;
        end
        if (refresh_in_progress_i !== 1'b0) begin
            $error("Time %0t: FAIL: refresh_in_progress not cleared.", $time);
            $finish;
        end
        if (sdram_ready_o !== 1'b1) begin
            $error("Time %0t: FAIL: sdram_ready_o not high after refresh.", $time);
            $finish;
        end

        // --- Final checks and simulation end ---
        $display("\n--------------------------------------------------");
        $display("All test scenarios completed. Simulation Finishing.");
        $display("--------------------------------------------------");
        $finish; // End simulation
    end

    // Optional: Monitor signals for waveform viewing
    initial begin
        $dumpfile("sdram_cmd_fsm.vcd");
        // Dump all signals in the current scope
        $dumpvars(0, sdram_cmd_fsm_tb);
        // Dump internal signals of the DUT for better debugging
        $dumpvars(0, dut.current_state);
        $dumpvars(0, dut.next_state);
        $dumpvars(0, dut.timer_count);
        $dumpvars(0, dut.refresh_in_progress);
        $dumpvars(0, dut.ahb_request_pending);
        $dumpvars(0, dut.active_bank_state); // This might still be problematic for older Vivado versions.
                                             // If so, comment out and rely on individual bank probes.
        $dumpvars(0, dut.latched_ahb_write);
        $dumpvars(0, dut.latched_ahb_addr);
        $dumpvars(0, dut.latched_ahb_burst);
        $dumpvars(0, dut.latched_ahb_size);
    end

endmodule