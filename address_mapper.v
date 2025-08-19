`timescale 1ns / 1ps
// address_mapper.sv
// This module maps the linear AHB address into the SDRAM's
// bank, row, and column addresses.

module address_mapper #(
    parameter ADDR_WIDTH        = 32,   // AHB-Lite Address Width
    parameter DATA_WIDTH        = 32,   // AHB-Lite Data Width (e.g., 32-bit for AHB)
    parameter SDRAM_BANK_WIDTH  = 2,    // SDRAM Bank Address Pins
    parameter SDRAM_COL_WIDTH   = 9,    // SDRAM Column Address Pins
    parameter SDRAM_ROW_WIDTH   = 13    // SDRAM Row Address Pins
) (
    input  [ADDR_WIDTH-1:0]     ahb_addr_i,         // Input AHB-Lite address

    output [SDRAM_BANK_WIDTH-1:0] sdram_bank_addr_o,  // Output SDRAM Bank Address
    output [SDRAM_ROW_WIDTH-1:0]  sdram_row_addr_o,   // Output SDRAM Row Address
    output [SDRAM_COL_WIDTH-1:0]  sdram_col_addr_o    // Output SDRAM Column Address
);

    // Custom function to calculate ceiling of log2
    // This function is synthesizable when 'value' is a constant at elaboration time.
    function integer custom_clog2;
        input integer value;
        integer i;
        begin
            if (value == 0) begin
                custom_clog2 = 0; // Or handle as an error, depending on design intent
            end else begin
                custom_clog2 = 0;
                for (i = 0; (1 << i) < value; i = i + 1) begin
                    custom_clog2 = i + 1;
                end
                // If value is a perfect power of 2, the loop condition (1 << i) < value
                // will make 'i' one less than the actual log2, so we add 1.
                // For example, if value = 4 (100 in binary), i will be 1 (1 << 1 = 2 < 4),
                // then i becomes 2 (1 << 2 = 4 is NOT < 4), so loop stops.
                // custom_clog2 = 1+1 = 2. This is correct for clog2(4) = 2.
                // If value = 3, i will be 0 (1 << 0 = 1 < 3), custom_clog2 = 1.
                // then i becomes 1 (1 << 1 = 2 < 3), custom_clog2 = 2.
                // then i becomes 2 (1 << 2 = 4 is NOT < 3), so loop stops.
                // custom_clog2 = 2. This is correct for clog2(3) = 2.
            end
        end
    endfunction

    // Calculate the starting bit for column, row, and bank addresses using the custom function
    // This assumes a byte-addressable AHB bus, where the lowest 2 bits (for 32-bit data)
    // are byte offsets and are typically ignored for word/half-word accesses to memory devices.
    // So, the actual memory address bits start from AHB_ADDR[2].

    localparam COL_ADDR_LSB = custom_clog2(DATA_WIDTH/8); // LSB for column address (e.g., 2 for 32-bit data)
    localparam ROW_ADDR_LSB = COL_ADDR_LSB + SDRAM_COL_WIDTH;
    localparam BANK_ADDR_LSB = ROW_ADDR_LSB + SDRAM_ROW_WIDTH;

    // Continuous assignments to map the AHB address bits to SDRAM addresses
    // This mapping strategy is common, but MUST be verified against your
    // specific SDRAM device's datasheet and your overall memory map.
    // For example, some systems might interleave bank bits differently for performance.

    assign sdram_col_addr_o  = ahb_addr_i[COL_ADDR_LSB +: SDRAM_COL_WIDTH];
    assign sdram_row_addr_o  = ahb_addr_i[ROW_ADDR_LSB +: SDRAM_ROW_WIDTH];
    assign sdram_bank_addr_o = ahb_addr_i[BANK_ADDR_LSB +: SDRAM_BANK_WIDTH];

    // Important:
    // The AHB_ADDR_WIDTH should be large enough to cover the maximum addressable
    // range of the SDRAM based on its bank, row, and column widths.
    // Max SDRAM Addressable Bits = SDRAM_BANK_WIDTH + SDRAM_ROW_WIDTH + SDRAM_COL_WIDTH

    // Example:
    // If SDRAM_COL_WIDTH = 9, SDRAM_ROW_WIDTH = 13, SDRAM_BANK_WIDTH = 2
    // Total SDRAM address bits = 9 + 13 + 2 = 24 bits
    // AHB_ADDR_i[2+:9] (bits 2 to 10) for column
    // AHB_ADDR_i[11+:13] (bits 11 to 23) for row
    // AHB_ADDR_i[24+:2] (bits 24 to 25) for bank
    // So, AHB_ADDR_i[25:2] would be the relevant address range.
    // ADDR_WIDTH should be at least (BANK_ADDR_LSB + SDRAM_BANK_WIDTH)
    // In this example, 26 bits. If ADDR_WIDTH is 32, the higher bits are unused.

endmodule
