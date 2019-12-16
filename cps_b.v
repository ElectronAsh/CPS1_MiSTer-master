//
// Prelim CPS-A custom chip logic.
//
// ElectronAsh. 2019.
//
//
module cps_b (
	input RESET_N,
	
	input CLK_16M,
  
	input CSB,			// Chip Select (active-Low).
	input WRB,			// Write enable (active-Low).
	
	inout  [5:1] CA,		// 68000 bus address.
	input  [15:0] CDIN,	// 68000 bus data in.
	output [15:0] CDOUT,	// 68000 bus data in.
	
	output CK500,	// 2 MHz. (used to SELect the upper or lower 32-bits from each 64-bit wide tile ROM access!)
	
	input [31:0] TILE_ROM_DATA,
	
	input LI,
	input FI,
	
	input [22:20] ROMA
);

reg [31:0] sprites_buf_0 [0:31];		// 32 words, 256 pixels.
reg [31:0] scroll1_buf_0 [0:63];		// 64 words, 512 pixels
reg [31:0] scroll2_buf_0 [0:63];		// 64 words, 512 pixels
reg [31:0] scroll3_buf_0 [0:63];		// 64 words, 512 pixels
reg [31:0]   stars_buf_0 [0:31];		// 32 words, 256 pixels.


reg [31:0] sprites_buf_1 [0:31];		// 32 words, 256 pixels.
reg [31:0] scroll1_buf_1 [0:63];		// 64 words, 512 pixels
reg [31:0] scroll2_buf_1 [0:63];		// 64 words, 512 pixels
reg [31:0] scroll3_buf_1 [0:63];		// 64 words, 512 pixels
reg [31:0]   stars_buf_1 [0:31];		// 32 words, 256 pixels.


reg [2:0] clk_div;
always @(posedge CLK_16M or negedge RESET_N)
if (!RESET_N) begin
	clk_div <= 3'd0;
end
else begin
	clk_div <= clk_div + 1;
end

assign CK500 = clk_div[2];	// 2 MHz.
wire PIX_CLK = clk_div[0];	// 8 MHz.

reg [8:0] addr;

reg buf_sel;

reg [31:0] sprites_buf_do;
reg [31:0] scroll1_buf_do;
reg [31:0] scroll2_buf_do;
reg [31:0] scroll3_buf_do;
reg [31:0]   stars_buf_do;

reg [3:0] sprites_pix;
reg [3:0] scroll1_pix;
reg [3:0] scroll2_pix;
reg [3:0] scroll3_pix;
reg [3:0]   stars_pix;


always @(posedge PIX_CLK or negedge RESET_N)	// PIX_CLK = 8 MHz.
if (!RESET_N) begin
	addr <= 9'd0;
	buf_sel <= 1'b0;
