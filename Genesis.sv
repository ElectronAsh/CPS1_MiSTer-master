//============================================================================
//  FPGAGen port to MiSTer
//  Copyright (c) 2017,2018 Sorgelig
//
//  YM2612 implementation by Jose Tejada Gomez. Twitter: @topapate
//  Original Genesis code: Copyright (c) 2010-2013 Gregory Estrade (greg@torlus.com) 
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,
	
	output [3:0]  sconf,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	input			PATT_CLK_IN,
	
	input  [11:0] PATT_X_IN,
	input  [11:0] PATT_Y_IN,
	
	input			  PATT_HS_IN,
	input			  PATT_VS_IN,
	input			  PATT_DE_IN,
	
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	
	input			  BTN_USER,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output signed [15:0] AUDIO_L,
	output signed [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
//assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VIDEO_ARX = status[9] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[9] ? 8'd9  : 8'd3;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;

`include "build_id.v"
localparam CONF_STR = {
	"Genesis;;",
	"-;",
	"F,BINGENMD ;",
	"-;",
	"O67,Region,JP,US,EU;",
	"O8,Auto Region,No,Yes;",
	"-;",
	"O9,Aspect ratio,4:3,16:9;",
	"O13,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O4,Swap joysticks,No,Yes;",
	"O5,6 buttons mode,No,Yes;",
	"-;",
	"R0,Reset;",
	"J1,A,B,C,Start,Mode,X,Y,Z;",
	"V,v1.51.",`BUILD_DATE
};


wire [31:0] status;
wire  [1:0] buttons;
wire [15:0] joystick_0;
wire [15:0] joystick_1;
wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;
wire  [7:0] ioctl_index;
reg         ioctl_wait;
wire        forced_scandoubler;
wire [10:0] ps2_key;

hps_io #(.STRLEN($size(CONF_STR)>>3), .PS2DIV(1000), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),

	.status(status),
	.status_in({status[31:8],region_req,status[5:0]}),
	.status_set(region_set),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.ps2_key(ps2_key)
);


///////////////////////////////////////////////////
wire clk_sys, clk_ram, locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_ram),
	.locked(locked)
);

///////////////////////////////////////////////////
wire [3:0] r, g, b;
wire vs,hs;
wire ce_pix;
wire hblank, vblank;
wire interlace;

assign DDRAM_CLK = clk_ram;


wire [12:0] audio_l, audio_r;

/*
wire reset = RESET | status[0] | buttons[1] | region_set;

genesis Genesis
(
	.RESET_N(~(reset|ioctl_download)),
	.MCLK(clk_sys),
	.RAMCLK(clk_ram),
	
	.EXPORT(|status[7:6]),
	.PAL(status[7]),

	.DAC_LDATA(audio_l),
	.DAC_RDATA(audio_r),

	.RED(r),
	.GREEN(g),
	.BLUE(b),
	.VS(vs),
	.HS(hs),
	.HBL(hblank),
	.VBL(vblank),
	.CE_PIX(ce_pix),
	.FIELD(VGA_F1),
	.INTERLACE(interlace),

	.PSG_ENABLE(1),
	.FM_ENABLE(1),
	.FM_LIMITER(1),

	.J3BUT(~status[5]),
	.JOY_1((status[4] ? joystick_1[11:0] : joystick_0[11:0])),
	.JOY_2((status[4] ? joystick_0[11:0] : joystick_1[11:0])),

	.MAPPER_A(mapper_a),
	.MAPPER_WE(mapper_we),
	.MAPPER_D(mapper_d),

	.ROM_ADDR(rom_addr),
	.ROM_DATA(rom_data),
	.ROM_REQ(rom_rd),
	.ROM_ACK(rom_rdack)
);

wire [2:0] scale = status[3:1];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

assign CLK_VIDEO = clk_ram;
assign VGA_SL = {~interlace,~interlace}&sl[1:0];

reg old_ce_pix;
always @(posedge CLK_VIDEO) old_ce_pix <= ce_pix;
*/


wire reset = RESET | status[0] | buttons[1] | !BTN_USER;

reg [19:0] CLK_DIV;
always @(posedge clk_sys) CLK_DIV <= CLK_DIV + 1;

/*
reg VBLANK_INT;
reg HBLANK_INT;
reg HSYNC_PULSE_1;
wire HSYNC_PULSE = (!HSYNC_PULSE_1 && CLK_DIV[11]);
always @(posedge clk_sys or posedge reset)
if (reset) begin
	VBLANK_INT <= 0;
	HSYNC_PULSE_1 <= 0;
end
else begin
	HSYNC_PULSE_1 <= CLK_DIV[11];
	
	if (HSYNC_PULSE) HBLANK_INT <= 1'b1;
	else if (TG68_FC==3'b111) HBLANK_INT <= 1'b0;	// If the 68K services the Interrupt, clear the HBLANK_INT flag.
	
	if (CLK_DIV==0) VBLANK_INT <= 1'b1;
	else if (TG68_FC==3'b111) VBLANK_INT <= 1'b0;	// If the 68K services the Interrupt, clear the VBLANK_INT flag.
	
	// CPS_A Register WRITES...
	if (CPS_A_OBJ_CS && !TG68_WR_N) 		CPS_A_OBJ_REG <= TG68_DO;
	if (CPS_A_SCR1_CS && !TG68_WR_N) 	CPS_A_SCR1_REG <= TG68_DO;
	if (CPS_A_SCR2_CS && !TG68_WR_N) 	CPS_A_SCR2_REG <= TG68_DO;
	if (CPS_A_SCR3_CS && !TG68_WR_N) 	CPS_A_SCR3_REG <= TG68_DO;
	if (CPS_A_RSCR_CS && !TG68_WR_N) 	CPS_A_RSCR_REG <= TG68_DO;
	if (CPS_A_PAL_CS && !TG68_WR_N) 		CPS_A_PAL_REG <= TG68_DO;
	if (CPS_A_SCR1_X_CS && !TG68_WR_N) 	CPS_A_SCR1_X_REG <= TG68_DO;
	if (CPS_A_SCR1_Y_CS && !TG68_WR_N) 	CPS_A_SCR1_Y_REG <= TG68_DO;
	if (CPS_A_SCR2_X_CS && !TG68_WR_N) 	CPS_A_SCR2_X_REG <= TG68_DO;
	if (CPS_A_SCR2_Y_CS && !TG68_WR_N) 	CPS_A_SCR2_Y_REG <= TG68_DO;
	if (CPS_A_SCR3_X_CS && !TG68_WR_N) 	CPS_A_SCR3_X_REG <= TG68_DO;
	if (CPS_A_SCR3_Y_CS && !TG68_WR_N) 	CPS_A_SCR3_Y_REG <= TG68_DO;
	if (CPS_A_STAR1_X_CS && !TG68_WR_N) CPS_A_STAR1_X_REG <= TG68_DO;
	if (CPS_A_STAR1_Y_CS && !TG68_WR_N) CPS_A_STAR1_Y_REG <= TG68_DO;
	if (CPS_A_STAR2_X_CS && !TG68_WR_N) CPS_A_STAR2_X_REG <= TG68_DO;
	if (CPS_A_STAR2_Y_CS && !TG68_WR_N) CPS_A_STAR2_Y_REG <= TG68_DO;
	if (CPS_A_RSCR_OFFS_CS && !TG68_WR_N) CPS_A_RSCR_OFFS_REG <= TG68_DO;
	if (CPS_A_vCONT_CS && !TG68_WR_N) 		CPS_A_vCONT_REG <= TG68_DO;

	// CPS_B Register WRITES...
	if (CPS_B_LAYERCON_CS && !TG68_WR_N) CPS_B_LAYERCON_REG <= TG68_DO;
	if (CPS_B_PRIMASK1_CS && !TG68_WR_N) CPS_B_PRIMASK1_REG <= TG68_DO;
	if (CPS_B_PRIMASK2_CS && !TG68_WR_N) CPS_B_PRIMASK2_REG <= TG68_DO;
	if (CPS_B_PRIMASK3_CS && !TG68_WR_N) CPS_B_PRIMASK3_REG <= TG68_DO;
	if (CPS_B_PRIMASK4_CS && !TG68_WR_N) CPS_B_PRIMASK4_REG <= TG68_DO;
	if (CPS_B_PALCONT_CS && !TG68_WR_N)  CPS_B_PALCONT_REG <= TG68_DO;
end
*/


