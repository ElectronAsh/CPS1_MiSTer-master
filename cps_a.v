module cps_a (
	input RESET_N,
	
	input CLK,
  
	input HBLANK_N,
	input VBLANK_N,
  
	input CSB,			// Chip Select (active-Low).
	input WRB,			// Write enable (active-Low).
	
	inout  [23:0] CA,		// 68000 bus address.
	input  [15:0] CDIN,	// 68000 bus data in.
	output [15:0] CDOUT,	// 68000 bus data in.
	
	output BRB,		// Bus Req. To the 68000, probably.
	input BGACKB,	// Bus Grant Acknowledge. From the 68000, probably.
	
	input [11:0] PATT_X,
	input [11:0] PATT_Y,
	
	output CK125,
	output CK250,
	
	output reg [22:0] ROMA,				// 23-bit Tile ROM (B board) Address.
	
	output reg [16:0] GFX_RAM_ADDR,	// WORD address.
	
	input  wire [15:0] GFX_RAM_DO,		// Input FROM gfx RAM.
	output wire [15:0] GFX_RAM_DI		// Output TO gfx RAM.
);


reg [15:0] CPS1_OBJ_BASE;			// Base address of objects
reg [15:0] CPS1_SCROLL1_BASE;		// Base address of scroll 1
reg [15:0] CPS1_SCROLL2_BASE;		// Base address of scroll 2
reg [15:0] CPS1_SCROLL3_BASE;		// Base address of scroll 3
reg [15:0] CPS1_OTHER_BASE;		// Base address of other video
reg [15:0] CPS1_PALETTE_BASE;		// Base address of palette
reg [15:0] CPS1_SCROLL1_SCROLLX;	// Scroll 1 X
reg [15:0] CPS1_SCROLL1_SCROLLY;	// Scroll 1 Y
reg [15:0] CPS1_SCROLL2_SCROLLX;	// Scroll 2 X
reg [15:0] CPS1_SCROLL2_SCROLLY;	// Scroll 2 Y
reg [15:0] CPS1_SCROLL3_SCROLLX;	// Scroll 3 X
reg [15:0] CPS1_SCROLL3_SCROLLY;	// Scroll 3 Y
reg [15:0] CPS1_STARS1_SCROLLX;	// Stars 1 X
reg [15:0] CPS1_STARS1_SCROLLY;	// Stars 1 Y
reg [15:0] CPS1_STARS2_SCROLLX;	// Stars 2 X
reg [15:0] CPS1_STARS2_SCROLLY;	// Stars 2 Y
reg [15:0] CPS1_ROWSCROLL_OFFS;	// base of row scroll offsets in other RAM
reg [15:0] CPS1_VIDEOCONTROL;		// flip screen, rowscroll enable


always @(posedge CLK or negedge RESET_N)
if (!RESET_N) begin

end
else begin
	if (!CSB && !WRB) begin
		case (CA)
			24'h800100: CPS1_OBJ_BASE <= CDIN;
			24'h800102: CPS1_SCROLL1_BASE <= CDIN;
			24'h800104: CPS1_SCROLL2_BASE <= CDIN;
			24'h800106: CPS1_SCROLL3_BASE <= CDIN;
			24'h800108: CPS1_OTHER_BASE <= CDIN;
			24'h80010A: CPS1_PALETTE_BASE <= CDIN;
			24'h80010C: CPS1_SCROLL1_SCROLLX <= CDIN;
			24'h80010E: CPS1_SCROLL1_SCROLLY <= CDIN;
			24'h800110: CPS1_SCROLL2_SCROLLX <= CDIN;
			24'h800112: CPS1_SCROLL2_SCROLLY <= CDIN;
			24'h800114: CPS1_SCROLL3_SCROLLX <= CDIN;
			24'h800116: CPS1_SCROLL3_SCROLLY <= CDIN;
			24'h800118: CPS1_STARS1_SCROLLX <= CDIN;
			24'h80011A: CPS1_STARS1_SCROLLY <= CDIN;
			24'h80011C: CPS1_STARS2_SCROLLX <= CDIN;
			24'h80011E: CPS1_STARS2_SCROLLY <= CDIN;
			24'h800120: CPS1_ROWSCROLL_OFFS <= CDIN;
			24'h800122: CPS1_VIDEOCONTROL <= CDIN;
		default:;
		endcase
	end