end
else begin
	if (LI) begin				// LINE (HSync) pulse, but only for one clock cycle.
		buf_sel <= !buf_sel;
		addr <= 9'd0;
	end
	else begin
		if ( addr<512 ) addr <= addr + 1;
	
		// Line buffer writing...
		case (ROMA[22:20])
			//3'b000: if (!buf_sel) sprites_buf_0[ addr[8:4] ] <= TILE_ROM_DATA; else sprites_buf_1[ addr[8:4] ] <= TILE_ROM_DATA;	// 256 pixels!
			3'b001: if (!buf_sel) scroll1_buf_0[ addr[8:3] ] <= TILE_ROM_DATA; else scroll1_buf_1[ addr[8:3] ] <= TILE_ROM_DATA;	// 512 pixels!
			3'b010: if (!buf_sel) scroll2_buf_0[ addr[8:3] ] <= TILE_ROM_DATA; else scroll2_buf_1[ addr[8:3] ] <= TILE_ROM_DATA;	// 512 pixels!
			3'b011: if (!buf_sel) scroll3_buf_0[ addr[8:3] ] <= TILE_ROM_DATA; else scroll3_buf_1[ addr[8:3] ] <= TILE_ROM_DATA;	// 512 pixels!
			//3'b100: if (!buf_sel)   stars_buf_0[ addr[8:4] ] <= TILE_ROM_DATA; else   stars_buf_1[ addr[8:4] ] <= TILE_ROM_DATA;	// 256 pixels!	
			default:;
		endcase
	

		// Line buffer reading...	
		//sprites_buf_do <= (!buf_sel) ? sprites_buf_1[ addr[8:4] ] : sprites_buf_0[ addr[8:4] ];	// buf0 and buf1 are swapped vs writes.	// 256 pixels!
		scroll1_buf_do <= (!buf_sel) ? scroll1_buf_1[ addr[8:3] ] : scroll1_buf_0[ addr[8:3] ];	// buf0 and buf1 are swapped vs writes.	// 512 pixels!
		scroll2_buf_do <= (!buf_sel) ? scroll2_buf_1[ addr[8:3] ] : scroll2_buf_0[ addr[8:3] ];	// buf0 and buf1 are swapped vs writes.	// 512 pixels!
		scroll3_buf_do <= (!buf_sel) ? scroll3_buf_1[ addr[8:3] ] : scroll3_buf_0[ addr[8:3] ];	// buf0 and buf1 are swapped vs writes.	// 512 pixels!
		  //stars_buf_do <= (!buf_sel) ?   stars_buf_1[ addr[8:4] ] :   stars_buf_0[ addr[8:4] ];	// buf0 and buf1 are swapped vs writes.	// 256 pixels!

	
		case (addr[2:0])
		3'd0: begin
			//sprites_pix <= sprites_buf_do[31:28];
			scroll1_pix <= scroll1_buf_do[31:28];
			scroll2_pix <= scroll2_buf_do[31:28];
			scroll3_pix <= scroll3_buf_do[31:28];
			  //stars_pix <=   stars_buf_do[31:28];
		end
		3'd1: begin
			//sprites_pix <= sprites_buf_do[27:24];
			scroll1_pix <= scroll1_buf_do[27:24];
			scroll2_pix <= scroll2_buf_do[27:24];
			scroll3_pix <= scroll3_buf_do[27:24];
			  //stars_pix <=   stars_buf_do[27:24];
		end
		3'd2: begin
			//sprites_pix <= sprites_buf_do[23:20];
			scroll1_pix <= scroll1_buf_do[23:20];
			scroll2_pix <= scroll2_buf_do[23:20];
			scroll3_pix <= scroll3_buf_do[23:20];
			  //stars_pix <=   stars_buf_do[23:20];
		end
		3'd3: begin
			//sprites_pix <= sprites_buf_do[19:16];
			scroll1_pix <= scroll1_buf_do[19:16];
			scroll2_pix <= scroll2_buf_do[19:16];
			scroll3_pix <= scroll3_buf_do[19:16];
			  //stars_pix <=   stars_buf_do[19:16];
		end
		3'd4: begin
			//sprites_pix <= sprites_buf_do[15:12];
			scroll1_pix <= scroll1_buf_do[15:12];
			scroll2_pix <= scroll2_buf_do[15:12];
			scroll3_pix <= scroll3_buf_do[15:12];
			  //stars_pix <=   stars_buf_do[15:12];
		end
		3'd5: begin
			//sprites_pix <= sprites_buf_do[11:8];
			scroll1_pix <= scroll1_buf_do[11:8];
			scroll2_pix <= scroll2_buf_do[11:8];
			scroll3_pix <= scroll3_buf_do[11:8];
			  //stars_pix <=   stars_buf_do[11:8];
		end
		3'd6: begin
			//sprites_pix <= sprites_buf_do[7:4];
			scroll1_pix <= scroll1_buf_do[7:4];
			scroll2_pix <= scroll2_buf_do[7:4];
			scroll3_pix <= scroll3_buf_do[7:4];
			  //stars_pix <=   stars_buf_do[7:4];
		end
		3'd7: begin
			//sprites_pix <= sprites_buf_do[3:0];
			scroll1_pix <= scroll1_buf_do[3:0];
			scroll2_pix <= scroll2_buf_do[3:0];
			scroll3_pix <= scroll3_buf_do[3:0];
			  //stars_pix <=   stars_buf_do[3:0];
		end
		default:;
		endcase
	end
end



endmodule