/*
(*keep*) wire [1:0] J68_BYTE_ENA;
(*keep*) wire [31:0] J68_ADDR;

(*keep*) wire J68_RD_ENA;
(*keep*) wire J68_WR_ENA;

//(*keep*) wire J68_DTACK = !TG68_DTACK_N;
(*keep*) wire J68_DTACK = 1'b1;

//(*keep*) wire [15:0] TG68_DI;
(*keep*) wire [15:0] TG68_DO;

(*keep*) wire TG68_UDS_N = !J68_BYTE_ENA[1];
(*keep*) wire TG68_LDS_N = !J68_BYTE_ENA[0];

(*keep*) wire [31:1] TG68_ADDR_OUT = J68_ADDR[31:1];
(*keep*) wire [23:0] TG68_BYTE_ADDR = J68_ADDR[23:0];

(*keep*) wire [2:0] TG68_FC;

wire TG68_INT2_N = !HBLANK_INT;
wire TG68_INT1_N = !VBLANK_INT;
wire TG68_INT0_N = 1'b1;

wire [2:0] TG68_IPL = {TG68_INT2_N, TG68_INT1_N, TG68_INT0_N};

wire TG68_RD_N = !J68_RD_ENA;
wire TG68_WR_N = !J68_WR_ENA;

j68 j68_inst
(
	.rst( reset ) ,			// input  rst
	.clk( CLK_DIV[1] ) ,		// input  clk
	
	.rd_ena( J68_RD_ENA ) ,	// output  rd_ena
	.wr_ena( J68_WR_ENA ) ,	// output  wr_ena
	
	.data_ack( J68_DTACK ) ,	// input  data_ack
	
	.byte_ena( J68_BYTE_ENA ) ,// output [1:0] byte_ena
	.address( J68_ADDR ) ,		// output [31:0] address
	
	.rd_data( TG68_DI ) ,	// input [15:0] rd_data
	.wr_data( TG68_DO ) ,	// output [15:0] wr_data
	
	.fc( TG68_FC ) ,			// output [2:0] fc
	.ipl_n( TG68_IPL ) ,		// input [2:0] ipl_n
	
	.dbg_reg_addr(dbg_reg_addr) ,	// output [3:0] dbg_reg_addr
	.dbg_reg_wren(dbg_reg_wren) ,	// output [3:0] dbg_reg_wren
	.dbg_reg_data(dbg_reg_data) ,	// output [15:0] dbg_reg_data
	.dbg_sr_reg(dbg_sr_reg) ,		// output [15:0] dbg_sr_reg
	.dbg_pc_reg(dbg_pc_reg) ,		// output [31:0] dbg_pc_reg
	.dbg_usp_reg(dbg_usp_reg) ,	// output [31:0] dbg_usp_reg
	.dbg_ssp_reg(dbg_ssp_reg) ,	// output [31:0] dbg_ssp_reg
	.dbg_vbr_reg(dbg_vbr_reg) ,	// output [31:0] dbg_vbr_reg
	.dbg_cycles(dbg_cycles) ,		// output [31:0] dbg_cycles
	.dbg_ifetch(dbg_ifetch) ,		// output  dbg_ifetch
	.dbg_irq_lvl(dbg_irq_lvl) 		// output [2:0] dbg_irq_lvl
);
*/


// TG68_FC (Function Code)...
// 
// FC[2:0]
// 
// 0 = Not used.
// 1 = User data.
// 2 = User program.
// 3 = Not used.
// 4 = Not used.
// 5 = Supervisor data.
// 6 = Supervisor program.
// 7 = Interrupt Acknowledge.


//wire [15:0] TG68_DI;
wire [2:0] TG68_IPL_N;
wire TG68_DTACK_N;
wire [31:0] TG68_A;
//wire [15:0] TG68_DO;
wire TG68_AS_N;
wire TG68_UDS_N;
wire TG68_LDS_N;
wire TG68_RNW;
wire TG68_INTACK;
wire [1:0] TG68_STATE;
(*keep*) wire [2:0] TG68_FC;
wire TG68_ENA;
wire [1:0] TG68_ENA_DIV;
wire TG68_ENARDREG;
wire TG68_ENAWRREG;

