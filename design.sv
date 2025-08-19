// design.sv
// This file includes all DUT modules to ensure they are compiled together.

`include "address_mapper.v"
`include "data_path.v"
`include "sdram_init_controller.v"
`include "sdram_refresh_controller.v"
`include "ahb_lite_interface.v"
`include "sdram_cmd_fsm.v"
`include "sdram_controller_top.v"