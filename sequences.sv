// sequences.sv
class single_write_read_seq extends uvm_sequence #(ahb_transaction);
    `uvm_object_utils(single_write_read_seq)

    function new(string name="single_write_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        ahb_transaction wr_req;
        ahb_transaction rd_req;

        `uvm_info(get_full_name(), "Starting single write/read sequence...", UVM_MEDIUM)

        // 1. Send a single write transaction
        `uvm_do_with(wr_req, {
            addr == 32'h0000_1000;
            wdata == 32'hDEADBEEF;
            is_write == 1;
        })

        // 2. Send a single read transaction to the same address
        // The get_response() is implicit in `uvm_do
        `uvm_do_with(rd_req, {
            addr == 32'h0000_1000;
            is_write == 0;
        })

        `uvm_info(get_full_name(), "Finished single write/read sequence.", UVM_MEDIUM)
    endtask
endclass