/*
TG68KdotC_Kernel TG68KdotC_Kernel_inst
(
	.clk( CLK_DIV[3] ) ,			// input  clk
	
	.nReset( !reset ) ,			// input  nReset
	
	.clkena_in( 1'b1 ) ,			// input  clkena_in
	.data_in( TG68_DI ) ,		// input [15:0] data_in
	
	.IPL( TG68_IPL ) ,			// input [2:0] IPL
	.IPL_autovector( 1'b1 ) ,	// input  IPL_autovector
	
	.berr( 1'b0 ) ,				// input  berr
	.CPU( 2'd0 ) ,					// input [1:0] CPU
	
	.addr( TG68_ADDR_OUT ) ,	// output [31:1] addr
	.data_write( TG68_DO ) ,	// output [15:0] data_write
	.nWr( TG68_WR_N ) ,			// output  nWr
	.nUDS( TG68_UDS_N ) ,		// output  nUDS
	.nLDS( TG68_LDS_N ) ,		// output  nLDS
	
	.busstate( TG68_BUSSTATE ) ,		// output [1:0] busstate
	.nResetOut( TG68_NRESET_OUT ) ,	// output  nResetOut
	.FC( TG68_FC ) ,						// output [2:0] FC
	.clr_berr( TG68_CLR_BERR ) ,		// output  clr_berr
	.skipFetch( TG68_SKIPFETCH ) ,	// output  skipFetch
	.regin( TG68_REGIN ) ,				// output [31:0] regin
	.CACR_out( TG68_CACR_OUT ) ,		// output [3:0] CACR_out
	.VBR_out( TG68_VBR_OUT ) 			// output [31:0] VBR_out
);

wire TG68_INT2_N = !HBLANK_INT;
wire TG68_INT1_N = !VBLANK_INT;
wire TG68_INT0_N = 1'b1;

wire [2:0] TG68_IPL = {TG68_INT2_N, TG68_INT1_N, TG68_INT0_N};

wire [1:0] TG68_BUSSTATE;
wire TG68_NRESET_OUT;
wire TG68_CLR_BERR;
wire TG68_SKIPFETCH;
wire [31:0] TG68_REGIN;
wire [2:0] TG68_CACR_OUT;
wire [31:0] TG68_VBR_OUT;


(* keep = 1 *) wire [15:0] TG68_DO;
(* keep = 1 *) wire [31:1] TG68_ADDR_OUT;
(* keep = 1 *) wire [23:0] TG68_BYTE_ADDR = {TG68_ADDR_OUT[23:1], 1'b0};


cpu_rom_hi	cpu_rom_hi_inst (
	.clock ( clk_sys ),
	.address ( TG68_ADDR_OUT[17:1] ),
	.q ( ROM_HI_DO )
);
wire [7:0] ROM_HI_DO;


cpu_rom_lo	cpu_rom_lo_inst (
	.clock ( clk_sys ),
	.address ( TG68_ADDR_OUT[17:1] ),
	.q ( ROM_LO_DO )
);
wire [7:0] ROM_LO_DO;


cpu_ram	cpu_ram_inst (
	.clock ( clk_sys ),
	.address ( TG68_ADDR_OUT[15:1] ),
	
	.data ( TG68_DO ),
	.wren ( CPU_RAM_WREN ),
	.byteena( CPU_RAM_BE ),
	
	.q ( CPU_RAM_DO )
);
(*keep*) wire [15:0] CPU_RAM_DO;


(*keep*) wire CPU_RAM_WREN = CPU_RAM_CS && !TG68_WR_N;
(*keep*) wire [1:0] CPU_RAM_BE = {!TG68_UDS_N, !TG68_LDS_N};


(*keep*) reg [10:0] KEEP_REG;
always @(posedge clk_sys) begin
	KEEP_REG <= {CPU_ROM_CS, PLAYER_CS, SERV_CS, NOPR_CS, COINCTRL_CS, CPSA_CS, CPSB_CS, SOUNDCMD_CS, SOUNDFADE_CS, GFX_RAM_CS, CPU_RAM_CS};
end

(*keep*) wire CPU_ROM_CS	= (TG68_BYTE_ADDR>=24'h000000 && TG68_BYTE_ADDR<=24'h3FFFFF);
(*keep*) wire PLAYER_CS		= (TG68_BYTE_ADDR>=24'h800000 && TG68_BYTE_ADDR<=24'h800007);
(*keep*) wire SERV_CS		= (TG68_BYTE_ADDR>=24'h800018 && TG68_BYTE_ADDR<=24'h800019);
(*keep*) wire DIPA_CS		= (TG68_BYTE_ADDR>=24'h80001A && TG68_BYTE_ADDR<=24'h80001B);
(*keep*) wire DIPB_CS		= (TG68_BYTE_ADDR>=24'h80001C && TG68_BYTE_ADDR<=24'h80001D);
(*keep*) wire DIPC_CS		= (TG68_BYTE_ADDR>=24'h80001E && TG68_BYTE_ADDR<=24'h80001F);
(*keep*) wire NOPR_CS		= (TG68_BYTE_ADDR>=24'h800020 && TG68_BYTE_ADDR<=24'h800021);
(*keep*) wire COINCTRL_CS	= (TG68_BYTE_ADDR>=24'h800030 && TG68_BYTE_ADDR<=24'h800037);
(*keep*) wire CPSA_CS		= (TG68_BYTE_ADDR>=24'h800100 && TG68_BYTE_ADDR<=24'h80013F);
(*keep*) wire CPSB_CS		= (TG68_BYTE_ADDR>=24'h800140 && TG68_BYTE_ADDR<=24'h80017F);
(*keep*) wire SOUNDCMD_CS	= (TG68_BYTE_ADDR>=24'h800180 && TG68_BYTE_ADDR<=24'h800187);
(*keep*) wire SOUNDFADE_CS	= (TG68_BYTE_ADDR>=24'h800188 && TG68_BYTE_ADDR<=24'h80018F);
(*keep*) wire GFX_RAM_CS	= (TG68_BYTE_ADDR>=24'h900000 && TG68_BYTE_ADDR<=24'h92FFFF);
(*keep*) wire CPU_RAM_CS 	= (TG68_BYTE_ADDR>=24'hFF0000 && TG68_BYTE_ADDR<=24'hFFFFFF);


// CPS-A Registers...
//
// All regs are write-only, apparently.
wire CPS_A_OBJ_CS = 			(TG68_BYTE_ADDR>=24'h800100 && TG68_BYTE_ADDR<=24'h800101);
wire CPS_A_SCR1_CS = 		(TG68_BYTE_ADDR>=24'h800102 && TG68_BYTE_ADDR<=24'h800103);
wire CPS_A_SCR2_CS = 		(TG68_BYTE_ADDR>=24'h800104 && TG68_BYTE_ADDR<=24'h800105);
wire CPS_A_SCR3_CS = 		(TG68_BYTE_ADDR>=24'h800106 && TG68_BYTE_ADDR<=24'h800107);
wire CPS_A_RSCR_CS =			(TG68_BYTE_ADDR>=24'h800108 && TG68_BYTE_ADDR<=24'h800109);
wire CPS_A_PAL_CS =			(TG68_BYTE_ADDR>=24'h80010a && TG68_BYTE_ADDR<=24'h80010b);
wire CPS_A_SCR1_X_CS =		(TG68_BYTE_ADDR>=24'h80010c && TG68_BYTE_ADDR<=24'h80010d);
wire CPS_A_SCR1_Y_CS =		(TG68_BYTE_ADDR>=24'h80010e && TG68_BYTE_ADDR<=24'h80010f);
wire CPS_A_SCR2_X_CS =		(TG68_BYTE_ADDR>=24'h800110 && TG68_BYTE_ADDR<=24'h800111);
wire CPS_A_SCR2_Y_CS =		(TG68_BYTE_ADDR>=24'h800112 && TG68_BYTE_ADDR<=24'h800113);
wire CPS_A_SCR3_X_CS =		(TG68_BYTE_ADDR>=24'h800114 && TG68_BYTE_ADDR<=24'h800115);
wire CPS_A_SCR3_Y_CS =		(TG68_BYTE_ADDR>=24'h800116 && TG68_BYTE_ADDR<=24'h800117);
wire CPS_A_STAR1_X_CS =		(TG68_BYTE_ADDR>=24'h800118 && TG68_BYTE_ADDR<=24'h800119);
wire CPS_A_STAR1_Y_CS =		(TG68_BYTE_ADDR>=24'h80011a && TG68_BYTE_ADDR<=24'h80011b);
wire CPS_A_STAR2_X_CS =		(TG68_BYTE_ADDR>=24'h80011c && TG68_BYTE_ADDR<=24'h80011d);
wire CPS_A_STAR2_Y_CS =		(TG68_BYTE_ADDR>=24'h80011e && TG68_BYTE_ADDR<=24'h80011f);
wire CPS_A_RSCR_OFFS_CS =	(TG68_BYTE_ADDR>=24'h800120 && TG68_BYTE_ADDR<=24'h800121);
wire CPS_A_vCONT_CS =		(TG68_BYTE_ADDR>=24'h800122 && TG68_BYTE_ADDR<=24'h800123);



reg [15:0] CPS_A_OBJ_REG;
reg [15:0] CPS_A_SCR1_REG;
reg [15:0] CPS_A_SCR2_REG;
reg [15:0] CPS_A_SCR3_REG;
reg [15:0] CPS_A_RSCR_REG;
reg [15:0] CPS_A_PAL_REG;
reg [15:0] CPS_A_SCR1_X_REG;
reg [15:0] CPS_A_SCR1_Y_REG;
reg [15:0] CPS_A_SCR2_X_REG;
reg [15:0] CPS_A_SCR2_Y_REG;
reg [15:0] CPS_A_SCR3_X_REG;
reg [15:0] CPS_A_SCR3_Y_REG;
reg [15:0] CPS_A_STAR1_X_REG;
reg [15:0] CPS_A_STAR1_Y_REG;
reg [15:0] CPS_A_STAR2_X_REG;
reg [15:0] CPS_A_STAR2_Y_REG;
reg [15:0] CPS_A_RSCR_OFFS_REG;
reg [15:0] CPS_A_vCONT_REG;


// CPS_B Registers...
//
// (example from Street Fighter 2, since each game has a different address map for the CPS-B regs).
wire CPS_B_LAYERCON_CS = (TG68_BYTE_ADDR>=24'h800166 && TG68_BYTE_ADDR<=24'h800167);
wire CPS_B_PRIMASK1_CS = (TG68_BYTE_ADDR>=24'h800168 && TG68_BYTE_ADDR<=24'h800169);
wire CPS_B_PRIMASK2_CS = (TG68_BYTE_ADDR>=24'h80016a && TG68_BYTE_ADDR<=24'h80016b);
wire CPS_B_PRIMASK3_CS = (TG68_BYTE_ADDR>=24'h80016c && TG68_BYTE_ADDR<=24'h80016d);
wire CPS_B_PRIMASK4_CS = (TG68_BYTE_ADDR>=24'h80016e && TG68_BYTE_ADDR<=24'h80016f);
wire CPS_B_PALCONT_CS  = (TG68_BYTE_ADDR>=24'h800170 && TG68_BYTE_ADDR<=24'h800171);

(*keep*) wire CPS_B_SF2_ID_CS = (TG68_BYTE_ADDR>=24'h800172 && TG68_BYTE_ADDR<=24'h800173);


reg [15:0] CPS_B_LAYERCON_REG;
reg [15:0] CPS_B_PRIMASK1_REG;
reg [15:0] CPS_B_PRIMASK2_REG;
reg [15:0] CPS_B_PRIMASK3_REG;
reg [15:0] CPS_B_PRIMASK4_REG;
reg [15:0] CPS_B_PALCONT_REG;





// Player controls are all active-HIGH here!...
wire P1_RIGHT	= 1'b0;
wire P1_LEFT	= 1'b0;
wire P1_DOWN	= 1'b0;
wire P1_UP		= 1'b0;
wire P1_BUT1	= 1'b0;
wire P1_BUT2	= 1'b0;
wire P1_BUT3	= 1'b0;
wire P1_UNK		= 1'b0;

wire P2_RIGHT	= 1'b0;
wire P2_LEFT	= 1'b0;
wire P2_DOWN	= 1'b0;
wire P2_UP		= 1'b0;
wire P2_BUT1	= 1'b0;
wire P2_BUT2	= 1'b0;
wire P2_BUT3	= 1'b0;
wire P2_UNK		= 1'b0;

wire [15:0] JOYSTICKS = ~{P2_UNK, P2_BUT3, P2_BUT2, P2_BUT1, P2_UP, P2_DOWN, P2_LEFT, P2_RIGHT,
								  P1_UNK, P1_BUT3, P1_BUT2, P1_BUT1, P1_UP, P1_DOWN, P1_LEFT, P1_RIGHT};


// Switches / DIP Switches are all active-HIGH here!...
wire COIN1	= 1'b0;
wire COIN2	= 1'b0;
wire SERV1	= 1'b0;
wire START1	= 1'b0;
wire START2	= 1'b0;
wire SERVSW	= 1'b0;
wire [7:0] SERV = ~{1'b0, SERVSW, START2, START1, 1'b0, SERV1, COIN2, COIN1};


// DIPSW A.
wire [2:0] COINAGE = 3'b000;	// 1 Coin/1 Credit.
wire COINSLOTS = 1'b0;			// 1 Coin Slot.
wire [7:0] DIPA = ~{COINAGE, COINSLOTS, 6'b000000};


// DIPSW B.
wire [2:0] DIFF = 3'b110;		// Normal.
wire [1:0] VS_MODE = 2'b00;	// 1 Game Match;
wire [7:0] DIPB = ~{DIFF, VS_MODE, 6'b000000};


// DIPSW C.
wire FREEZE = 1'b0;			// Definitely keep this OFF! lol
wire FLIP_SCREEN = 1'b0;
wire DEMO_SOUNDS = 1'b1;
wire GAME_MODE = 1'b0;		// 0=GAME. 1=TEST.
wire [7:0] DIPC = ~{3'b000, FREEZE, FLIP_SCREEN, DEMO_SOUNDS, 1'b0, GAME_MODE};



(* keep = 1 *) wire [15:0] ROM_DATA_FULL = {ROM_HI_DO, ROM_LO_DO};

(* keep = 1 *) wire [15:0] TG68_DI = (CPU_ROM_CS) ? ROM_DATA_FULL : 
												 (CPU_RAM_CS) ? CPU_RAM_DO :
												 
												 (PLAYER_CS) ? JOYSTICKS :
												 
												 (SERV_CS)  ? {SERV, 8'hFF} :	// Switches / DIP Switch bits are already active-LOW here,
												 (DIPA_CS)  ? {DIPA, 8'hFF} :	// and mapped to the upper bits of the 68K!
												 (DIPB_CS)  ? {DIPB, 8'hFF} :
												 (DIPC_CS)  ? {DIPC, 8'hFF} :
												 
												 (CPS_A_OBJ_CS) 		? CPS_A_OBJ_REG :			// Offset: 0x800100.
												 (CPS_A_SCR1_CS) 		? CPS_A_SCR1_REG :		// Offset: 0x800102.
												 (CPS_A_SCR2_CS) 		? CPS_A_SCR2_REG :		// Offset: 0x800104.
												 (CPS_A_SCR3_CS) 		? CPS_A_SCR3_REG :		// Offset: 0x800106.
												 (CPS_A_RSCR_CS) 		? CPS_A_RSCR_REG :		// Offset: 0x800108.
												 (CPS_A_PAL_CS) 		? CPS_A_PAL_REG :			// Offset: 0x80010A.
												 (CPS_A_SCR1_X_CS) 	? CPS_A_SCR1_X_REG :		// Offset: 0x80010C.
												 (CPS_A_SCR1_Y_CS) 	? CPS_A_SCR1_Y_REG :		// Offset: 0x80010E.
												 (CPS_A_SCR2_X_CS) 	? CPS_A_SCR2_X_REG :		// Offset: 0x800110.
												 (CPS_A_SCR2_Y_CS) 	? CPS_A_SCR2_Y_REG:		// Offset: 0x800112.
												 (CPS_A_SCR3_X_CS) 	? CPS_A_SCR3_X_REG :		// Offset: 0x800114.
												 (CPS_A_SCR3_Y_CS) 	? CPS_A_SCR3_Y_REG :		// Offset: 0x800116.
												 (CPS_A_STAR1_X_CS) 	? CPS_A_STAR1_X_REG :	// Offset: 0x800118.
												 (CPS_A_STAR1_Y_CS) 	? CPS_A_STAR1_Y_REG :	// Offset: 0x80011A.
												 (CPS_A_STAR2_X_CS) 	? CPS_A_STAR2_X_REG :	// Offset: 0x80011C.
												 (CPS_A_STAR2_Y_CS) 	? CPS_A_STAR2_Y_REG :	// Offset: 0x80011E.
												 (CPS_A_RSCR_OFFS_CS) ? CPS_A_RSCR_OFFS_REG :// Offset: 0x800120.
												 (CPS_A_vCONT_CS) 	? CPS_A_vCONT_REG :		// Offset: 0x800122.
												 
												 // CPS_B regs have different offsets for each game!
												 (CPS_B_LAYERCON_CS) ? CPS_B_LAYERCON_REG :
												 (CPS_B_PRIMASK1_CS) ? CPS_B_PRIMASK1_REG :
												 (CPS_B_PRIMASK2_CS) ? CPS_B_PRIMASK2_REG :
												 (CPS_B_PRIMASK3_CS) ? CPS_B_PRIMASK3_REG :
												 (CPS_B_PRIMASK4_CS) ? CPS_B_PRIMASK4_REG :
												 (CPS_B_PALCONT_CS)  ? CPS_B_PALCONT_REG :
												 
												 (CPS_B_SF2_ID_CS)	? 16'h0401 :
												 
												 (GFX_RAM_CS) ? GFX_RAM_DO :
																	 16'hzzzz;

gfx_ram	gfx_ram_inst (
	.clock ( clk_sys ),
	.address ( TG68_ADDR_OUT[17:1] ),
	
	.data ( TG68_DO ),
	.wren ( GFX_RAM_WREN ),
	.byteena( GFX_RAM_BE ),
	
	.q ( GFX_RAM_DO )
);
(* keep = 1 *) wire [15:0] GFX_RAM_DO;

(* keep = 1 *) wire GFX_RAM_WREN = GFX_RAM_CS && !TG68_WR_N;
(* keep = 1 *) wire [1:0] GFX_RAM_BE = {!TG68_UDS_N, !TG68_LDS_N};




wire [23:0] osd_rgb_out;
wire [1:0] cable_type;
wire osd_enable;
wire cont_disable;

wire [1:0] lr_filter;
wire [1:0] hr_filter;
wire [3:0] scanline_mode;

wire [7:0] osd_ctrl;
wire osdframe;

my_osd my_osd_inst
(
	.reset_n( !reset ) ,			// input  reset_n (active LOW).
	
	.pix_clk( PATT_CLK_IN ) ,	// input  pixel clk 
	.sys_clk( clk_sys ) ,		// input  system clk

	.hsync( PATT_HS_IN ) ,		// input  hsync (active HIGH!)
	.vsync( PATT_VS_IN ) ,		// input  vsync (active HIGH!)
	
	.rgb_in( 24'h000000 ) ,		// input [23:0] rgb_in.
	.rgb_out( osd_rgb_out ) ,	// output [23:0] rgb_out.

	.osd_ctrl( osd_ctrl ) ,		// input [7:0] osd_ctrl
	
	._scs( OSD_CS_N ) ,			// input  _scs		// ESP8266, pin "GPIO 16" (SPI /Chip Select for the OSD module)
	.sdo( OSD_MISO ) ,			// inout  sdo		// ESP8266, pin "GPIO 12" (ESP MISO. ie. Data IN to the ESP!)
	
	.sdi( SPARE ) ,				// input  sdi		// ESP8266, pin "GPIO 13" (ESP MOSI. ie. Data OUT of the ESP!)
										// Had to change to the SPARE pin, as the OSD_MOSI pin (13) on the Cyc III got zapped. :(
										// Must be the ground-loop thing between the PC and board. Need series resistors on ALL SPI signals, and JTAG!!
	
	.sck( EEPROM_DAT ) ,			// input  sck		// ESP8266, pin "GPIO 14" (SCK. SPI Clock)
										// Had to change to the EEPROM_DAT pin, as the OSD_SCLK pin on the Cyc III ALSO got zapped. :(
	
	.horbeam( PATT_X_IN ) ,		// input [11:0] horbeam.
	.verbeam( PATT_Y_IN ) ,		// input [11:0] verbeam.
	
	.osdframe( osdframe ) ,		// output osdframe
	
	.scanline_mode( scanline_mode ) ,// output [3:0] scanline
	
	.cable_type( cable_type ) ,		// output [1:0] cable_type
	.osd_enable( osd_enable ) ,		// output  osd_enable
	.cont_disable( cont_disable ) ,	// output  cont_disable
	
	.lr_filter( lr_filter ) ,	// output [1:0] lr_filter
	.hr_filter( hr_filter )		// output [1:0] hr_filter
);


assign VGA_R = (PATT_DE_IN) ? osd_rgb_out[23:16] : 8'h00;
assign VGA_G = (PATT_DE_IN) ? osd_rgb_out[15:8] : 8'h00;
assign VGA_B = (PATT_DE_IN) ? osd_rgb_out[7:0] : 8'h00;

assign VGA_HS = !PATT_HS_IN;
assign VGA_VS = !PATT_VS_IN;
assign VGA_DE = PATT_DE_IN;
*/


