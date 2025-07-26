module AHB_slave (
    input         HRESETn,
    input         HCLK,
    input  [7:0]  HADDR,
    input  [1:0]  HTRANS,
    input         HWRITE,
    input  [2:0]  HSIZE,
    input  [2:0]  HBURST,
    input  [31:0] HWDATA,

    // Write FIFO
    output reg [40:0] DATA_to_WriteFIFO,
    output reg        WriteFIFO_wr_en,
    input             WriteFIFO_full,

    // Read FIFO
    input      [31:0] DATA_from_ReadFIFO,
    output reg        ReadFIFO_rd_en,
    input             ReadFIFO_empty,

    output reg [31:0] HRDATA,
    output wire       HRESP,   // Now a wire
    output            HREADY
);

localparam IDLE = 2'b00, BUSY = 2'b01, NON_SEQ = 2'b10, SEQ = 2'b11;
reg [1:0] state;
reg [31:0] fifo_data_fetch;
reg        fifo_rd_en_d;
reg        done; // Internal register to store response

// Data alignment function - returns 32 bit aligned data
function [31:0] align_data;
    input [31:0] HWDATA;
    input [2:0]  HSIZE;
    begin
        case (HSIZE)
            3'b000: align_data = {24'b0, HWDATA[7:0]};    // Byte
            3'b001: align_data = {16'b0, HWDATA[15:0]};   // Half-word
            3'b010: align_data = HWDATA;                  // Word
            default: align_data = 32'h0;
        endcase
    end
endfunction

assign HREADY = 1'b1;
assign HRESP = done; // Assign internal reg to wire

wire wr_en = (HWRITE == 1'b1) && (HREADY == 1'b1) && ((state == NON_SEQ) || (state == SEQ));
wire rd_en = (HWRITE == 1'b0) && (HREADY == 1'b1) && ((state == NON_SEQ) || (state == SEQ));

// State machine for AHB transfer
always @(posedge HCLK or negedge HRESETn) begin
    if (~HRESETn) begin
        state <= IDLE;
    end else begin
        case (state)
            IDLE: begin
                if (HTRANS == 2'b10)
                    state <= NON_SEQ;
                else
                    state <= IDLE;
            end
            NON_SEQ: begin
                case (HTRANS)
                    2'b11: state <= SEQ;
                    2'b01: state <= BUSY;
                    2'b00: state <= IDLE;
                    default: state <= NON_SEQ;
                endcase
            end
            SEQ: begin
                if (HTRANS == 2'b01)
                    state <= BUSY;
                else if (HTRANS == 2'b00)
                    state <= IDLE;
                else
                    state <= SEQ;
            end
            BUSY: begin
                if (HTRANS == 2'b11)
                    state <= SEQ;
                else
                    state <= BUSY;
            end
            default: state <= IDLE;
        endcase
    end
end

// FIFO interface and data latching logic
always @(posedge HCLK or negedge HRESETn) begin
    if (~HRESETn) begin
        DATA_to_WriteFIFO <= 41'h0;
        WriteFIFO_wr_en   <= 1'b0;
        ReadFIFO_rd_en    <= 1'b0;
        HRDATA            <= 32'h0;
        fifo_data_fetch   <= 32'h0;
        fifo_rd_en_d      <= 1'b0;
        done              <= 1'b0;
    end else begin
        WriteFIFO_wr_en <= 1'b0;
        ReadFIFO_rd_en  <= 1'b0;
        done            <= 1'b0; // Default to OKAY (0)

        if (wr_en) begin
            // Write operation - write aligned data to write FIFO if not full
            if (!WriteFIFO_full) begin
                DATA_to_WriteFIFO <= {1'b1, HADDR[0], HADDR[7:1], align_data(HWDATA, HSIZE)};
                WriteFIFO_wr_en <= 1'b1;
            end else begin
                done <= 1'b1; // ERROR - write FIFO full
            end
        end else if (rd_en) begin
            // Read operation - write read control to write FIFO and read from read FIFO if both FIFOs ready
            if (!WriteFIFO_full && !ReadFIFO_empty) begin
                DATA_to_WriteFIFO <= {1'b0, HADDR[0], HADDR[7:1], 32'b0};
                WriteFIFO_wr_en <= 1'b1;
                ReadFIFO_rd_en <= 1'b1;
                fifo_rd_en_d <= 1'b1; 
            end else begin
                done <= 1'b1; // ERROR - either write FIFO full or read FIFO empty
            end
        end

        // fetch data from ReadFIFO (one cycle after read enable)
        if (fifo_rd_en_d) begin
            fifo_data_fetch <= DATA_from_ReadFIFO;
        end

        // Output last read data
        HRDATA <= fifo_data_fetch;
        fifo_rd_en_d <= 1'b0;
    end
end

endmodule