end

wire [16:0] OBJ_GFX_BASE		= (CPS1_OBJ_BASE     & 10'h3C0) << 7;
wire [16:0] SCROLL1_GFX_BASE	= (CPS1_SCROLL1_BASE & 10'h3C0) << 7;
wire [16:0] SCROLL2_GFX_BASE	= (CPS1_SCROLL2_BASE & 10'h3C0) << 7;
wire [16:0] SCROLL3_GFX_BASE	= (CPS1_SCROLL3_BASE & 10'h3C0) << 7;
wire [16:0] OTHER_GFX_BASE		= (CPS1_OTHER_BASE   & 10'h3C0) << 7;


// Notes from MAME cps1.cpp...
//
// The A-board passes 23 bits of address to the B-board when requesting gfx ROM data.
// The B-board selects 64 bits of data, that is 16 4bpp pixels, and returns half of
// them depending on a signal from the C board.
// The 23 address bits are laid out this way (note that the top 3 bits select the
// tile type; the purpose of the top bit is unknown):
//
// sprite  000ccccccccccccccccyyyy
// scroll1 001?ccccccccccccccccyyy
// scroll2 010ccccccccccccccccyyyy
// scroll3 011ccccccccccccccyyyyyx
// stars   100000000sxxxxxyyyyyyyy (to be verified)
//
// where
// c is the tile code
// y is the y position in the tile
// x is the x position in the tile (only applicable to 32x32 tiles)
//


// On the Logic Analyser capture of a real CPS1 board running SF2, the sequence of the top bits of ROMA appear like this...
//
// 	HBLANK_N falling, then...
// 0	sprite
// 1	scroll1
// 2	scroll2
// 3	scroll3
// 4	stars
// 1	scroll1
// 2	scroll2
// 3	scroll3
//
// The sequence above repeats 16 times during each line.
// Each read can access 64 bits of tile ROM data, or 16 pixels per read.
//
// So 16 reads for the sprite and stars layers (256 pixels), and 32 reads for the scroll layers (512 pixels).
//
//
// Since there are twice as many accesses for scroll layers 1,2,3, they each read a total of 512 pixels per line.
//
// There are only half as many reads for the sprite and stars layers, so they can (in theory) only grab 256 pixels per line from the tile ROMs.
//

reg [1:0] layer_cnt;
reg stars_sel;

//wire cnt_reset = !RESET_N | !HBLANK_N;
wire cnt_reset = !RESET_N;

always @(posedge CLK or posedge cnt_reset)
if (cnt_reset) begin
	layer_cnt <= 2'd0;
	stars_sel <= 1'b0;
end
else begin
	layer_cnt <= layer_cnt + 1;
	if (layer_cnt==0) stars_sel <= ~stars_sel;
end


wire [7:0] x_cnt = PATT_X[7:0];	// TODO!
wire [7:0] y_cnt = PATT_Y[7:0];	// TODO!
reg s_bit = 1'b0;			// TODO!

always @* begin
	case (layer_cnt)
	0: begin ROMA = {stars_sel, layer_cnt, GFX_RAM_DO,		   y_cnt[3:0]};				 end	// sprite 	ROMA[22:0]=000ccccccccccccccccyyyy
	1: begin ROMA = {stars_sel, layer_cnt, 1'b0, GFX_RAM_DO, y_cnt[2:0]};				 end	// scroll1 	ROMA[22:0]=001?ccccccccccccccccyyy
	2: begin ROMA = {stars_sel, layer_cnt, GFX_RAM_DO,		   y_cnt[3:0]};				 end	// scroll2 	ROMA[22:0]=010ccccccccccccccccyyyy
	3: begin ROMA = {stars_sel, layer_cnt, GFX_RAM_DO[13:0], y_cnt[4:0], x_cnt[0]};	 end	// scroll3 	ROMA[22:0]=011ccccccccccccccyyyyyx
	4:	begin ROMA = {stars_sel, layer_cnt, 6'b000000, s_bit, x_cnt[4:0], y_cnt[7:0]}; end	// stars 	ROMA[22:0]=100000000sxxxxxyyyyyyyy
	default:;
	endcase
end



endmodule
