// sdram_agent.sv

// Monitor
class sdram_monitor extends uvm_monitor;
    `uvm_component_utils(sdram_monitor)
    virtual sdram_if vif;
    uvm_analysis_port #(sdram_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual sdram_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "SDRAM VIF not found");
    endfunction

    task run_phase(uvm_phase phase);
        forever @(vif.monitor_cb) begin
            if (vif.monitor_cb.cke && !vif.monitor_cb.cs_n) begin
                sdram_transaction trans = sdram_transaction::type_id::create("trans");
                trans.ba = vif.monitor_cb.ba;
                trans.addr = vif.monitor_cb.addr;

                case ({vif.monitor_cb.ras_n, vif.monitor_cb.cas_n, vif.monitor_cb.we_n})
                    3'b000: trans.command = sdram_transaction::CMD_LOAD_MODE;
                    3'b001: trans.command = sdram_transaction::CMD_REFRESH;
                    3'b010: trans.command = sdram_transaction::CMD_PRECHARGE;
                    3'b011: trans.command = sdram_transaction::CMD_ACTIVE;
                    3'b100: trans.command = sdram_transaction::CMD_WRITE;
                    3'b101: trans.command = sdram_transaction::CMD_READ;
                    default: trans.command = sdram_transaction::CMD_NOP;
                endcase
                
                if (trans.command != sdram_transaction::CMD_NOP) begin
                   `uvm_info("SDRAM_MONITOR", $sformatf("Observed SDRAM Command: %s", trans.sprint()), UVM_HIGH)
                    ap.write(trans);
                end
            end
        end
    endtask
endclass

// Reactive Driver (Memory Model)
class sdram_driver extends uvm_driver #(sdram_transaction);
    `uvm_component_utils(sdram_driver)
    virtual sdram_if vif;
    localparam int CAS_LATENCY = 3;
    
    bit [31:0] memory [bit[1:0]][bit[12:0]][bit[8:0]];
    bit [12:0] active_row[bit[1:0]];
    sdram_transaction read_queue[$];

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual sdram_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "SDRAM VIF not found");
    endfunction

    task run_phase(uvm_phase phase);
      vif.dq_oe <= 1'b0;
      fork
        handle_commands();
        drive_read_data();
      join
    endtask

    task handle_commands();
        forever @(posedge vif.clk) begin
            if (vif.cke && !vif.cs_n) begin
                case ({vif.ras_n, vif.cas_n, vif.we_n})
                    3'b011: 
                        active_row[vif.ba] = vif.addr;
                    3'b100:
                        // --- THIS IS THE CORRECTED LINE ---
                        memory[vif.ba][active_row[vif.ba]][vif.addr[8:0]] = vif.dq_in;
                    3'b101: begin
                        sdram_transaction rd_trans = new;
                        rd_trans.data = memory[vif.ba][active_row[vif.ba]][vif.addr[8:0]];
                        read_queue.push_back(rd_trans);
                    end
                endcase
            end
        end
    endtask
    
    task drive_read_data();
        forever @(posedge vif.clk) begin
            vif.dq_oe <= 1'b0;
            if (read_queue.size() > 0) begin
                repeat(CAS_LATENCY-1) @(posedge vif.clk);
                vif.dq_oe <= 1'b1;
                vif.dq_out <= read_queue.pop_front().data;
                @(posedge vif.clk);
                vif.dq_oe <= 1'b0;
            end
        end
    endtask
endclass

// Agent
class sdram_agent extends uvm_agent;
    `uvm_component_utils(sdram_agent)
    sdram_monitor m_monitor;
    sdram_driver m_driver;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_monitor = sdram_monitor::type_id::create("m_monitor", this);
        m_driver = sdram_driver::type_id::create("m_driver", this);
    endfunction
endclass