// test.sv
`include "env.sv"
`include "sequences.sv" // Include the new sequences file

class base_test extends uvm_test;
    `uvm_component_utils(base_test)
    env m_env;
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_env = env::type_id::create("m_env", this);
    endfunction
    
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        // Wait for the DUT's internal initialization to complete.
        // A simple delay works for this test.
        #2000ns;
        phase.drop_objection(this);
    endtask
endclass

class single_write_read_test extends base_test;
    `uvm_component_utils(single_write_read_test)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction

    task run_phase(uvm_phase phase);
        single_write_read_seq seq; // Create a handle for the sequence
        phase.raise_objection(this);

        // First, wait for the DUT to initialize itself
        super.run_phase(phase); 
        
        `uvm_info(get_full_name(), "DUT initialization finished. Starting test sequence.", UVM_MEDIUM)

        // Create and start the sequence on the agent's sequencer
        seq = single_write_read_seq::type_id::create("seq");
        seq.start(m_env.m_ahb_agent.m_sequencer);

        #200ns; // Add a final delay to let scoreboard process the last transaction
        phase.drop_objection(this);
    endtask
endclass