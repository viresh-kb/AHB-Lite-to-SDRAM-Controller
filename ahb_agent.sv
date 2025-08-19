// ahb_agent.sv

// Sequencer
`include "transactions.sv"
typedef uvm_sequencer #(ahb_transaction) ahb_sequencer;

// Driver
class ahb_driver extends uvm_driver #(ahb_transaction);
    `uvm_component_utils(ahb_driver)
    virtual ahb_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "AHB VIF not found");
    endfunction

    virtual task run_phase(uvm_phase phase);
        vif.driver_cb.HTRANS <= 2'b00; // IDLE
        forever begin
            seq_item_port.get_next_item(req);
            
            @(vif.driver_cb);
            vif.driver_cb.HADDR  <= req.addr;
            vif.driver_cb.HWRITE <= req.is_write;
            vif.driver_cb.HTRANS <= req.trans;
            vif.driver_cb.HBURST <= req.burst;
            vif.driver_cb.HSIZE  <= req.size;
            if (req.is_write) begin
                vif.driver_cb.HWDATA <= req.wdata;
            end
            
            // Wait until transfer is accepted by DUT
            do @(vif.driver_cb); while (!vif.driver_cb.HREADYOUT);

            // Capture read data if it was a read
            if (!req.is_write) req.rdata = vif.driver_cb.HRDATA;
            
            // De-assert
            vif.driver_cb.HTRANS <= 2'b00; // IDLE
            seq_item_port.item_done();
        end
    endtask
endclass

// Monitor
class ahb_monitor extends uvm_monitor;
    `uvm_component_utils(ahb_monitor)
    virtual ahb_if vif;
    uvm_analysis_port #(ahb_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "AHB VIF not found");
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            ahb_transaction trans;
            @(vif.monitor_cb);
            // Detect start of a valid transfer
            if (vif.monitor_cb.HTRANS == 2'b10 || vif.monitor_cb.HTRANS == 2'b11) begin
                trans = ahb_transaction::type_id::create("trans");
                trans.addr = vif.monitor_cb.HADDR;
                trans.is_write = vif.monitor_cb.HWRITE;
                trans.burst = vif.monitor_cb.HBURST;
                trans.size = vif.monitor_cb.HSIZE;
                trans.trans = vif.monitor_cb.HTRANS;
                
                // Wait for DUT to be ready
                do @(vif.monitor_cb); while(!vif.monitor_cb.HREADYOUT);

                if (trans.is_write) trans.wdata = vif.monitor_cb.HWDATA;
                else trans.rdata = vif.monitor_cb.HRDATA;

                `uvm_info("AHB_MONITOR", $sformatf("Observed AHB Transaction: %s", trans.sprint()), UVM_HIGH)
                ap.write(trans);
            end
        end
    endtask
endclass

// Agent
class ahb_agent extends uvm_agent;
    `uvm_component_utils(ahb_agent)
    ahb_driver m_driver;
    ahb_sequencer m_sequencer;
    ahb_monitor m_monitor;
    uvm_analysis_port #(ahb_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_monitor = ahb_monitor::type_id::create("m_monitor", this);
        if (get_is_active() == UVM_ACTIVE) begin
            m_driver = ahb_driver::type_id::create("m_driver", this);
            m_sequencer = ahb_sequencer::type_id::create("m_sequencer", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        if (get_is_active() == UVM_ACTIVE) begin
            m_driver.seq_item_port.connect(m_sequencer.seq_item_export);
        end
        m_monitor.ap.connect(this.ap);
    endfunction
endclass