// Z80

wire T80_RESET_N = !reset;
wire T80_CLKEN = 1'b1;
wire T80_WAIT_N = 1'b1;
wire T80_INT_N = JT51_IRQ_N;
wire T80_NMI_N = 1'b1;
wire T80_BUSRQ_N = 1'b1;

wire T80_M1_N;
wire T80_MREQ_N;
wire T80_IORQ_N;
wire T80_RD_N;
wire T80_WR_N;
wire T80_BUSAK_N;

wire [15:0] T80_ADDR;
wire [7:0] T80_DI;
wire [7:0] T80_DO;

T80s T80s_inst
(
	.RESET_n( T80_RESET_N ) ,	// input  RESET_n
	.CLK( CLK_DIV[3] ) ,			// input  CLK
	.CEN( T80_CLKEN ) ,			// input  CEN
	.WAIT_n( T80_WAIT_N ) ,		// input  WAIT_n
	.INT_n( T80_INT_N ) ,		// input  INT_n
	.NMI_n( T80_NMI_N ) ,		// input  NMI_n
	.BUSRQ_n( T80_BUSRQ_N ) ,	// input  BUSRQ_n
	.M1_n( T80_M1_N ) ,			// output  M1_n
	.MREQ_n( T80_MREQ_N ) ,		// output  MREQ_n
	.IORQ_n( T80_IORQ_N ) ,		// output  IORQ_n
	.RD_n( T80_RD_N ) ,			// output  RD_n
	.WR_n( T80_WR_N ) ,			// output  WR_n
//	.RFSH_n(RFSH_n) ,				// output  RFSH_n
//	.HALT_n(HALT_n) ,				// output  HALT_n
	.BUSAK_n( T80_BUSAK_N ) ,	// output  BUSAK_n
//	.OUT0(OUT0) ,					// input  OUT0
	.A( T80_ADDR ) ,				// output [15:0] A
	.DI( T80_DI ) ,				// input [7:0] DI
	.DO( T80_DO ) 					// output [7:0] DO
);


