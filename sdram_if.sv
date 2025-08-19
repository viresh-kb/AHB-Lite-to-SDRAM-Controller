// sdram_if.sv
interface sdram_if (input bit clk);
    logic        cke;
    logic        cs_n;
    logic        ras_n;
    logic        cas_n;
    logic        we_n;
    logic [1:0]  ba;
    logic [12:0] addr;
    logic [3:0]  dqm;
    logic [31:0] dq_out;
    logic [31:0] dq_in;
    logic        dq_oe;

    // ADDED this clocking block for the monitor
    clocking monitor_cb @(posedge clk);
        input cke, cs_n, ras_n, cas_n, we_n, ba, addr, dqm, dq_in;
    endclocking

    // Modport for the monitor to observe all signals
    modport MONITOR (
        clocking monitor_cb // EXPORT the clocking block
    );

    // Modport for the reactive driver
    modport DRIVER (
        input clk, cke,
        output cs_n, ras_n, cas_n, we_n, ba, addr, dqm, dq_out, dq_oe
    );
endinterface