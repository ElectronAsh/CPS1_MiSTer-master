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

//assign VIDEO_ARX = status[9] ? 8'd16 : 8'd4;
//assign VIDEO_ARY = status[9] ? 8'd9  : 8'd3;
assign VIDEO_ARX = 8'd4;
assign VIDEO_ARY = 8'd3;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;

`include "build_id.v"
localparam CONF_STR = {
	"CPS;;",
	"-;",
	"F,BINROM ;",
	"-;",
	"O69,Layer,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15;",
	"-;",
	"-;",
	"-;",
	"O13,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O4,Swap joysticks,No,Yes;",
	"O5,6 buttons mode,No,Yes;",
	"-;",
	"R0,Reset;",
	"J1,1,2,3,4,coin,start,service,test;",
	"V,v1.51.",`BUILD_DATE
};

wire [3:0] layer = status[9:6];

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
	.status_in(status),
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
wire clk_sys, clk_ram, clk_ntsc, pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_ram),
	.outclk_2(clk_ntsc),
	.locked(pll_locked)
);

///////////////////////////////////////////////////
wire [3:0] r, g, b;
wire vs,hs;
wire ce_pix;
wire hblank, vblank;
wire interlace;


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


wire reset = RESET | status[0] | buttons[1] | !BTN_USER | ioctl_download;

reg [19:0] CLK_DIV;
always @(posedge clk_sys or posedge reset)
if (reset) CLK_DIV <= 20'd0;
else CLK_DIV <= CLK_DIV + 1;


reg fx68k_enPhi1;
reg fx68k_enPhi2;

reg as_n_1;
wire as_n_falling = as_n_1 && !fx68k_as_n;

reg [1:0] clkdiv;
always @(posedge clk_sys) begin
	clkdiv <= clkdiv + 2'd1;
	
	as_n_1 <= fx68k_as_n;
	
	fx68k_enPhi1 <= 1'b0;
	fx68k_enPhi2 <= 1'b0;
	
	//if (clkdiv==0) begin
		//fx68k_enPhi1 <= 1'b1;
	//end

	if (clkdiv==1) begin
		fx68k_enPhi1 <= 1'b1;
	end
	
	//if (clkdiv==2) begin
		//fx68k_enPhi2 <= 1'b1;
	//end
	
	if (clkdiv==3) begin
		fx68k_enPhi2 <= 1'b1;
	end	
end


(*keep*) wire fx68k_clk = clk_sys;
(*keep*) wire fx68k_rst = reset;

(*keep*) wire fx68k_rw;
(*keep*) wire fx68k_as_n;
(*keep*) wire fx68k_lds_n;
(*keep*) wire fx68k_uds_n;
(*keep*) wire fx68k_e;
(*keep*) wire fx68k_vma_n;

(*keep*) wire fx68k_berr_n = 1'b1;

(*keep*) wire [2:0] fx68k_fc;

//wire fx68k_vpa_n = 1'b1;							// vpa_n tied High, means it's NOT using auto-vector for the interrupt. ElectronAsh.
(*keep*) wire fx68k_vpa_n = !(fx68k_fc==7);	// vpa_n driven Low when the interrupt is being serviced, which will trigger Auto-vectored interrupt.


(*keep*) wire [23:1] fx68k_addr;										// WORD address. LSB not used! (like on the real 68000).