wire [15:0] Z80_ROM_ADDR = (Z80_BANK1_CS) ? {1'b1, Z80_BANK_REG, T80_ADDR[13:0]} :	// <- 0x8000 to 0xBFFF.
																						T80_ADDR[15:0];	// <- Just use the full T80_ADDR range for 0x0000 to 0x7FFF.

z80_rom	z80_rom_inst (
	.clock ( clk_sys ),
	.address ( Z80_ROM_ADDR ),
	.q ( Z80_ROM_DO )
);
wire [7:0] Z80_ROM_DO;


z80_ram	z80_ram_inst (
	.clock ( clk_sys ),
	.address ( T80_ADDR[10:0] ),
		
	.data ( Z80_RAM_DI ),
	.wren ( Z80_RAM_WE ),
	
	.q ( Z80_RAM_DO )
);
wire [7:0] Z80_RAM_DI = T80_DO;
wire [7:0] Z80_RAM_DO;

wire Z80_RAM_WE = Z80_RAM_CS && !T80_MREQ_N && !T80_WR_N;


wire Z80_ROM_CS  = (T80_ADDR>=16'h0000 && T80_ADDR<=16'h7FFF);
wire Z80_BANK1_CS= (T80_ADDR>=16'h8000 && T80_ADDR<=16'hBFFF);
wire Z80_RAM_CS  = (T80_ADDR>=16'hD000 && T80_ADDR<=16'hD7FF);

wire Z80_JT51_CS = (T80_ADDR>=16'hF000 && T80_ADDR<=16'hF001);
wire Z80_OKI_CS  = (T80_ADDR>=16'hF002 && T80_ADDR<=16'hF003);
wire Z80_BANK_CS = (T80_ADDR>=16'hF004 && T80_ADDR<=16'hF005);
wire Z80_SEL_CS  = (T80_ADDR>=16'hF006 && T80_ADDR<=16'hF007);
wire Z80_CMD_CS  = (T80_ADDR>=16'hF008 && T80_ADDR<=16'hF009);
wire Z80_FADE_CS = (T80_ADDR>=16'hF00A && T80_ADDR<=16'hF00B);


assign T80_DI = (Z80_ROM_CS)		? Z80_ROM_DO :
					 (Z80_BANK1_CS)	? Z80_ROM_DO :
					 (Z80_RAM_CS)		? Z80_RAM_DO :
					 (Z80_JT51_CS)		? JT51_DO : 
					 //(Z80_OKI_CS)	? PCM_DO :
					 (Z80_OKI_CS)		? 8'hF0 :
					 (Z80_CMD_CS)		? Z80_CMD_REG :
					 (Z80_FADE_CS)		? Z80_FADE_REG :
											  8'h00;


reg Z80_BANK_REG;


// 68K to Z80 command regs / latches...
reg [7:0] Z80_CMD_REG;
reg [7:0] Z80_FADE_REG;

reg PCM_SS_REG = 1;

reg [15:0] DELAY;
reg [3:0] CNT;
always @(posedge CLK_DIV[3] or posedge reset)
if (reset) begin
	Z80_CMD_REG <= 8'h00;
	Z80_FADE_REG <= 8'h00;
	DELAY <= 16'hFFFF;
	CNT <= 0;
	Z80_BANK_REG <= 1'b0;
end
else begin
	DELAY <= DELAY - 1;

//	if (SOUNDCMD_CS && !TG68_WR_N) Z80_CMD_REG <= TG68_DO;
//	if (SOUNDFADE_CS && !TG68_WR_N) Z80_FADE_REG <= TG68_DO;
//
	
	if (Z80_BANK_CS && !T80_WR_N) Z80_BANK_REG <= T80_DO[0];
	//if (Z80_SEL_CS && !T80_WR_N) PCM_SS_REG <= T80_DO[0];
	
	
	case (CNT)
	0: if (!DELAY) begin
		Z80_CMD_REG <= 8'hF0;	// Probably the "silence" / stop music command.
		CNT <= CNT + 1;
	end
	
	1: if (!DELAY) begin
		Z80_CMD_REG <= 8'hFF;
		CNT <= CNT + 1;
	end

	2: if (!DELAY) begin
		Z80_CMD_REG <= 8'hF7;	// Probably the "music select" command.
		CNT <= CNT + 1;
	end

	3: if (!DELAY) begin
		Z80_CMD_REG <= 8'hFF;
		CNT <= CNT + 1;
	end

	4: if (!DELAY) begin
		//Z80_CMD_REG <= 8'h01;	// Music selection. (SF2 - Ryu's theme).
		//Z80_CMD_REG <= 8'h04;	// Music selection. (SF2 - Ken's theme.
		//Z80_CMD_REG <= 8'h05;	// Music selection. (SF2 - Guile's theme).
		//Z80_CMD_REG <= 8'h06;	// Music selection. (SF2 - Chun-Li's theme).
		//Z80_CMD_REG <= 8'h07;	// Music selection. (SF2 - Zangief's theme).
		//Z80_CMD_REG <= 8'h08;	// Music selection. (SF2 - Dhalsim's theme).
		//Z80_CMD_REG <= 8'h09;	// Music selection. (SF2 - Balrog's theme).
		Z80_CMD_REG <= 8'h0A;	// Music selection. (SF2 - Vega's theme).
		//Z80_CMD_REG <= 8'h0E;	// Music selection. (SF2 - Character Select Menu song).
		//Z80_CMD_REG <= 8'h16;	// Music selection. (SF2 - Intro song).

		//Z80_CMD_REG <= 8'h0C;	// Music selection. (Ghouls - Level 1).
		//Z80_CMD_REG <= 8'h0D;	// Music selection. (Ghouls - Boss fight?).
		//Z80_CMD_REG <= 8'h0E;	// Music selection. (Ghouls - ).
		
		CNT <= CNT + 1;
	end

	5: if (!DELAY) begin
		Z80_CMD_REG <= 8'hFF;
		CNT <= CNT + 1;
	end

	default:;
	endcase
