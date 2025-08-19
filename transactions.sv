// transactions.sv

// AHB Transaction
class ahb_transaction extends uvm_sequence_item;
    `uvm_object_utils(ahb_transaction)

    rand bit [31:0] addr;
    rand bit [31:0] wdata;
    bit [31:0] rdata;
    rand bit is_write;
    
    rand bit [1:0] trans;
    rand bit [2:0] burst;
    rand bit [2:0] size;

    constraint c_simple {
        trans == 2'b10; // NONSEQ
        burst == 3'b000; // SINGLE
        size  == 3'b010; // 32-bit
    }

    function new(string name = "ahb_transaction");
        super.new(name);
    endfunction
endclass

// SDRAM Transaction
class sdram_transaction extends uvm_sequence_item;
    `uvm_object_utils(sdram_transaction)

    typedef enum { CMD_NOP, CMD_ACTIVE, CMD_READ, CMD_WRITE, CMD_PRECHARGE, CMD_REFRESH, CMD_LOAD_MODE } cmd_t;

    cmd_t command;
    bit [12:0] addr;
    bit [1:0]  ba;
    bit [31:0] data;

    function new(string name = "sdram_transaction");
        super.new(name);
    endfunction
endclass