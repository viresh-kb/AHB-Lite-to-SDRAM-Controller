// env.sv
`include "ahb_agent.sv"
`include "sdram_agent.sv"
`include "scoreboard.sv"

class env extends uvm_env;
    `uvm_component_utils(env)
    ahb_agent m_ahb_agent;
    sdram_agent m_sdram_agent;
    scoreboard m_scoreboard;

    function new(string name, uvm_component parent); super.new(name,parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_ahb_agent = ahb_agent::type_id::create("m_ahb_agent", this);
        m_sdram_agent = sdram_agent::type_id::create("m_sdram_agent", this);
        m_scoreboard = scoreboard::type_id::create("m_scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        m_ahb_agent.ap.connect(m_scoreboard.ahb_imp);
    endfunction
endclass