(*keep*) wire [23:0] fx68k_byte_addr = {fx68k_addr, 1'b0};	// LSB added, and tied low. Makes it easier for SignalTap debugging, and address decoding.

(*keep*) wire [15:0] fx68k_di;
(*keep*) wire [15:0] fx68k_do;

(*keep*) wire fx68k_dtack_n = (CPU_ROM_CS /*| CPU_RAM_CS*/) ? sdram_68k_busy : 1'b0;


(*keep*) wire fx68k_ipl_n_2 = !HBLANK_INT;
(*keep*) wire fx68k_ipl_n_1 = !VBLANK_INT;
(*keep*) wire fx68k_ipl_n_0 = 1'b1;


(*keep*) wire fx68k_bg_n;

(*keep*) wire fx68k_br_n = 1'b1;			// Bus Request.
(*keep*) wire fx68k_bgack_n = 1'b1;		// Bus Grant Acknowledge.

(*keep*) wire fx68k_write_pulse = !fx68k_as_n && !fx68k_rw && fx68k_enPhi1 && (!fx68k_uds_n | !fx68k_lds_n);


fx68k fx68k_inst
(
	.clk( fx68k_clk ) ,			// input  clk
	
	.extReset( fx68k_rst ) ,	// input  extReset
	.pwrUp( fx68k_rst ) ,		// input  pwrUp
	
	.enPhi1( fx68k_enPhi1 ) ,	// input  enPhi1
	.enPhi2( fx68k_enPhi2 ) ,	// input  enPhi2
	
	.eRWn( fx68k_rw ) ,			// output  eRWn
	.ASn( fx68k_as_n ) ,			// output  ASn
	.LDSn( fx68k_lds_n ) ,		// output  LDSn
	.UDSn( fx68k_uds_n ) ,		// output  UDSn
	.E( fx68k_e ) ,				// output  E
	.VMAn( fx68k_vma_n ) ,		// output  VMAn
	
	.FC0( fx68k_fc[0] ) ,		// output  FC0
	.FC1( fx68k_fc[1] ) ,		// output  FC1
	.FC2( fx68k_fc[2] ) ,		// output  FC2
	
	.oRESETn( ) ,					// output  oRESETn
	.oHALTEDn( ) ,					// output  oHALTEDn
	
	.DTACKn( fx68k_dtack_n ) ,	// input  DTACKn
	
	.VPAn( fx68k_vpa_n ) ,		// input  VPAn - Tied HIGH on the real Jag.
	
	.BERRn( fx68k_berr_n ) ,	// input  BERRn - Tied HIGH on the real Jag.
	
	.BRn( fx68k_br_n ) ,			// input  BRn
	.BGn( fx68k_bg_n ) ,			// output  BGn
	.BGACKn( fx68k_bgack_n ) ,	// input  BGACKn
	
	.IPL0n( fx68k_ipl_n_0 ) ,	// input  IPL0n
	.IPL1n( fx68k_ipl_n_1 ) ,	// input  IPL1n
	.IPL2n( fx68k_ipl_n_2 ) ,	// input  IPL2n
	
	.iEdb( fx68k_di ) ,			// input [15:0] iEdb
	.oEdb( fx68k_do ) ,		// output [15:0] oEdb
	
	.eab( fx68k_addr ) 		// output [23:1] eab
);


/*
cpu_rom_hi	cpu_rom_hi_inst (
	.clock ( clk_sys ),
	.address ( fx68k_addr[17:1] ),
	.q ( ROM_HI_DO )
);
wire [7:0] ROM_HI_DO;


cpu_rom_lo	cpu_rom_lo_inst (
	.clock ( clk_sys ),
	.address ( fx68k_addr[17:1] ),
	.q ( ROM_LO_DO )
);
wire [7:0] ROM_LO_DO;
*/

/*
assign SDRAM_CLK = clk_ram;

sdram sdram (
    // system interface
   .init           ( ~pll_locked               ),
	.clk            ( clk_sys                   ),
   
   // interface to the MT48LC16M16 chip
   .SDRAM_DQ       ( SDRAM_DQ                  ),
   .SDRAM_A        ( SDRAM_A                   ),
   .SDRAM_DQML     ( SDRAM_DQML                ),
	.SDRAM_DQMH     ( SDRAM_DQMH                ),
   .SDRAM_nCS      ( SDRAM_nCS                 ),
   .SDRAM_BA       ( SDRAM_BA                  ),
   .SDRAM_nWE      ( SDRAM_nWE                 ),
   .SDRAM_nRAS     ( SDRAM_nRAS                ),
   .SDRAM_nCAS     ( SDRAM_nCAS                ),
	.SDRAM_CKE      ( SDRAM_CKE                 ),

   // cpu interface
	.addr           ( sdram_addr                ),
   .din            ( sdram_din                 ),
	.wtbt				 ( sdram_be                  ),
   .we             ( sdram_wr                  ),
	
   .rd             ( sdram_rd 					  ),
   .dout           ( sdram_dout                ),
	.ready          ( sdram_ready               )
);
wire sdram_ready;
*/


sdram sdram
(
	.*,
	
	.init(~pll_locked),
	
	//.clk( clk_ram ),
	.clk( clk_sys ),			// Apparently don't need the phase shift any more? DDIO is used to generate SDRAM_CLK instead.
	
	// Port 0.
	.addr0( sdram_addr ),	// WORD address!! [20:1]
	.dout0( sdram_dout ),
	.rd0( sdram_rd ),
	.din0( sdram_din ),
	.wrl0( sdram_wrh ),
	.wrh0( sdram_wrl ),
	.rfs0( sdram_rfs0 ),
	.busy0( sdram_68k_busy ),

	// Port 1.
	.addr1( ioctl_addr ),
	.dout1( ),
	.rd1(0),

	.din1( {ioctl_data[7:0],ioctl_data[15:8]} ),
	.wrl1( ioctl_wr ),		// HPS writes a whole WORD at a time.
	.wrh1( ioctl_wr ),
	.rfs1(0),
	.busy1( sdram_cart_busy ),
	
	// Port 2.
	.addr2(0),
	.din2(0),
	.dout2(),
	.rd2(0),
	.wrl2(0),
	.wrh2(0),
	.rfs2(0),
	.busy2()
);

reg sdram_rfs0;
reg [8:0] refresh_counter;
reg refresh_pending;
always @(posedge clk_sys or posedge reset)
if (reset) begin
	//refresh_counter <= 9'd400;
	refresh_counter <= 9'd200;
	refresh_pending <= 1'b0;
	sdram_rfs0 <= 1'b0;
end
else begin
	if (refresh_counter==0) begin
		refresh_counter <= 9'd200;
		refresh_pending <= 1'b1;
	end
	else refresh_counter <= refresh_counter - 9'd1;
	
	if (refresh_pending && !sdram_68k_busy && fx68k_as_n) begin
		sdram_rfs0 <= 1'b1;
		refresh_pending <= 1'b0;
	end
end


/*
sdram ram1(
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_A(SDRAM_A),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nWE(SDRAM_nWE),

	.init(~pll_locked),	// Init SDRAM as soon as the PLL is locked
	.clk(clk_sys),
	
	.ch1_addr( ch1_addr ),		// input      [26:1] ch1_addr. 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
	.ch1_dout( ch1_dout ),		// output reg [63:0] ch1_dout. data output
	.ch1_din( ch1_din ),			// input      [15:0] ch1_din.  data input
	.ch1_req( ch1_req ),			// input             ch1_req.  request
	.ch1_rnw( ch1_rnw ),			// input             ch1_rnw.  1 - read, 0 - write
	.ch1_ready( ch1_ready ),	// output reg        ch1_ready,
	
	.ch2_addr( ch2_addr ),		// input      [26:1] ch2_addr. 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
	.ch2_dout( ch2_dout ),		// output reg [31:0] ch2_dout. data output
	.ch2_din( ch2_din ),			// input      [31:0] ch2_din.  data input
	.ch2_req( ch2_req ),			// input             ch2_req.  request
	.ch2_rnw( ch2_rnw ),			// input             ch2_rnw.  1 - read, 0 - write
	.ch2_ready( ch2_ready ),	// output reg        ch2_ready,
	
	.ch3_addr( ch3_addr ),		// input      [26:1] ch3_addr. 25 bit address for 8bit mode. addr[0] = 0 for 16bit mode for correct operations.
	.ch3_dout( ch3_dout ),		// output reg [15:0] ch3_dout. data outpu
	.ch3_din( ch3_din ),			// input      [15:0] ch3_din.  data input
	.ch3_req( ch3_req ),			// input             ch3_req.  request
	.ch3_rnw( ch3_rnw ),			// input             ch3_rnw.  1 - read, 0 - write
	.ch3_ready( ch3_ready )		// output reg        ch3_ready,
);
wire [26:1] ch1_addr = sdram_addr;
wire [63:0] ch1_dout;
wire [15:0] ch1_din;
wire ch1_req = !ioctl_download && CPU_ROM_CS && !fx68k_as_n;
wire ch1_rnw = fx68k_rw;
wire ch1_ready;

wire [26:1] ch2_addr = ioctl_addr;
wire [31:0] ch2_dout = {ioctl_data, ioctl_data};
wire [31:0] ch2_din;
wire ch2_req = ioctl_download && ioctl_wr;
wire ch2_rnw = 1'b0;	// Write!
wire ch2_ready;

wire [26:1] ch3_addr;
wire [15:0] ch3_dout;
wire [15:0] ch3_din;
wire ch3_req = 1'b0;
wire ch3_rnw;
wire ch3_ready;

//assign ioctl_wait = ioctl_download && !ch3_ready;
assign ioctl_wait = 1'b0;


//(*keep*) wire sdram_68k_busy = !ch1_ready;
(*keep*) wire sdram_68k_busy = 1'b0;

(*keep*) wire [15:0] sdram_dout = ch1_dout[15:0];

(*keep*) wire [15:0] sdram_din = fx68k_do;
*/

								
wire [20:1] sdram_addr = /*(CPU_RAM_CS) ? {5'b10000, fx68k_addr[15:1]} :*/	// Force 68000 RAM to map to 0x100000-0x10FFFF (WORD address!) in SDRAM.
													    fx68k_addr[20:1];					// Allow reading of 68000 ROM.

//wire sdram_wrh = CPU_RAM_CS && !fx68k_uds_n && !fx68k_as_n && !fx68k_rw && fx68k_enPhi1;
//wire sdram_wrl = CPU_RAM_CS && !fx68k_lds_n && !fx68k_as_n && !fx68k_rw && fx68k_enPhi1;

wire sdram_wrh = 1'b0;
wire sdram_wrl = 1'b0;

wire sdram_rd = !fx68k_as_n && fx68k_rw && (CPU_ROM_CS/* | CPU_RAM_CS*/);


//wire  [1:0] sdram_be = 2'b11;


// BYTE Addresses for SDRAM...
//
// 0x000000-0x0FFFFF = 68000 Program ROM. (1MB)
// 0x100000-0x10FFFF = 68000 RAM.         (64KB)
// 0x110000-0x11FFFF = Z80 Program ROM.   (64KB)
// 0x120000-0x15FFFF = PCM Sample ROM.    (256KB)
// 0x160000-onwards  = Tile ROMs.         (quite a lot)
//


//assign rom_wrack = 1'b1;
//assign rom_rdack = 1'b1;


(*keep*) wire CPU_RAM_WREN = CPU_RAM_CS && fx68k_write_pulse;
(*keep*) wire [1:0] CPU_RAM_BE = {!fx68k_uds_n, !fx68k_lds_n};

cpu_ram	cpu_ram_inst (
	.clock ( clk_sys ),
	.address ( fx68k_addr[15:1] ),
	
	.data ( fx68k_do ),
	.wren ( CPU_RAM_WREN ),
	.byteena( CPU_RAM_BE ),
	
	.q ( CPU_RAM_DO )
);
(*keep*) wire [15:0] CPU_RAM_DO;


(*noprune*) reg [10:0] KEEP_REG;
always @(posedge clk_sys) begin
	KEEP_REG <= {CPU_ROM_CS, PLAYER_CS, SERV_CS, NOPR_CS, COINCTRL_CS, CPSA_CS, CPSB_CS, SOUNDCMD_CS, SOUNDFADE_CS, GFX_RAM_CS, CPU_RAM_CS};
end

// Note: The LSB bit of fx68k_byte_addr is tied Low, so the comparisons for some of these ODD addresses will be ignored. ElectronAsh.

(*keep*) wire CPU_ROM_CS	= (fx68k_byte_addr>=24'h000000 && fx68k_byte_addr<=24'h3FFFFF);
(*keep*) wire PLAYER_CS		= (fx68k_byte_addr>=24'h800000 && fx68k_byte_addr<=24'h800007);
(*keep*) wire SERV_CS		= (fx68k_byte_addr>=24'h800018 && fx68k_byte_addr<=24'h800019);
(*keep*) wire DIPA_CS		= (fx68k_byte_addr>=24'h80001A && fx68k_byte_addr<=24'h80001B);
(*keep*) wire DIPB_CS		= (fx68k_byte_addr>=24'h80001C && fx68k_byte_addr<=24'h80001D);
(*keep*) wire DIPC_CS		= (fx68k_byte_addr>=24'h80001E && fx68k_byte_addr<=24'h80001F);
(*keep*) wire NOPR_CS		= (fx68k_byte_addr>=24'h800020 && fx68k_byte_addr<=24'h800021);
(*keep*) wire COINCTRL_CS	= (fx68k_byte_addr>=24'h800030 && fx68k_byte_addr<=24'h800037);
(*keep*) wire CPSA_CS		= (fx68k_byte_addr>=24'h800100 && fx68k_byte_addr<=24'h80013F);
(*keep*) wire CPSB_CS		= (fx68k_byte_addr>=24'h800140 && fx68k_byte_addr<=24'h80017F);
(*keep*) wire SOUNDCMD_CS	= (fx68k_byte_addr>=24'h800180 && fx68k_byte_addr<=24'h800187);
(*keep*) wire SOUNDFADE_CS	= (fx68k_byte_addr>=24'h800188 && fx68k_byte_addr<=24'h80018F);
(*keep*) wire GFX_RAM_CS	= (fx68k_byte_addr>=24'h900000 && fx68k_byte_addr<=24'h92FFFF);
(*keep*) wire CPU_RAM_CS 	= (fx68k_byte_addr>=24'hFF0000 && fx68k_byte_addr<=24'hFFFFFF);


// CPS-A Registers...
//
// All regs are write-only, apparently.
wire CPS_A_OBJ_CS = 			(fx68k_byte_addr>=24'h800100 && fx68k_byte_addr<=24'h800101);
wire CPS_A_SCR1_CS = 		(fx68k_byte_addr>=24'h800102 && fx68k_byte_addr<=24'h800103);
wire CPS_A_SCR2_CS = 		(fx68k_byte_addr>=24'h800104 && fx68k_byte_addr<=24'h800105);
wire CPS_A_SCR3_CS = 		(fx68k_byte_addr>=24'h800106 && fx68k_byte_addr<=24'h800107);
wire CPS_A_RSCR_CS =			(fx68k_byte_addr>=24'h800108 && fx68k_byte_addr<=24'h800109);
wire CPS_A_PAL_CS =			(fx68k_byte_addr>=24'h80010a && fx68k_byte_addr<=24'h80010b);
wire CPS_A_SCR1_X_CS =		(fx68k_byte_addr>=24'h80010c && fx68k_byte_addr<=24'h80010d);
wire CPS_A_SCR1_Y_CS =		(fx68k_byte_addr>=24'h80010e && fx68k_byte_addr<=24'h80010f);
wire CPS_A_SCR2_X_CS =		(fx68k_byte_addr>=24'h800110 && fx68k_byte_addr<=24'h800111);
wire CPS_A_SCR2_Y_CS =		(fx68k_byte_addr>=24'h800112 && fx68k_byte_addr<=24'h800113);
wire CPS_A_SCR3_X_CS =		(fx68k_byte_addr>=24'h800114 && fx68k_byte_addr<=24'h800115);
wire CPS_A_SCR3_Y_CS =		(fx68k_byte_addr>=24'h800116 && fx68k_byte_addr<=24'h800117);
wire CPS_A_STAR1_X_CS =		(fx68k_byte_addr>=24'h800118 && fx68k_byte_addr<=24'h800119);
wire CPS_A_STAR1_Y_CS =		(fx68k_byte_addr>=24'h80011a && fx68k_byte_addr<=24'h80011b);
wire CPS_A_STAR2_X_CS =		(fx68k_byte_addr>=24'h80011c && fx68k_byte_addr<=24'h80011d);
wire CPS_A_STAR2_Y_CS =		(fx68k_byte_addr>=24'h80011e && fx68k_byte_addr<=24'h80011f);
wire CPS_A_RSCR_OFFS_CS =	(fx68k_byte_addr>=24'h800120 && fx68k_byte_addr<=24'h800121);
wire CPS_A_vCONT_CS =		(fx68k_byte_addr>=24'h800122 && fx68k_byte_addr<=24'h800123);


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
wire CPS_B_LAYERCON_CS = (fx68k_byte_addr>=24'h800166 && fx68k_byte_addr<=24'h800167);
wire CPS_B_PRIMASK1_CS = (fx68k_byte_addr>=24'h800168 && fx68k_byte_addr<=24'h800169);
wire CPS_B_PRIMASK2_CS = (fx68k_byte_addr>=24'h80016a && fx68k_byte_addr<=24'h80016b);
wire CPS_B_PRIMASK3_CS = (fx68k_byte_addr>=24'h80016c && fx68k_byte_addr<=24'h80016d);
wire CPS_B_PRIMASK4_CS = (fx68k_byte_addr>=24'h80016e && fx68k_byte_addr<=24'h80016f);
wire CPS_B_PALCONT_CS  = (fx68k_byte_addr>=24'h800170 && fx68k_byte_addr<=24'h800171);

(*keep*) wire CPS_B_SF2_ID_CS = (fx68k_byte_addr>=24'h800172 && fx68k_byte_addr<=24'h800173);

reg [15:0] CPS_B_LAYERCON_REG;
reg [15:0] CPS_B_PRIMASK1_REG;
reg [15:0] CPS_B_PRIMASK2_REG;
reg [15:0] CPS_B_PRIMASK3_REG;
reg [15:0] CPS_B_PRIMASK4_REG;
reg [15:0] CPS_B_PALCONT_REG;


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
	else if (fx68k_fc==3'd7) HBLANK_INT <= 1'b0;	// If the 68K services the Interrupt, clear the HBLANK_INT flag.
	
	if (CLK_DIV==0) VBLANK_INT <= 1'b1;
	else if (fx68k_fc==3'd7) VBLANK_INT <= 1'b0;	// If the 68K services the Interrupt, clear the VBLANK_INT flag.
	
	// CPS_A Register WRITES...
	if (CPS_A_OBJ_CS			&& fx68k_write_pulse) CPS_A_OBJ_REG			<= fx68k_do;
	if (CPS_A_SCR1_CS			&& fx68k_write_pulse) CPS_A_SCR1_REG		<= fx68k_do;
	if (CPS_A_SCR2_CS			&& fx68k_write_pulse) CPS_A_SCR2_REG		<= fx68k_do;
	if (CPS_A_SCR3_CS			&& fx68k_write_pulse) CPS_A_SCR3_REG		<= fx68k_do;
	if (CPS_A_RSCR_CS			&& fx68k_write_pulse) CPS_A_RSCR_REG		<= fx68k_do;
	if (CPS_A_PAL_CS			&& fx68k_write_pulse) CPS_A_PAL_REG			<= fx68k_do;
	if (CPS_A_SCR1_X_CS		&& fx68k_write_pulse) CPS_A_SCR1_X_REG		<= fx68k_do;
	if (CPS_A_SCR1_Y_CS		&& fx68k_write_pulse) CPS_A_SCR1_Y_REG		<= fx68k_do;
	if (CPS_A_SCR2_X_CS		&& fx68k_write_pulse) CPS_A_SCR2_X_REG		<= fx68k_do;
	if (CPS_A_SCR2_Y_CS		&& fx68k_write_pulse) CPS_A_SCR2_Y_REG		<= fx68k_do;
	if (CPS_A_SCR3_X_CS		&& fx68k_write_pulse) CPS_A_SCR3_X_REG		<= fx68k_do;
	if (CPS_A_SCR3_Y_CS		&& fx68k_write_pulse) CPS_A_SCR3_Y_REG		<= fx68k_do;
	if (CPS_A_STAR1_X_CS		&& fx68k_write_pulse) CPS_A_STAR1_X_REG	<= fx68k_do;
	if (CPS_A_STAR1_Y_CS		&& fx68k_write_pulse) CPS_A_STAR1_Y_REG	<= fx68k_do;
	if (CPS_A_STAR2_X_CS		&& fx68k_write_pulse) CPS_A_STAR2_X_REG	<= fx68k_do;
	if (CPS_A_STAR2_Y_CS		&& fx68k_write_pulse) CPS_A_STAR2_Y_REG	<= fx68k_do;
	if (CPS_A_RSCR_OFFS_CS	&& fx68k_write_pulse) CPS_A_RSCR_OFFS_REG <= fx68k_do;
	if (CPS_A_vCONT_CS		&& fx68k_write_pulse) CPS_A_vCONT_REG		<= fx68k_do;

	// CPS_B Register WRITES...
	if (CPS_B_LAYERCON_CS	&& fx68k_write_pulse) CPS_B_LAYERCON_REG	<= fx68k_do;
	if (CPS_B_PRIMASK1_CS	&& fx68k_write_pulse) CPS_B_PRIMASK1_REG	<= fx68k_do;
	if (CPS_B_PRIMASK2_CS	&& fx68k_write_pulse) CPS_B_PRIMASK2_REG	<= fx68k_do;
	if (CPS_B_PRIMASK3_CS	&& fx68k_write_pulse) CPS_B_PRIMASK3_REG	<= fx68k_do;
	if (CPS_B_PRIMASK4_CS	&& fx68k_write_pulse) CPS_B_PRIMASK4_REG	<= fx68k_do;
	if (CPS_B_PALCONT_CS		&& fx68k_write_pulse) CPS_B_PALCONT_REG	<= fx68k_do;
end



// Player controls are all active-HIGH here!...
wire P1_RIGHT	= joystick_0[0];
wire P1_LEFT	= joystick_0[1];
wire P1_DOWN	= joystick_0[2];
wire P1_UP		= joystick_0[3];
wire P1_BUT1	= joystick_0[4];
wire P1_BUT2	= joystick_0[5];
wire P1_BUT3	= joystick_0[6];
wire P1_UNK		= joystick_0[7];

wire P2_RIGHT	= joystick_1[0];
wire P2_LEFT	= joystick_1[1];
wire P2_DOWN	= joystick_1[2];
wire P2_UP		= joystick_1[3];
wire P2_BUT1	= joystick_1[4];
wire P2_BUT2	= joystick_1[5];
wire P2_BUT3	= joystick_1[6];
wire P2_UNK		= joystick_1[7];

wire [15:0] JOYSTICKS = ~{P2_UNK, P2_BUT3, P2_BUT2, P2_BUT1, P2_UP, P2_DOWN, P2_LEFT, P2_RIGHT,
								  P1_UNK, P1_BUT3, P1_BUT2, P1_BUT1, P1_UP, P1_DOWN, P1_LEFT, P1_RIGHT};


// Switches / DIP Switches are all active-HIGH here!...
wire COIN1	= joystick_0[8];
wire START1	= joystick_0[9];

wire COIN2	= joystick_1[8];
wire START2	= joystick_1[9];

wire SERV1	= joystick_0[10];
wire SERVSW	= joystick_0[11];
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

//wire DEMO_SOUNDS = 1'b1;
wire DEMO_SOUNDS = 1'b0;	// TESTING. Not sure if this stuff is inverted?

wire GAME_MODE = 1'b0;		// 0=GAME. 1=TEST.
wire [7:0] DIPC = ~{3'b000, FREEZE, FLIP_SCREEN, DEMO_SOUNDS, 1'b0, GAME_MODE};



//(*keep*) wire [15:0] ROM_DATA_FULL = {ROM_HI_DO, ROM_LO_DO};	// On-chip.


(*keep*) assign fx68k_di = //(CPU_ROM_CS) ? ROM_DATA_FULL : 
									(CPU_ROM_CS) ? sdram_dout :

									(CPU_RAM_CS) ? CPU_RAM_DO :
									//(CPU_RAM_CS) ? sdram_dout :
									 
									(PLAYER_CS) ? JOYSTICKS :
									 
									(SERV_CS)  ? {SERV, 8'hFF} :	// Coin/Start/Service button bits are already active-LOW here. Mapped to the upper bits of the 68K!
									
									(DIPA_CS)  ? {DIPA, 8'hFF} :
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
/*
gfx_ram	gfx_ram_inst (
	.clock ( clk_sys ),
	.address ( fx68k_addr[17:1] ),
	
	.data ( fx68k_do ),
	.wren ( GFX_RAM_WREN ),
	.byteena( GFX_RAM_BE ),
	
	.q ( GFX_RAM_DO )
);
*/

gfx_ram_dp	gfx_ram_dp_inst (
	.clock_a ( clk_sys ),
	.address_a ( fx68k_addr[17:1] ),
	.data_a ( fx68k_do ),
	.wren_a ( GFX_RAM_WREN ),
	.byteena_a ( GFX_RAM_BE ),
	.q_a ( GFX_RAM_DO ),
	
	.clock_b ( PATT_CLK_IN ),
	.address_b ( GFX_RAM_READ_ADDR ),
//	.data_b ( GFX_RAM_READ_DI ),
	.wren_b ( 1'b0 ),
	.q_b ( GFX_RAM_READ_DO )
);

(*keep*) wire [15:0] GFX_RAM_DO;

(*keep*) wire GFX_RAM_WREN = GFX_RAM_CS && !fx68k_as_n && !fx68k_rw;
(*keep*) wire [1:0] GFX_RAM_BE = {!fx68k_uds_n, !fx68k_lds_n};



wire [16:0] GFX_RAM_READ_ADDR = (layer<<13) | {PATT_Y_IN[11:3], PATT_X_IN[11:4]};

wire [15:0] GFX_RAM_READ_DO;

assign VGA_R = (PATT_DE_IN) ? {GFX_RAM_READ_DO[15:11], 3'b000} : 8'h00;
assign VGA_G = (PATT_DE_IN) ? {GFX_RAM_READ_DO[10:5],  2'b00}  : 8'h00;
assign VGA_B = (PATT_DE_IN) ? {GFX_RAM_READ_DO[4:0],   3'b000} : 8'h00;

assign CLK_VIDEO = PATT_CLK_IN;
assign CE_PIXEL = 1'b1;

/*
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
*/
assign VGA_HS = !PATT_HS_IN;
assign VGA_VS = !PATT_VS_IN;
assign VGA_DE = PATT_DE_IN;

/*
cps_a cps_a_inst
(
	.RESET_N(!reset) ,		// input  RESET_N
	.CLK(PATT_CLK_IN) ,		// input  CLK
	.HBLANK_N(HBLANK_N) ,	// input  HBLANK_N
	.VBLANK_N(VBLANK_N) ,	// input  VBLANK_N
	.CSB(CSB) ,					// input  CSB
	.WRB(WRB) ,					// input  WRB
	.CA(CA) ,					// inout [23:0] CA
	.CDIN(CDIN) ,				// input [15:0] CDIN
	.CDOUT(CDOUT) ,			// output [15:0] CDOUT
	.BRB(BRB) ,					// output  BRB
	.BGACKB(BGACKB) ,			// input  BGACKB
	.PATT_X(PATT_X) ,			// input [11:0] PATT_X
	.PATT_Y(PATT_Y) ,			// input [11:0] PATT_Y
	.CK125(CK125) ,			// output  CK125
	.CK250(CK250) ,			// output  CK250
	.ROMA(ROMA) ,				// output [22:0] ROMA
	.GFX_RAM_ADDR(GFX_RAM_ADDR) ,	// output [16:0] GFX_RAM_ADDR
	.GFX_RAM_DO(GFX_RAM_DO) ,	// input [15:0] GFX_RAM_DO
	.GFX_RAM_DI(GFX_RAM_DI) 	// output [15:0] GFX_RAM_DI
);
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
	.CLK( clk_ntsc ) ,			// input  CLK
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


// 68K to Z80 command regs / latches...
reg [7:0] Z80_CMD_REG;
reg [7:0] Z80_FADE_REG;
always @(posedge fx68k_clk or posedge reset)
if (reset) begin
	Z80_CMD_REG <= 8'h00;
	Z80_FADE_REG <= 8'h00;
end
else begin
	if (SOUNDCMD_CS  && fx68k_write_pulse) Z80_CMD_REG <= fx68k_do[7:0];
	if (SOUNDFADE_CS && fx68k_write_pulse) Z80_FADE_REG <= fx68k_do[7:0];
end


reg Z80_BANK_REG;
reg PCM_SS_REG;

reg [15:0] DELAY;
reg [3:0] CNT;
always @(posedge clk_ntsc or posedge reset)
if (reset) begin
	//Z80_CMD_REG <= 8'h00;
	//Z80_FADE_REG <= 8'h00;
	//DELAY <= 16'hFFFF;
	//CNT <= 0;
	Z80_BANK_REG <= 1'b0;
	PCM_SS_REG <= 1'b1;
end
else begin
	//DELAY <= DELAY - 1;
	
	if (Z80_BANK_CS && !T80_WR_N) Z80_BANK_REG <= T80_DO[0];
	//if (Z80_SEL_CS && !T80_WR_N) PCM_SS_REG <= T80_DO[0];
	
	/*
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
		Z80_CMD_REG <= 8'h09;	// Music selection. (SF2 - Balrog's theme).
		//Z80_CMD_REG <= 8'h0A;	// Music selection. (SF2 - Vega's theme).
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
	*/
end


wire JT51_CLK = clk_ntsc;
wire JT51_RsT = reset;
wire JT51_CS_N = !Z80_JT51_CS;
wire JT51_WR_N = !(Z80_JT51_CS && !T80_WR_N && !T80_MREQ_N);
wire JT51_A0 = T80_ADDR[0];
wire [7:0] JT51_DI = T80_DO;
wire [7:0] JT51_DO;
wire JT51_CT1;
wire JT51_CT2;
wire JT51_IRQ_N;
wire JT51_P1;
wire JT51_SAMPLE;
(*keep*) wire signed [15:0] JT51_L;
(*keep*) wire signed [15:0] JT51_R;
(*keep*) wire signed [15:0] JT51_XLEFT;
(*keep*) wire signed [15:0] JT51_XRIGHT;
(*keep*) wire [15:0] JT51_DACLEFT;
(*keep*) wire [15:0] JT51_DACRIGHT;


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
	
	.left( JT51_L ) ,				// output [15:0] left
	.right( JT51_R ) ,			// output [15:0] right
	.xleft( JT51_XLEFT ) ,		// output [15:0] xleft
	.xright( JT51_XRIGHT ) ,	// output [15:0] xright
	.dacleft( JT51_DACLEFT ) ,	// output [15:0] dacleft
	.dacright( JT51_DACRIGHT ) // output [15:0] dacright
);


/*
wire PCM_RESET_N = !reset;
wire PCM_CLK = clk_ntsc;

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
*/


assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

//wire signed [16:0] MIX_L = PCM_SOUND_OUT[21:5];

//wire signed [16:0] MIX_L = {JT51_XLEFT[15],  JT51_XLEFT}  + {PCM_SOUND_OUT[21], PCM_SOUND_OUT[21:5]};
//wire signed [16:0] MIX_R = {JT51_XRIGHT[15], JT51_XRIGHT} + {PCM_SOUND_OUT[19], PCM_SOUND_OUT[19:4]};

//wire signed [16:0] MIX_L = JT51_XLEFT  + PCM_SOUND_OUT[19:4];
//wire signed [16:0] MIX_R = JT51_XRIGHT + PCM_SOUND_OUT[19:4];


//assign AUDIO_L = MIX_L[16:1];
//assign AUDIO_R = MIX_R[16:1];

// Original chip quality...
assign AUDIO_L = JT51_XLEFT;
assign AUDIO_R = JT51_XRIGHT;

// Better quality?...
//assign AUDIO_L = JT51_XLEFT;
//assign AUDIO_R = JT51_XRIGHT;

//assign AUDIO_R = PCM_SOUND_OUT[19:4];


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
wire rom_rd;
wire rom_rdack;
/*

assign DDRAM_CLK = clk_ram;

ddram ddram
(
	.*,

   .wraddr(ioctl_addr),
   .din({ioctl_data[7:0],ioctl_data[15:8]}),
   .we_req(rom_wr),
   //.we_ack(rom_wrack),
	.we_ack(),

   .rdaddr(use_map ? {map[rom_addr[21:19]], rom_addr[18:1]} : rom_addr),
   .dout(rom_data),
   .rd_req(rom_rd),
   .rd_ack(rom_rdack)
);
*/

/*
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
*/

/*
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
*/


/*
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
*/

endmodule