end

					 
wire JT51_CLK = CLK_DIV[3];
wire JT51_RsT = reset;
wire JT51_CS_N = !Z80_JT51_CS;
wire JT51_WR_N = !(Z80_JT51_CS && !T80_WR_N);
wire JT51_A0 = T80_ADDR[0];
wire [7:0] JT51_DI = T80_DO;
wire [7:0] JT51_DO;
wire JT51_CT1;
wire JT51_CT2;
wire JT51_IRQ_N;
wire JT51_P1;
wire JT51_SAMPLE;
wire signed [15:0] JT51_L;
wire signed [15:0] JT51_R;
wire signed [15:0] JT51_XLEFT;
wire signed [15:0] JT51_XRIGHT;
wire [15:0] JT51_DACLEFT;
wire [15:0] JT51_DACRIGHT;


jt51 jt51_inst
(
	.clk( JT51_CLK ) ,			// input  clk
	.rst( JT51_RsT ) ,			// input  rst
	
	.cs_n( JT51_CS_N ) ,			// input  cs_n
	.wr_n( JT51_WR_N ) ,			// input  wr_n
	.a0( JT51_A0 ) ,				// input  a0
	
	.d_in( JT51_DI ) ,			// input [7:0] d_in
	
	.d_out( JT51_DO ) ,			// output [7:0] d_out
	
	.ct1( JT51_CT1 ) ,			// output  ct1
	.ct2( JT51_CT2 ) ,			// output  ct2
	.irq_n( JT51_IRQ_N ) ,		// output  irq_n
	.p1( JT51_P1 ) ,				// output  p1
	
	.sample( JT51_SAMPLE ) ,	// output  sample
	
	.left( JT51_L ) ,			// output [15:0] left
	.right( JT51_R ) ,		// output [15:0] right
	.xleft( JT51_XLEFT ) ,		// output [15:0] xleft
	.xright( JT51_XRIGHT ) ,	// output [15:0] xright
	.dacleft( JT51_DACLEFT ) ,	// output [15:0] dacleft
	.dacright( JT51_DACRIGHT ) // output [15:0] dacright
);


wire PCM_RESET_N = !reset;
wire PCM_CLK = CLK_DIV[3];

wire [7:0] PCM_DI = T80_DO;
wire [7:0] PCM_DO;

wire PCM_CS_N = !Z80_OKI_CS;
wire PCM_RD_N = !(Z80_OKI_CS && !T80_RD_N);
wire PCM_WR_N = !(Z80_OKI_CS && !T80_WR_N);

wire PCM_SS = PCM_SS_REG;

wire [17:0] PCM_ROM_ADDR;
wire [7:0] PCM_ROM_DATA;

wire signed [21:0] PCM_SOUND_OUT;

wire signed [17:0] V1_SAMP_OUT;
wire signed [17:0] V2_SAMP_OUT;
wire signed [17:0] V3_SAMP_OUT;
wire signed [17:0] V4_SAMP_OUT;

