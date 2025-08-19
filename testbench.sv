// testbench.sv
`include "uvm_macros.svh"
import uvm_pkg::*;
`include "ahb_if.sv"
`include "sdram_if.sv"
`include "test.sv"

module testbench;
    bit HCLK;
    bit HRESETn;
    ahb_if ahb_vif(HCLK, HRESETn);
    sdram_if sdram_vif(HCLK);
    wire [31:0] SDRAM_DQ_wire;

    // --- FINAL FIX: Override the long delay parameter for fast simulation ---
    sdram_controller_top #(
        .INIT_POWER_UP_DELAY_CYCLES(200) // Use 200 cycles instead of the default 200000
    ) dut (
        .HCLK(HCLK), .HRESETn(HRESETn), .HTRANS(ahb_vif.HTRANS), .HADDR(ahb_vif.HADDR),
        .HWRITE(ahb_vif.HWRITE), .HSIZE(ahb_vif.HSIZE), .HBURST(ahb_vif.HBURST),
        .HWDATA(ahb_vif.HWDATA), .HREADYOUT(ahb_vif.HREADYOUT), .HRDATA(ahb_vif.HRDATA),
        .HRESP(ahb_vif.HRESP), .sdram_cs_n(sdram_vif.cs_n), .sdram_ras_n(sdram_vif.ras_n),
        .sdram_cas_n(sdram_vif.cas_n), .sdram_we_n(sdram_vif.we_n), .sdram_cke(sdram_vif.cke),
        .sdram_addr(sdram_vif.addr), .sdram_ba(sdram_vif.ba), .sdram_dqm(sdram_vif.dqm),
        .SDRAM_DQ(SDRAM_DQ_wire)
    );

    assign SDRAM_DQ_wire = sdram_vif.dq_oe ? sdram_vif.dq_out : 'z;
    assign sdram_vif.dq_in = SDRAM_DQ_wire;

    initial begin HCLK = 0; forever #5 HCLK = ~HCLK; end
    initial begin HRESETn = 1'b0; #50ns; HRESETn = 1'b1; end

    initial begin
        uvm_config_db#(virtual ahb_if)::set(null, "uvm_test_top.m_env.m_ahb_agent*", "vif", ahb_vif);
        uvm_config_db#(virtual sdram_if)::set(null, "uvm_test_top.m_env.m_sdram_agent*", "vif", sdram_vif);
        run_test("single_write_read_test");
    end
  
   initial
        begin
          $dumpfile("dump.vcd");
          $dumpvars(0,testbench);
        end
endmodule