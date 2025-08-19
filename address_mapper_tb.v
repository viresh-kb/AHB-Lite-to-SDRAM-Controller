`timescale 1ns / 1ps
// address_mapper_tb.sv
// Testbench for the address_mapper module.

module address_mapper_tb;

    // Parameters for the testbench - MUST match DUT parameters
    parameter ADDR_WIDTH_TB      = 32;
    parameter DATA_WIDTH_TB      = 32;
    parameter SDRAM_BANK_WIDTH_TB = 2;
    parameter SDRAM_COL_WIDTH_TB  = 9;
    parameter SDRAM_ROW_WIDTH_TB  = 13;

    // Declare signals for DUT inputs
    reg [ADDR_WIDTH_TB-1:0] ahb_addr_i;

    // Declare wires for DUT outputs
    wire [SDRAM_BANK_WIDTH_TB-1:0] sdram_bank_addr_o;
    wire [SDRAM_ROW_WIDTH_TB-1:0]  sdram_row_addr_o;
    wire [SDRAM_COL_WIDTH_TB-1:0]  sdram_col_addr_o;

    // Instantiate the Device Under Test (DUT)
    address_mapper #(
        .ADDR_WIDTH      (ADDR_WIDTH_TB),
        .DATA_WIDTH      (DATA_WIDTH_TB),
        .SDRAM_BANK_WIDTH(SDRAM_BANK_WIDTH_TB),
        .SDRAM_COL_WIDTH (SDRAM_COL_WIDTH_TB),
        .SDRAM_ROW_WIDTH (SDRAM_ROW_WIDTH_TB)
    ) dut (
        .ahb_addr_i       (ahb_addr_i),
        .sdram_bank_addr_o(sdram_bank_addr_o),
        .sdram_row_addr_o (sdram_row_addr_o),
        .sdram_col_addr_o (sdram_col_addr_o)
    );

    // Local parameters derived from DUT parameters for expected value calculation
    localparam COL_ADDR_LSB_TB  = $clog2(DATA_WIDTH_TB/8); // LSB for column address
    localparam ROW_ADDR_LSB_TB  = COL_ADDR_LSB_TB + SDRAM_COL_WIDTH_TB;
    localparam BANK_ADDR_LSB_TB = ROW_ADDR_LSB_TB + SDRAM_ROW_WIDTH_TB;

    // Test sequence
    initial begin
        $display("-----------------------------------------------------");
        $display("Starting Address Mapper Testbench");
        $display("ADDR_WIDTH: %0d, DATA_WIDTH: %0d", ADDR_WIDTH_TB, DATA_WIDTH_TB);
        $display("SDRAM_BANK_WIDTH: %0d, SDRAM_COL_WIDTH: %0d, SDRAM_ROW_WIDTH: %0d",
                 SDRAM_BANK_WIDTH_TB, SDRAM_COL_WIDTH_TB, SDRAM_ROW_WIDTH_TB);
        $display("Calculated LSBs: COL=%0d, ROW=%0d, BANK=%0d",
                 COL_ADDR_LSB_TB, ROW_ADDR_LSB_TB, BANK_ADDR_LSB_TB);
        $display("-----------------------------------------------------");

        // Test Case 1: All zeros
        ahb_addr_i = {ADDR_WIDTH_TB{1'b0}};
        #1; // Allow combinational logic to propagate
        $display("Test AHB Addr: 0x%H", ahb_addr_i);
        $display("  DUT Outputs: Bank=0x%H, Row=0x%H, Col=0x%H",
                 sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
        $display("  Expected:    Bank=0x%H, Row=0x%H, Col=0x%H",
                 0, 0, 0);
        if (sdram_bank_addr_o == 0 && sdram_row_addr_o == 0 && sdram_col_addr_o == 0) begin
            $display("  --> PASS");
        end else begin
            $display("  --> FAIL");
            $error("Mismatch found for AHB address 0x%H", ahb_addr_i);
        end
        $display("-----------------------------------------------------");

        // Test Case 2: Simple address, all fields non-zero
        // AHB_ADDR = {BANK, ROW, COL, BYTE_OFFSET}
        // Example: Bank=1, Row=10, Col=5, Byte_Offset=0
        ahb_addr_i = (1 << BANK_ADDR_LSB_TB) | (10 << ROW_ADDR_LSB_TB) | (5 << COL_ADDR_LSB_TB);
        #1;
        $display("Test AHB Addr: 0x%H", ahb_addr_i);
        $display("  DUT Outputs: Bank=0x%H, Row=0x%H, Col=0x%H",
                 sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
        $display("  Expected:    Bank=0x%H, Row=0x%H, Col=0x%H",
                 1, 10, 5);
        if (sdram_bank_addr_o == 1 && sdram_row_addr_o == 10 && sdram_col_addr_o == 5) begin
            $display("  --> PASS");
        end else begin
            $display("  --> FAIL");
            $error("Mismatch found for AHB address 0x%H", ahb_addr_i);
        end
        $display("-----------------------------------------------------");

        // Test Case 3: Max values for each field
        ahb_addr_i = ({SDRAM_BANK_WIDTH_TB{1'b1}} << BANK_ADDR_LSB_TB) |
                     ({SDRAM_ROW_WIDTH_TB{1'b1}}  << ROW_ADDR_LSB_TB)  |
                     ({SDRAM_COL_WIDTH_TB{1'b1}}  << COL_ADDR_LSB_TB);
        #1;
        $display("Test AHB Addr: 0x%H", ahb_addr_i);
        $display("  DUT Outputs: Bank=0x%H, Row=0x%H, Col=0x%H",
                 sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
        $display("  Expected:    Bank=0x%H, Row=0x%H, Col=0x%H",
                 {SDRAM_BANK_WIDTH_TB{1'b1}}, {SDRAM_ROW_WIDTH_TB{1'b1}}, {SDRAM_COL_WIDTH_TB{1'b1}});
        if (sdram_bank_addr_o == {SDRAM_BANK_WIDTH_TB{1'b1}} &&
            sdram_row_addr_o  == {SDRAM_ROW_WIDTH_TB{1'b1}}  &&
            sdram_col_addr_o  == {SDRAM_COL_WIDTH_TB{1'b1}}) begin
            $display("  --> PASS");
        end else begin
            $display("  --> FAIL");
            $error("Mismatch found for AHB address 0x%H", ahb_addr_i);
        end
        $display("-----------------------------------------------------");

        // Test Case 4: Address with byte offset (should be ignored by mapping)
        ahb_addr_i = (2 << BANK_ADDR_LSB_TB) | (100 << ROW_ADDR_LSB_TB) | (20 << COL_ADDR_LSB_TB) | 3; // Byte offset 3
        #1;
        $display("Test AHB Addr: 0x%H", ahb_addr_i);
        $display("  DUT Outputs: Bank=0x%H, Row=0x%H, Col=0x%H",
                 sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
        $display("  Expected:    Bank=0x%H, Row=0x%H, Col=0x%H",
                 2, 100, 20);
        if (sdram_bank_addr_o == 2 && sdram_row_addr_o == 100 && sdram_col_addr_o == 20) begin
            $display("  --> PASS");
        end else begin
            $display("  --> FAIL");
            $error("Mismatch found for AHB address 0x%H", ahb_addr_i);
        end
        $display("-----------------------------------------------------");

        // Test Case 5: Address that primarily affects column, minimal other changes
        ahb_addr_i = (1 << COL_ADDR_LSB_TB); // Only column bit 0 set (after byte offset)
        #1;
        $display("Test AHB Addr: 0x%H", ahb_addr_i);
        $display("  DUT Outputs: Bank=0x%H, Row=0x%H, Col=0x%H",
                 sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
        $display("  Expected:    Bank=0x%H, Row=0x%H, Col=0x%H",
                 0, 0, 1);
        if (sdram_bank_addr_o == 0 && sdram_row_addr_o == 0 && sdram_col_addr_o == 1) begin
            $display("  --> PASS");
        end else begin
            $display("  --> FAIL");
            $error("Mismatch found for AHB address 0x%H", ahb_addr_i);
        end
        $display("-----------------------------------------------------");

        // Test Case 6: Address that primarily affects row, minimal other changes
        ahb_addr_i = (1 << ROW_ADDR_LSB_TB); // Only row bit 0 set
        #1;
        $display("Test AHB Addr: 0x%H", ahb_addr_i);
        $display("  DUT Outputs: Bank=0x%H, Row=0x%H, Col=0x%H",
                 sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
        $display("  Expected:    Bank=0x%H, Row=0x%H, Col=0x%H",
                 0, 1, 0);
        if (sdram_bank_addr_o == 0 && sdram_row_addr_o == 1 && sdram_col_addr_o == 0) begin
            $display("  --> PASS");
        end else begin
            $display("  --> FAIL");
            $error("Mismatch found for AHB address 0x%H", ahb_addr_i);
        end
        $display("-----------------------------------------------------");

        // Test Case 7: Address that primarily affects bank, minimal other changes
        ahb_addr_i = (1 << BANK_ADDR_LSB_TB); // Only bank bit 0 set
        #1;
        $display("Test AHB Addr: 0x%H", ahb_addr_i);
        $display("  DUT Outputs: Bank=0x%H, Row=0x%H, Col=0x%H",
                 sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
        $display("  Expected:    Bank=0x%H, Row=0x%H, Col=0x%H",
                 1, 0, 0);
        if (sdram_bank_addr_o == 1 && sdram_row_addr_o == 0 && sdram_col_addr_o == 0) begin
            $display("  --> PASS");
        end else begin
            $display("  --> FAIL");
            $error("Mismatch found for AHB address 0x%H", ahb_addr_i);
        end
        $display("-----------------------------------------------------");

        // Test Case 8: A more complex, arbitrary address
        // Example: AHB_ADDR = 0x0000_1234
        // Binary: 0000 0000 0000 0000 0001 0010 0011 0100
        // COL_ADDR_LSB = 2, SDRAM_COL_WIDTH = 9 -> bits [10:2]
        // ROW_ADDR_LSB = 11, SDRAM_ROW_WIDTH = 13 -> bits [23:11]
        // BANK_ADDR_LSB = 24, SDRAM_BANK_WIDTH = 2 -> bits [25:24]

        // For 0x0000_1234:
        // ahb_addr_i[10:2] = 010001101 (0x8D) -> Col = 141
        // ahb_addr_i[23:11] = 00000000010 (0x2) -> Row = 2
        // ahb_addr_i[25:24] = 00 (0x0) -> Bank = 0
        ahb_addr_i = 32'h00001234;
        #1;
        $display("Test AHB Addr: 0x%H", ahb_addr_i);
        $display("  DUT Outputs: Bank=0x%H, Row=0x%H, Col=0x%H",
                 sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
        $display("  Expected:    Bank=0x%H, Row=0x%H, Col=0x%H",
                 0, 2, 141);
        if (sdram_bank_addr_o == 0 && sdram_row_addr_o == 2 && sdram_col_addr_o == 141) begin
            $display("  --> PASS");
        end else begin
            $display("  --> FAIL");
            $error("Mismatch found for AHB address 0x%H", ahb_addr_i);
        end
        $display("-----------------------------------------------------");

        $display("-----------------------------------------------------");
        $display("Testbench finished.");
        $finish; // End simulation
    end

    // Monitor signals (optional, but good for debugging)
    initial begin
        $monitor("Time: %0t | AHB_Addr: 0x%H | Bank: 0x%H | Row: 0x%H | Col: 0x%H",
                 $time, ahb_addr_i, sdram_bank_addr_o, sdram_row_addr_o, sdram_col_addr_o);
    end

endmodule