wire signed [12:0] V1_SIGNAL;
wire signed [12:0] V2_SIGNAL;
wire signed [12:0] V3_SIGNAL;
wire signed [12:0] V4_SIGNAL;

msm6295 msm6295_inst
(
	.RESET_N( PCM_RESET_N ) ,		// input  RESET_N
	.CLK( PCM_CLK ) ,					// input  CLK
	
	.CPU_DI( PCM_DI ) ,				// input [7:0] CPU_DI
	
	.CPU_DO( PCM_DO ) ,				// output [7:0] CPU_DO
		
	.CS_N( PCM_CS_N ) ,				// input  CS_N
	.RD_N( PCM_RD_N ) ,				// input  RD_N
	.WR_N( PCM_WR_N ) ,				// input  WR_N
	
	.SS( PCM_SS ) ,					// input  SS
	
	.ROM_ADDR( PCM_ROM_ADDR ) ,	// output [17:0] ROM_ADDR
	.ROM_DATA( PCM_ROM_DATA ) ,	// input [7:0] ROM_DATA
	
	.SOUND_OUT( PCM_SOUND_OUT ) ,	// output [21:0] SOUND_OUT
	
//	.V1_STATE(V1_STATE) ,	// output [3:0] V1_STATE
//	.VOICE_SLOT(VOICE_SLOT) ,	// output [2:0] VOICE_SLOT
	
//	.V1_SA(V1_SA) ,			// output [17:0] V1_SA
//	.V1_EA(V1_EA) ,			// output [17:0] V1_EA
	
//	.V1_GATE(V1_GATE) ,		// output  V1_GATE
//	.V2_GATE(V2_GATE) ,		// output  V2_GATE
//	.V3_GATE(V3_GATE) ,		// output  V3_GATE
//	.V4_GATE(V4_GATE) ,		// output  V4_GATE
	
//	.WR_N_RISING(WR_N_RISING) ,	// output  WR_N_RISING
	
//	.WRITE_STATE(WRITE_STATE) ,	// output  WRITE_STATE
	
//	.CPU_DATA_DBG(CPU_DATA_DBG) ,	// output [7:0] CPU_DATA_DBG
	
//	.V1_NIB(V1_NIB) ,	// output [3:0] V1_NIB
//	.V2_NIB(V2_NIB) ,	// output [3:0] V2_NIB
//	.V3_NIB(V3_NIB) ,	// output [3:0] V3_NIB
//	.V4_NIB(V4_NIB) ,	// output [3:0] V4_NIB

	.V1_SAMP_OUT( V1_SAMP_OUT ) ,	// output [17:0] V1_SAMP_OUT
	.V2_SAMP_OUT( V2_SAMP_OUT ) ,	// output [17:0] V2_SAMP_OUT
	.V3_SAMP_OUT( V3_SAMP_OUT ) ,	// output [17:0] V3_SAMP_OUT
	.V4_SAMP_OUT( V4_SAMP_OUT ) ,	// output [17:0] V4_SAMP_OUT

	.V1_SIGNAL( V1_SIGNAL ) ,		// output [12:0] V1_SIGNAL
	.V2_SIGNAL( V2_SIGNAL ) ,		// output [12:0] V2_SIGNAL
	.V3_SIGNAL( V3_SIGNAL ) ,		// output [12:0] V3_SIGNAL
	.V4_SIGNAL( V4_SIGNAL ) ,		// output [12:0] V4_SIGNAL
	
	.SAMP_PULSE(SAMP_PULSE) 	// output  SAMP_PULSE

);

pcm_rom	pcm_rom_inst (
	.clock ( CLK_DIV[2] ),		// Need to run this at a faster clock multiple than the msm6295 atm. TODO - fix this! ElectronAsh.
	
	.address ( PCM_ROM_ADDR ),
	.q ( PCM_ROM_DATA )
);



assign AUDIO_S = 1;
assign AUDIO_MIX = 0;


wire signed [16:0] MIX_L = {JT51_XLEFT[15],  JT51_XLEFT}  + {PCM_SOUND_OUT[21], PCM_SOUND_OUT[21:5]};
//wire signed [16:0] MIX_L = PCM_SOUND_OUT[21:5];
wire signed [16:0] MIX_R = {JT51_XRIGHT[15], JT51_XRIGHT} + {PCM_SOUND_OUT[19],PCM_SOUND_OUT[19:4]};

assign AUDIO_L = MIX_L[16:1];
assign AUDIO_R = MIX_R[16:1];



assign sconf = status[11:10];

/*
video_mixer #(.LINE_LENGTH(320), .HALF_DEPTH(1)) video_mixer
(
    .clk_sys(CLK_VIDEO),
    .ce_pix(~old_ce_pix & ce_pix),
    .ce_pix_out(CE_PIXEL),

    .scanlines(0),
    .scandoubler(~interlace && (scale || forced_scandoubler)),
    .hq2x(scale==1),

    .mono(0),

    .R(r),
    .G(g),
    .B(b),

    // Positive pulses.
    .HSync(hs),
    .VSync(vs),
    .HBlank(hblank),
    .VBlank(vblank),
    
    .VGA_R( VGA_R ),
    .VGA_G( VGA_G ),
    .VGA_B( VGA_B ),
    .VGA_VS( VGA_VS ),
    .VGA_HS( VGA_HS ),
    .VGA_DE( VGA_DE )
);
*/


/*
compressor compressor
(
	clk_sys,
	audio_l[12:1], audio_r[12:1],
	AUDIO_L,       AUDIO_R
);
*/


///////////////////////////////////////////////////

wire [22:1] rom_addr;
wire [15:0] rom_data;
wire rom_rd, rom_rdack;

ddram ddram
(
	.*,

   .wraddr(ioctl_addr),
   .din({ioctl_data[7:0],ioctl_data[15:8]}),
   .we_req(rom_wr),
   .we_ack(rom_wrack),

   .rdaddr(use_map ? {map[rom_addr[21:19]], rom_addr[18:1]} : rom_addr),
   .dout(rom_data),
   .rd_req(rom_rd),
   .rd_ack(rom_rdack)
);

reg  rom_wr;
wire rom_wrack;

always @(posedge clk_sys) begin
	reg old_download, old_reset;
	old_download <= ioctl_download;
	old_reset <= reset;

	if(~old_reset && reset) ioctl_wait <= 0;
	if(~old_download && ioctl_download) rom_wr <= 0;
	else begin
		if(ioctl_wr) begin
			ioctl_wait <= 1;
			rom_wr <= ~rom_wr;
		end else if(ioctl_wait && (rom_wr == rom_wrack)) begin
			ioctl_wait <= 0;
		end
	end
end

wire [2:0] mapper_a;
wire [5:0] mapper_d;
wire       mapper_we;

reg  [5:0] map[8] = '{0,1,2,3,4,5,6,7};
reg        use_map = 0;

always @(posedge clk_sys) begin
	if(reset) begin
		map <= '{0,1,2,3,4,5,6,7};
		use_map <= 0;
	end
	else if (mapper_we && mapper_a) begin
		map[mapper_a] <= mapper_d;
		use_map <= 1;
	end
end

reg  [1:0] region_req;
reg        region_set = 0;

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state, old_download = 0;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		casex(code)
			'h005: begin region_req <= 0; region_set <= pressed; end // F1
			'h006: begin region_req <= 1; region_set <= pressed; end // F2
			'h004: begin region_req <= 2; region_set <= pressed; end // F3
		endcase
	end

	old_download <= ioctl_download;
	if(status[8] & (old_download ^ ioctl_download) & |ioctl_index) begin
		region_set <= ioctl_download;
		region_req <= ioctl_index[7:6];
	end
