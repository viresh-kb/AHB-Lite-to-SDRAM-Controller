// ahb_if.sv
interface ahb_if (input bit HCLK, input bit HRESETn);
    logic [1:0]  HTRANS;
    logic [31:0] HADDR;
    logic        HWRITE;
    logic [2:0]  HSIZE;
    logic [2:0]  HBURST;
    logic [31:0] HWDATA;
    logic        HREADYOUT;
    logic [31:0] HRDATA;
    logic [1:0]  HRESP;

    clocking driver_cb @(posedge HCLK);
        output HTRANS, HADDR, HWRITE, HSIZE, HBURST, HWDATA;
        input HREADYOUT, HRDATA, HRESP;
    endclocking

    clocking monitor_cb @(posedge HCLK);
        input HTRANS, HADDR, HWRITE, HSIZE, HBURST, HWDATA, HREADYOUT, HRDATA, HRESP;
    endclocking

    modport DRIVER (clocking driver_cb, input HRESETn);
    modport MONITOR (clocking monitor_cb, input HRESETn);
endinterface