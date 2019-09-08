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
// Created on Wed Oct 24 01:09:27 2018

T80s T80s_inst
(
	.RESET_n(RESET_n) ,	// input  RESET_n
	.CLK(CLK) ,	// input  CLK
	.CEN(CEN) ,	// input  CEN
	.WAIT_n(WAIT_n) ,	// input  WAIT_n
	.INT_n(INT_n) ,	// input  INT_n
	.NMI_n(NMI_n) ,	// input  NMI_n
	.BUSRQ_n(BUSRQ_n) ,	// input  BUSRQ_n
	.M1_n(M1_n) ,	// output  M1_n
	.MREQ_n(MREQ_n) ,	// output  MREQ_n
	.IORQ_n(IORQ_n) ,	// output  IORQ_n
	.RD_n(RD_n) ,	// output  RD_n
	.WR_n(WR_n) ,	// output  WR_n
	.RFSH_n(RFSH_n) ,	// output  RFSH_n
	.HALT_n(HALT_n) ,	// output  HALT_n
	.BUSAK_n(BUSAK_n) ,	// output  BUSAK_n
	.OUT0(OUT0) ,	// input  OUT0
	.A(A) ,	// output [15:0] A
	.DI(DI) ,	// input [7:0] DI
	.DO(DO) 	// output [7:0] DO
);

defparam T80s_inst.Mode = 0;
defparam T80s_inst.T2Write = 1;
defparam T80s_inst.IOWait = 1;