end


(*keep*)wire bus_eof;
(*keep*)wire [6:0] bus_vbl;
(*keep*)wire [8:0] bus_vpos;
(*keep*)wire bus_dma_ena;
(*keep*)wire bus_frd_ena;

(*keep*)wire vid_clk_ena;
(*keep*)wire vid_eol;
(*keep*)wire vid_eof;
(*keep*)wire [10:0] vid_hpos;
(*keep*)wire [10:0] vid_vpos;
(*keep*)wire vid_hsync;
(*keep*)wire vid_vsync;
(*keep*)wire vid_dena;

cps_video_beam cps_video_beam_inst
(
	.bus_rst( reset ) ,		// input  bus_rst
	.bus_clk( clk_sys ) ,	// input  bus_clk
	
	.ram_ref(ram_ref) ,		// input  ram_ref
	.ram_cyc(ram_cyc) ,		// input [3:0] ram_cyc
	.ram_acc(ram_acc) ,		// input [3:0] ram_acc
	.ram_slot(ram_slot) ,	// input [8:0] ram_slot
	
	.slot_rst(slot_rst) ,	// input  slot_rst
	
	.bus_eof(bus_eof) ,		// output  bus_eof
	.bus_vbl(bus_vbl) ,		// output [6:0] bus_vbl
	.bus_vpos(bus_vpos) ,	// output [8:0] bus_vpos
	.bus_dma_ena(bus_dma_ena) ,	// output  bus_dma_ena
	.bus_frd_ena(bus_frd_ena) ,	// output  bus_frd_ena
	
	.vid_rst( reset ) ,		// input  vid_rst
	.vid_clk( clk_sys ) ,		// input  vid_clk
	.vid_clk_ena(vid_clk_ena) ,	// output [2:0] vid_clk_ena
	.vid_eol(vid_eol) ,		// output  vid_eol
	.vid_eof(vid_eof) ,		// output  vid_eof
	.vid_hpos(vid_hpos) ,	// output [10:0] vid_hpos
	.vid_vpos(vid_vpos) ,	// output [10:0] vid_vpos
	.vid_hsync(vid_hsync) ,	// output  vid_hsync
	.vid_vsync(vid_vsync) ,	// output  vid_vsync
	.vid_dena(vid_dena) 		// output  vid_dena
);



wire ram_rdy_n;
wire ram_ref;
wire [3:0] ram_cyc;
wire [3:0] ram_acc;
wire [8:0] ram_slot;

wire slot_rst;

wire [15:0] rd_data;

wire rden_b0;
wire wren_b0;
wire [31:0] addr_b0;
wire valid_b0;
wire fetch_b0;
wire [1:0] wr_bena_b0;
wire [15:0] wr_data_b0;

wire rden_b1;
wire wren_b1;
wire [31:0] addr_b1;
wire valid_b1;
wire fetch_b1;
wire [1:0] wr_bena_b1;
wire [15:0] wr_data_b1;

wire rden_b2;
wire wren_b2;
wire [31:0] addr_b2;
wire valid_b2;
wire fetch_b2;
wire [1:0] wr_bena_b2;
wire [15:0] wr_data_b2;

wire rden_b3;
wire wren_b3;
wire [31:0] addr_b3;
wire valid_b3;
wire fetch_b3;
wire [1:0] wr_bena_b3;
wire [15:0] wr_data_b3;

sdram_ctrl_16b sdram_ctrl_16b_inst
(
	.rst( reset ) ,			// input  rst
	.clk( clk_sys ) ,			// input  clk
	
	.ram_rdy_n(ram_rdy_n) ,	// output  ram_rdy_n
	.ram_ref(ram_ref) ,		// output  ram_ref
	.ram_cyc(ram_cyc) ,		// output [3:0] ram_cyc
	.ram_acc(ram_acc) ,		// output [3:0] ram_acc
	.ram_slot(ram_slot) ,	// output [8:0] ram_slot
	
	.slot_rst(slot_rst) ,	// output  slot_rst
	
	.rd_data(rd_data) ,	// output [15:0] rd_data
	
	.rden_b0(rden_b0) ,	// input  rden_b0
	.wren_b0(wren_b0) ,	// input  wren_b0
	.addr_b0(addr_b0) ,	// input [31:0] addr_b0
	.valid_b0(valid_b0) ,	// output  valid_b0
	.fetch_b0(fetch_b0) ,	// output  fetch_b0
	.wr_bena_b0(wr_bena_b0) ,	// input [1:0] wr_bena_b0
	.wr_data_b0(wr_data_b0) ,	// input [15:0] wr_data_b0
	
	.rden_b1(rden_b1) ,	// input  rden_b1
	.wren_b1(wren_b1) ,	// input  wren_b1
	.addr_b1(addr_b1) ,	// input [31:0] addr_b1
	.valid_b1(valid_b1) ,	// output  valid_b1
	.fetch_b1(fetch_b1) ,	// output  fetch_b1
	.wr_bena_b1(wr_bena_b1) ,	// input [1:0] wr_bena_b1
	.wr_data_b1(wr_data_b1) ,	// input [15:0] wr_data_b1
	
	.rden_b2(rden_b2) ,	// input  rden_b2
	.wren_b2(wren_b2) ,	// input  wren_b2
	.addr_b2(addr_b2) ,	// input [31:0] addr_b2
	.valid_b2(valid_b2) ,	// output  valid_b2
	.fetch_b2(fetch_b2) ,	// output  fetch_b2
	.wr_bena_b2(wr_bena_b2) ,	// input [1:0] wr_bena_b2
	.wr_data_b2(wr_data_b2) ,	// input [15:0] wr_data_b2
	
	.rden_b3(rden_b3) ,	// input  rden_b3
	.wren_b3(wren_b3) ,	// input  wren_b3
	.addr_b3(addr_b3) ,	// input [31:0] addr_b3
	.valid_b3(valid_b3) ,	// output  valid_b3
	.fetch_b3(fetch_b3) ,	// output  fetch_b3
	.wr_bena_b3(wr_bena_b3) ,	// input [1:0] wr_bena_b3
	.wr_data_b3(wr_data_b3) ,	// input [15:0] wr_data_b3
	
	.sdram_cs_n( SDRAM_nCS ) ,	// output  sdram_cs_n
	.sdram_ras_n( SDRAM_nRAS ) ,// output  sdram_ras_n
	.sdram_cas_n( SDRAM_nCAS ) ,// output  sdram_cas_n
	.sdram_we_n( SDRAM_nWE ) ,	// output  sdram_we_n
	.sdram_ba( SDRAM_BA ) ,		// output [1:0] sdram_ba
	.sdram_addr( SDRAM_A ) ,	// output [12:0] sdram_addr
	.sdram_dqm_n( {SDRAM_DQMH, SDRAM_DQML} ) ,// output [1:0] sdram_dqm_n
	.sdram_dq_oe( sdram_dq_oe ) ,// output  sdram_dq_oe
	.sdram_dq_o( sdram_dq_o ) ,	// output [15:0] sdram_dq_o
	.sdram_dq_i( SDRAM_DQ ) 		// input [15:0] sdram_dq_i
);

wire sdram_dq_oe;
wire [15:0] sdram_dq_o;


assign SDRAM_CKE = 1'b1;
assign SDRAM_CLK = clk_ram;

assign SDRAM_DQ = (sdram_dq_oe) ? sdram_dq_o : 16'hzzzz;


endmodule
