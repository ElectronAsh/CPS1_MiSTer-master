// Copyright (C) 2017  Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions 
// and other software and tools, and its AMPP partner logic 
// functions, and any output files from any of the foregoing 
// (including device programming or simulation files), and any 
// associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License 
// Subscription Agreement, the Intel Quartus Prime License Agreement,
// the Intel MegaCore Function License Agreement, or other 
// applicable license agreement, including, without limitation, 
// that your use is for the sole purpose of programming logic 
// devices manufactured by Intel and sold by Intel or its 
// authorized distributors.  Please refer to the applicable 
// agreement for further details.


// Generated by Quartus Prime Version 17.0 (Build Build 595 04/25/2017)
// Created on Fri Nov 09 05:54:23 2018

dpram_2048x4 dpram_2048x4_inst
(
	.reset(reset_sig) ,	// input  reset_sig
	.clock(clock_sig) ,	// input  clock_sig
	.rden_a(rden_a_sig) ,	// input  rden_a_sig
	.address_a(address_a_sig) ,	// input [10:0] address_a_sig
	.q_a(q_a_sig) ,	// output [3:0] q_a_sig
	.wren_b(wren_b_sig) ,	// input  wren_b_sig
	.address_b(address_b_sig) ,	// input [10:0] address_b_sig
	.data_b(data_b_sig) ,	// input [3:0] data_b_sig
	.q_b(q_b_sig) 	// output [3:0] q_b_sig
);

defparam dpram_2048x4_inst.RAM_INIT_FILE = "j68_ram.mif";