// scoreboard.sv
class scoreboard extends uvm_scoreboard;
    `uvm_component_utils(scoreboard)

    uvm_analysis_imp #(ahb_transaction, scoreboard) ahb_imp;

    // --- THIS IS THE CORRECTED LINE ---
    // Making the key type explicit to help the simulator's elaborator.
    ahb_transaction expected_queue[bit [31:0]];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ahb_imp = new("ahb_imp", this);
    endfunction

    virtual function void write(ahb_transaction t);
        if (t.is_write) begin
            `uvm_info("SCOREBOARD", $sformatf("Got a WRITE. Storing Data=0x%h for Addr=0x%h", t.wdata, t.addr), UVM_MEDIUM)
            expected_queue[t.addr] = t;
        end else begin
            `uvm_info("SCOREBOARD", $sformatf("Got a READ from Addr=0x%h", t.addr), UVM_MEDIUM)
            if (expected_queue.exists(t.addr)) begin
                ahb_transaction expected_t = expected_queue[t.addr];
                if (expected_t.wdata == t.rdata) begin
                    `uvm_info("SCOREBOARD", $sformatf("PASS: Addr[0x%h] Read Data[0x%h] == Expected[0x%h]", t.addr, t.rdata, expected_t.wdata), UVM_LOW)
                end else begin
                    `uvm_error("SCOREBOARD", $sformatf("FAIL: Addr[0x%h] Read Data[0x%h] != Expected[0x%h]", t.addr, t.rdata, expected_t.wdata))
                end
                expected_queue.delete(t.addr); // Consume the expected transaction
            end else begin
                `uvm_warning("SCOREBOARD", $sformatf("Received a read from Addr=0x%h with no corresponding write.", t.addr))
            end
        end
    endfunction
endclass