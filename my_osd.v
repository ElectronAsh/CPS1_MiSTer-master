//on screen display controller
module my_osd
(
	input	reset_n,			// reset_n
	
	input	pix_clk,		   // pixel clock
	
	input sys_clk,			// system clock
	
	input	hsync,				// start of video line
	input	vsync,				// start of video frame 
	
	input	[7:0] osd_ctrl,	// keycode for OSD control (Amiga keyboard codes + additional keys coded as values > 80h)
	
	input	_scs,				// SPI enable
	inout sdo,	 			// SPI data out
	input	sdi,		  		// SPI data in
	input	sck,	  			// SPI clock
	
	input wire [11:0] horbeam,
	input wire [11:0] verbeam,
	
	output	wire osdframe,		// osd overlay, normal video blank output
	
	output 	reg cont_disable = 0,	// Controller disable.
	output	reg osd_enable = 0,		// OSD enable.
		
	output	reg [1:0] cable_type = 3,	// Force 480p / 31KHz as default.
	//output	reg [1:0] cable_type = 0,	// Force 480i / 15KHz as default.
	
	output	reg [3:0] scanline_mode = 0,	// Scanlines OFF by default. (settings now saved in Flash on the ESP8266 / ESP32).
	
	output	reg [1:0] lr_filter = 0,
	output	reg [1:0] hr_filter = 0,
	
	input wire [23:0] rgb_in,
	output reg [23:0] rgb_out
);

// Local signals...

wire	[7:0] wrdat/*synthesis keep*/;		//osd buffer write data
reg 	[13:0] wraddr/*synthesis noprune*/;	//osd buffer write address
wire	osd_wren/*synthesis keep*/;			//osd buffer write enable

reg 	[7:0] paladdr/*synthesis keep*/;	//palette entry address
wire	pal_wren/*synthesis keep*/;		//palette entry write enable

reg	invert;					//invertion of highlighted line

reg	[31:0] palette [63:0]/*synthesis noprune*/;

reg	[8:0] attrib_wraddr;

reg	[2:0] pos_wraddr;
wire 	pos_wren;

reg	[11:0] frame_x/*synthesis noprune*/;
reg	[11:0] frame_y/*synthesis noprune*/;

reg	double_size = 0;

wire  osd_vsync = (verbeam==osd_vpos && hframe);

reg scroll_enable = 1;


// "audio_almost_empty" (bit [4]) goes High when there are less than 128 Bytes in the audio FIFO".
//
// "osdframe" (bit [3]) goes High during every line of the OSD window (and for the full width of the OSD window).
// (whether the OSD menu is active or not!)
//
// "osd_vsync" (bit [2]) goes High during only the first line of the OSD window (and for the full width of the OSD window).
// (whether the OSD menu is active or not!)
//
// "hsync" (bit [1]), and "vsync" (bit [0]) go High during the full H / V sync period (of the 480p video output), respectively.
//
wire [7:0] status = {3'b000, 1'b0, osdframe, osd_vsync, hsync, vsync}/*synthesis keep*/;

reg [7:0] int_mask = 8'h00;

reg [7:0] draw = 0;




//--------------------------------------------------------------------------------------
//OSD video generator
//--------------------------------------------------------------------------------------

reg [11:0] osd_hpos = 12'd320;
reg [11:0] osd_vpos = 12'd192;


/*
//horizontal part..
wire hframe = (double_size==0) ? (horbeam >= osd_hpos && horbeam < (osd_hpos+256) )			// 256 pixels wide.
						             : (horbeam >= osd_hpos-128 && horbeam < (osd_hpos+384) );	// 2X. (shift left by half the original 256, then count 256 pixels again.)
						
//vertical part..
wire vframe = (double_size==0) ? (verbeam >= osd_vpos && verbeam < (osd_vpos+128) )			// 128 lines tall.
										 : (verbeam >= osd_vpos-64 && verbeam < (osd_vpos+192) );	// 2X. (shift up by half the original 128, then count 128 lines again.)
*/


// OSD Window stuff...

// 256 pixels wide.
wire hframe_start = horbeam >= osd_hpos;
wire hframe_end = horbeam < osd_hpos+256;

// 128 pixels tall.
wire vframe_start = verbeam >= osd_vpos;
wire vframe_end = verbeam < osd_vpos+128;

wire hframe = hframe_start & hframe_end;
wire vframe = vframe_start & vframe_end;

assign osdframe = vframe & hframe;

reg osdframe_prev;
wire osdframe_rising = !osdframe_prev && osdframe;
wire osdframe_falling = osdframe_prev && !osdframe;



// SCROLL Window stuff...

// 512 pixels wide.
wire hgame_start = horbeam >= osd_hpos-128;
wire hgame_end = horbeam < osd_hpos+384;

// 512 pixels tall.
wire vgame_start = verbeam >= osd_vpos-64;
wire vgame_end = verbeam < osd_vpos+448;
										 
wire hgame = hgame_start & hgame_end;
wire vgame = vgame_start & vgame_end;

wire scrollframe = hgame & vgame;
										 
reg scrollframe_prev;
wire scrollframe_rising = !scrollframe_prev && scrollframe;
wire scrollframe_falling = scrollframe_prev && !scrollframe;



reg hsync_flag;

reg osd_vsync_prev;
wire osd_vsync_rising = !osd_vsync_prev && osd_vsync;

reg hsync_prev;
wire hsync_rising = !hsync_prev && hsync;

reg vsync_prev;
wire vsync_rising = !vsync_prev && vsync;


// combine..
reg osd_enabled;
reg scroll_enabled;
always @(posedge pix_clk or negedge reset_n)
if (!reset_n) begin


end
else begin
	osdframe_prev <= osdframe;
	scrollframe_prev <= scrollframe;
	
	osd_vsync_prev <= osd_vsync;
	
	hsync_prev <= hsync;
	vsync_prev <= vsync;

	if (vsync_rising) begin
		osd_enabled <= osd_enable;
		scroll_enabled <= scroll_enable;
		//scroll_x_vsync <= scroll_x;
		//scroll_y_vsync <= scroll_y;
		frame_y <= 12'd0;
	end

	if (hsync_rising) begin
		hsync_flag <= 1'b1;
		frame_x <= 12'd1;
	end
	
	if ( scrollframe ) begin
		frame_x <= frame_x + 1'd1;
	end
	
	if (hsync_flag && (scrollframe_falling&scroll_enabled) ) begin
		hsync_flag <= 1'b0;
		frame_y <= frame_y + 1'd1;
	end
	
/*
	if (rx && cmd && spicmd==4'b1010) interrupt <= 1'b0;	// Clear the interrupt reg when the STATUS byte is read!
	else interrupt <= (int_mask[4]&audio_almost_empty) | 	// Else, set the interrupt based on the mask bits AND rising pulses)...
							(int_mask[3]&osdframe_rising) | 
							(int_mask[2]&osd_vsync_rising) | 
							(int_mask[1]&hsync_rising) | 
							(int_mask[0]&vsync_rising);
*/
end

//assign COLDRESET_N = (!int_mask[7]) ? 1'b0 : 1'bz;
assign COLDRESET_N = int_mask[7];


//--------------------------------------------------------------------------------------
//video buffer
//--------------------------------------------------------------------------------------

//  RRRR_TTTTT_AAA_BB
//  DCBA9_8765432_10	<- bit of patt_addr.
//  XXXXX_YYYYYYY_XX
//  76543_6543210_21 <- bits of frame_x,y,x
//
// 32 tiles wide by 16 tiles tall (256x128)...
//
// Drawing the tiles DOWN each COLUMN...
//
//wire [13:0] patt_addr = {frame_x[7:3],frame_y[6:0],frame_x[2:1]};



//  RRRR = Selects each new "ROW" of tiles from VRAM.
//
//  TTTTT = Selects each "TILE" along a row.
//
//  BB = Selects each Byte (0-3) of a tile row.
//
//  AAA = Selects each "row" within the current tile.
//
//  RRRR_TTTTT_AAA_BB
//  DCBA_98765_432_10 <- bit of patt_addr.
//  YYYY_XXXXX_YYY_XX
//  6543_76543_210_21 <- bits of frame_y,x,y,x
//
// 32 tiles wide by 16 tiles tall (256x128)...
//
// Drawing the tiles ALONG each ROW...
//
//wire [13:0] patt_addr = {frame_y[6:3],frame_x[7:3],frame_y[2:0],frame_x[2:1]};

reg [11:0] scroll_x = 0;
reg [11:0] scroll_y = 0;

//reg [11:0] scroll_x_vsync = 0;
//reg [11:0] scroll_y_vsync = 0;
//wire [11:0] frame_x_scroll = frame_x + scroll_x_vsync/*synthesis keep*/;
//wire [11:0] frame_y_scroll = frame_y + scroll_y_vsync/*synthesis keep*/;

//wire [11:0] frame_x_scroll = frame_x/*synthesis keep*/;
//wire [11:0] frame_y_scroll = frame_y/*synthesis keep*/;
wire [11:0] frame_x_scroll = frame_x[11:2]/*synthesis keep*/;
wire [11:0] frame_y_scroll = frame_y[11:2]/*synthesis keep*/;


reg [7:0] wrdat_upper/*synthesis noprune*/;
/*wire [11:0] scroll_a_rdaddr = (osdframe) ? { frame_y[9:4], frame_x[8:3] } : 
														 { verbeam[9:4], horbeam[8:3] };*/

wire [10:0] scroll_a_rdaddr = { frame_y_scroll[7:3], frame_x_scroll[8:3] };


wire [31:0] scroll_a_data/*synthesis keep*/;
reg scroll_a_select_byte;
scroll_buf	scroll_buf_a (
	.clock ( pix_clk ),
	.data ( {wrdat_upper, wrdat} ),
	.rdaddress ( scroll_a_rdaddr ),
	.wraddress ( wraddr[12:1] ),
	.wren ( scroll_a_wren ),
	.q ( scroll_a_data )
);



//reg [11:0] scroll_b_rdaddr/*synthesis keep*/;
//wire [15:0] scroll_b_data/*synthesis keep*/;
/*
scroll_buf	scroll_buf_b (
	.clock ( pix_clk ),
	.data ( {wrdat_upper, wrdat} ),
	.rdaddress ( scroll_b_rdaddr ),
	.wraddress ( wraddr[12:1] ),
	.wren ( scroll_b_wren ),
	.q ( scroll_b_data )
);
*/

//  RRRR = Selects each new "ROW" of tiles from VRAM.
//
//  TTTTT = Selects each "TILE" along a row.
//
//  BB = Selects each Byte (0-3) of a tile row.
//
//  AAA = Selects each "row" within the current tile.
//
//  RRRR_TTTTT_AAA_BB
//  DCBA_98765_432_10 <- bit of patt_addr.
//  YYYY_XXXXX_YYY_XX
//  8765_43210_210_21 <- bits of scroll_a_data, y, x	
//						

//wire [13:0] patt_addr = { scroll_a_data[8:0] , frame_y_scroll[2:0], frame_x_scroll[2:1] };

	
//wire [13:0] patt_addr = (scroll_enabled) ? { scroll_a_data[23:16],scroll_a_data[31:24] , frame_y_scroll[2:0], frame_x_scroll[2:1] } :
//								(double_size==0) ? { frame_y_scroll[6:3], frame_x_scroll[7:3], frame_y_scroll[2:0], frame_x_scroll[2:1] }
//													  : { frame_y_scroll[7:4], frame_x_scroll[8:4], frame_y_scroll[3:1], frame_x_scroll[3:2] };

// TESTING!! - View tiles directly from tile ROM (osdbuf).
//wire [13:0] patt_addr = {frame_y_scroll[10:3], frame_x_scroll[8:3]};

//wire [13:0] patt_addr = { frame_y_scroll[6:3], frame_x_scroll[7:3], frame_y_scroll[2:0], frame_x_scroll[2:1] };


//wire [13:0] patt_addr = { frame_x_scroll[6], frame_y_scroll[5:0], frame_x_scroll[4:3],1'b0,frame_x_scroll[2:1] };

//wire [13:0] patt_addr = { frame_x_scroll[7], frame_y_scroll[5:0], frame_x_scroll[6:2] };
wire [13:0] patt_addr = { frame_y_scroll[8:0], frame_x_scroll[5:1],3'b000 };


//	Select the upper or lower nibble depending on frame_x_scroll[0] (ie. frame_x_scroll = Even or Odd)...
//
//  Pixel: 01234567
//   Byte: 00112233
// Nibble: ULULULUL
// 
wire [3:0] pal_entry = (!frame_x_scroll[0]) ? osdbuf_data_out[7:4] : osdbuf_data_out[3:0]/*synthesis keep*/;


// OSD PATTERN Buffer (16384*8 Dual-port)
wire [7:0] osdbuf_data_out;
osdbuf	osdbuf_inst (
	.clock ( pix_clk ),
	.data ( wrdat ),
	.rdaddress ( patt_addr ),
	.wraddress ( wraddr ),
	.wren ( osd_wren ),
	.q ( osdbuf_data_out )
);


wire [7:0] attrib_data_out;
att_buf	att_buf_inst (
	.clock ( pix_clk ),
	.data ( wrdat ),
	.rdaddress ( patt_addr[13:5] ),
	.wraddress ( attrib_wraddr ),
	.wren ( attrib_wren ),
	.q ( attrib_data_out )
);


/*
wire [1:0] pal_select = (scroll_enabled) ? scroll_a_data[14:13] : attrib_data_out[1:0];

wire [31:0] pal_pixel = (pal_entry==0) ? palette[ (pal_select*16)+0 ] :
								(pal_entry==1) ? palette[ (pal_select*16)+1 ] :
								(pal_entry==2) ? palette[ (pal_select*16)+2 ] :
								(pal_entry==3) ? palette[ (pal_select*16)+3 ] :
								(pal_entry==4) ? palette[ (pal_select*16)+4 ] :
								(pal_entry==5) ? palette[ (pal_select*16)+5 ] :
								(pal_entry==6) ? palette[ (pal_select*16)+6 ] :
								(pal_entry==7) ? palette[ (pal_select*16)+7 ] :
								(pal_entry==8) ? palette[ (pal_select*16)+8 ] :
								(pal_entry==9) ? palette[ (pal_select*16)+9 ] :
								(pal_entry==10) ? palette[ (pal_select*16)+10 ] :
								(pal_entry==11) ? palette[ (pal_select*16)+11 ] :
								(pal_entry==12) ? palette[ (pal_select*16)+12 ] :
								(pal_entry==13) ? palette[ (pal_select*16)+13 ] :
								(pal_entry==14) ? palette[ (pal_select*16)+14 ] :
														palette[ (pal_select*16)+15 ];
*/

wire [31:0] pal_pixel = (pal_entry==0)  ? 32'h00_44_44_44 :
								(pal_entry==1)  ? 32'h00_FF_DD_99 :
								(pal_entry==2)  ? 32'h00_FF_BB_88 :
								(pal_entry==3)  ? 32'h00_EE_99_77 :
								(pal_entry==4)  ? 32'h00_CC_88_66 :
								(pal_entry==5)  ? 32'h00_99_66_55 :
								(pal_entry==6)  ? 32'h00_66_44_33 :
								(pal_entry==7)  ? 32'h00_BB_00_00 :
								(pal_entry==8)  ? 32'h00_FF_FF_FF :
								(pal_entry==9)  ? 32'h00_EE_EE_CC :
								(pal_entry==10) ? 32'h00_DD_CC_AA :
								(pal_entry==11) ? 32'h00_BB_AA_88 :
								(pal_entry==12) ? 32'h00_AA_88_77 :
								(pal_entry==13) ? 32'h00_88_66_CC :
								(pal_entry==14) ? 32'h00_77_66_55 :
														32'h00_00_11_FF;
						
wire [7:0] r_in = rgb_in[23:16];
wire [7:0] g_in = rgb_in[15:8];
wire [7:0] b_in = rgb_in[7:0];

wire [7:0] alpha = pal_pixel[31:24];
wire [7:0] r_pal = pal_pixel[23:16];
wire [7:0] g_pal = pal_pixel[15:8];
wire [7:0] b_pal = pal_pixel[7:0];


// Standard Alpha blending equation...
//
// opacity*original + (1-opacity)*background = resulting pixel
//
// Or...
//
// out = alpha * new + (1 - alpha) * old
//
// Or, the integer version, which we're using...
// 
//wire [7:0] ar = (r_pal * alpha + r_in * (255 - alpha)) / 255;
//wire [7:0] ag = (g_pal * alpha + g_in * (255 - alpha)) / 255;
//wire [7:0] ab = (b_pal * alpha + b_in * (255 - alpha)) / 255;


//always @(*) rgb_out <= /*(!osdframe & draw>0) ? {draw[7:5],5'b00000, draw[4:2],5'b00000, draw[1:0],6'b000000} :*/
											/*(scrollframe & scroll_enabled) ? pal_pixel[23:0] :
											(osdframe & osd_enabled & alpha>0) ? {ar, ag, ab} :
											rgb_in;*/


always @(*) rgb_out = (osdframe | scrollframe) ? pal_pixel : rgb_in;


// OSD SPI commands:
//
// 0x0X - 8'b0000_0000  READ FPGA Status byte(s) / NOP.
// 0x1X - 8'b0001_RRRR  Write to Attribute Buffer. Starting on tile row <RRRR>. Auto-increments.
// 0x2X - 8'b0010_RRRR  Write to OSD Pixel / Pattern buffer. Starting on tile row <RRRR>. Auto-increments.
// 0x3X - 8'b0011_0PPP  Write to Palette (select a palette 0-3 using the lower bits).
// 0x4X - 8'b0100_SDCO  Enable the SCROLL window (S). Double-size the OSD window (D). Disable Dreamcast controller (C). Enable OSD display (O).
// 0x5X - 8'b0101_00AA  Set AV cable forcing type (AA).
// 0x6X - 8'b0110_SSSS  Set Scanline mode
// 0x7X - 8'b0111_0000  hr_filter,lr_filter bits in [1:0].
//
// 0x8X - 8'b1000_0000  OSD H / V Position. (four bytes follow), then the X/Y scroll values in the last byte [7:4] and [3:0].
// 0x9X - 8'b1001_0000	Read Maple bus / DC controller bytes.
// 0xAX - 8'b1010_0000	Send Audio (8-bit) via HDMI! :)
// 0xBX - 8'b1011_0000	Write to Interrupt Mask reg. (MSB bit is N64 COLDRESET_N.)
// 0xCX - 8'b1100_0000	Force pixel colour on screen (gets displayed if > 0);
// 0xDX - 8'b1101_0000	Write to Scroll_A table.
// 0xEX - 8'b1110_0000  Write to Scroll_B table.
// 0xF0 - 8'b1111_0000  READ from GD Emu register / buffer byte. Single byte!
// 0xF1 - 8'b1111_0001  WRITE to GD Emu register / buffer. Single byte!
// 0xF2 - 8'b1111_0010  READ from GD Emu registers / buffers. Multiple Bytes / Auto-Increment.
// 0xF3 - 8'b1111_0011  WRITE to GD Emu registers / buffers. Multiple Bytes / Auto-Increment.
//

always @(posedge sys_clk or negedge reset_n)
if (!reset_n) begin

end
else begin

	// Latch the command
	if (rx && cmd) spicmd <= wrdat[7:4];

	// Read FPGA Status byte...
	//if (rx && cmd && wrdat[7:4]==4'b0000) maple_count <= 4'd0;
	//else if (rx) maple_count <= maple_count + 4'd1;	//increment for every data byte that (goes out).


	// Attrib Buffer write control.
	if (rx && cmd && wrdat[7:4]==4'b0001) attrib_wraddr <= {wrdat[3:0],5'b00000};	// Set the starting TILE ROW (0-15) using SPI CMD bits [3:0].
	else if (rx && ~cmd && spicmd == 4'b0001) attrib_wraddr <= attrib_wraddr + 9'd1;	//increment for every data byte that comes in
	
	// OSD Tile / pixel buffer write control (write to row <RRRR> command).
	if (rx && cmd && wrdat[7:4]==4'b0010) wraddr <= {wrdat[3:0],10'b0000000000};	// Set the starting TILE ROW (0-15) using SPI CMD bits [3:0].
	else if (rx && ~cmd && spicmd == 4'b0010) wraddr <= wraddr + 14'd1;	//increment for every data byte that comes in
	
	// Scroll_A write control.
	if (rx && cmd && wrdat[7:4]==4'b1101) wraddr <= 0;
	else if (rx && ~cmd && spicmd == 4'b1101) wraddr <= wraddr + 14'd1;	//increment for every data byte that comes in
	
	// Scroll_B write control.
	if (rx && cmd && wrdat[7:4]==4'b1110) wraddr <= 0;
	else if (rx && ~cmd && spicmd == 4'b1110) wraddr <= wraddr + 14'd1;	//increment for every data byte that comes in
	
	// Palette writing control.
	if (rx && cmd && wrdat[7:4]==4'b0011) paladdr <= {wrdat[1:0],6'b0000_00};	// Zero paladdr when palette cmd seen...
	else if (pal_wren) begin
		case (paladdr[1:0])
			0: palette[ paladdr[7:2] ][31:24] <= wrdat;	// ALPHA. Write MSB byte first.
			1: palette[ paladdr[7:2] ][23:16] <= wrdat;	// RED
			2: palette[ paladdr[7:2] ][15:8]  <= wrdat;	// GREEN
			3: palette[ paladdr[7:2] ][7:0]	 <= wrdat;	// BLUE
			default:;
		endcase
		paladdr <= paladdr + 4'd1;
	end
	
	// Double-size the OSD, Dreamcast controller Disable / enable, and OSD Enable.
	if (rx && cmd && wrdat[7:4]==4'b0100) {scroll_enable, double_size, cont_disable, osd_enable} <= wrdat[3:0];

	// AV cable type.
	if (rx && cmd && wrdat[7:4]==4'b0101) cable_type <= wrdat[1:0];
	
	// Scanline mode.
	if (rx && cmd && wrdat[7:4]==4'b0110) scanline_mode <= wrdat[3:0];

	// Horizontal / Vertical Filters...
	if (rx && cmd && wrdat[7:4]==4'b0111) {hr_filter,lr_filter} <= wrdat[3:0];
	
	// OSD H / V Position. And Scroll X / Scroll Y...
	if (rx && cmd && wrdat[7:4]==4'b1000) pos_wraddr <= 3'b000;
	else if (pos_wren) begin
		case (pos_wraddr)
			0: osd_hpos[11:8] <= wrdat[3:0];
			1: osd_hpos[7:0]  <= wrdat;
			2: osd_vpos[11:8] <= wrdat[3:0];
			3: osd_vpos[7:0]  <= wrdat;
			4: scroll_x[11:8] <= wrdat[3:0];
			5: scroll_x[7:0] 	<= wrdat;
			6: scroll_y[11:8] <= wrdat[3:0];
			7: scroll_y[7:0] 	<= wrdat;
			default:;
		endcase
		pos_wraddr <= pos_wraddr + 3'd1;
	end
	
end


wire attrib_wren 	= (rx && ~cmd && spicmd==4'b0001);
assign osd_wren   = (rx && ~cmd && spicmd==4'b0010);
assign pal_wren   = (rx && ~cmd && spicmd==4'b0011);

wire scroll_a_wren = (rx && ~cmd && spicmd==4'b1101 && wraddr[0])/*synthesis keep*/;		// Write BOTH bytes when the address is ODD.
wire scroll_b_wren = (rx && ~cmd && spicmd==4'b1110 && wraddr[0])/*synthesis keep*/;		// Write BOTH bytes when the address is ODD.

assign pos_wren   	= (rx && ~cmd && spicmd==4'b1000);

assign audio_fifo_reset = (rx && cmd && spicmd==4'b1010);
assign audio_wrreq = (rx && ~cmd && spicmd==4'b1010);


/*
wire [7:0] spi_in_mux = (spicmd==4'b0000) ? status :
								(spicmd==4'b1111) ? gd_module_read :
								(spicmd==4'b1001 && maple_count==0) ? maple_reg_0 :
								(spicmd==4'b1001 && maple_count==1) ? maple_reg_1 :
								(spicmd==4'b1001 && maple_count==2) ? maple_reg_2 :
								(spicmd==4'b1001 && maple_count==3) ? maple_reg_3 :
								(spicmd==4'b1001 && maple_count==4) ? maple_reg_4 :
								(spicmd==4'b1001 && maple_count==5) ? maple_reg_5 :
								(spicmd==4'b1001 && maple_count==6) ? maple_reg_6 :
								(spicmd==4'b1001 && maple_count==7) ? maple_reg_7 :
								(spicmd==4'b1001 && maple_count==8) ? maple_reg_8 :
								(spicmd==4'b1001 && maple_count==9) ? maple_reg_9 :
								(spicmd==4'b1001 && maple_count==10) ? maple_reg_10 :
								(spicmd==4'b1001 && maple_count==11) ? maple_reg_11 :
								(spicmd==4'b1001 && maple_count==12) ? maple_reg_12 :
								(spicmd==4'b1001 && maple_count==13) ? maple_reg_13 :
								(spicmd==4'b1001 && maple_count==14) ? maple_reg_14 : maple_reg_15;
*/

wire [7:0] spi_in_mux = status;


//--------------------------------------------------------------------------------------
//interface to host
//--------------------------------------------------------------------------------------
wire	rx;
wire	cmd;
reg 	[3:0] spicmd;		//spi command

reg load_late = 0;

//instantiate spi interface
spi8 spi0
(
	.clk( sys_clk ),
	._scs( _scs ),
	.sdi( sdi ),
	.sdo( sdo ),
	.sck( sck ),
	.in( spi_in_mux ),
	.out( wrdat[7:0] ),
	.rx( rx ),
	.cmd( cmd )
);

endmodule

//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------

//SPI interface module (8 bits)
//this is a slave module, clock is controlled by host
//clock is high when bus is idle
//ingoing data is sampled at the positive clock edge
//outgoing data is shifted/changed at the negative clock edge
//msb is sent first
//         ____   _   _   _   _
//sck   ->    |_| |_| |_| |_|
//data   ->     777 666 555 444
//sample ->      ^   ^   ^   ^
//strobe is asserted at the end of every byte and signals that new data must
//be registered at the out output. At the same time, new data is read from the in input.
//The data at input in is also sent as the first byte after _scs is asserted (without strobe!). 
module spi8
(
	input clk,			// pixel clock
	input	_scs,			// SPI chip select
	input	sdi,			// SPI data in
	inout sdo,			// SPI data out
	input	sck,			// SPI clock
	input	[7:0] in,	// parallel input data
	output [7:0] out,	// parallel output data
	output reg rx,		// byte received
	output reg cmd,		// first byte received
	output wire load_late
);

//locals
reg [2:0] bit_cnt;	//bit counter
reg [7:0] sdi_reg;	//input shift register	(rising edge of SPI clock)
reg [7:0] sdo_reg;	//output shift register	 (falling edge of SPI clock)

reg new_byte;			//new byte (8 bits) received
reg rx_sync;			//synchronization to clk (first stage)
reg first_byte;		//first byte is going to be received

//------ input shift register ------//
always @(posedge sck) sdi_reg <= {sdi_reg[6:0],sdi};

assign out = sdi_reg;

//------ receive bit counter ------//
always @(posedge sck or posedge _scs)
	if (_scs) bit_cnt <= 0;					//always clear bit counter when CS is not active
	else bit_cnt <= bit_cnt + 3'd1;		//increment bit counter when new bit has been received

//----- rx signal ------//
//this signal goes high for one clk clock period just after new byte has been received
//it's synchronous with clk, output data shouldn't change when rx is active
always @(posedge sck or posedge rx)
	if (rx) new_byte <= 0;		//cleared asynchronously when rx is high (rx is synchronous with clk)
	else if (bit_cnt == 3'd7) new_byte <= 1;		//set when last bit of a new byte has been just received

always @(negedge clk) rx_sync <= new_byte;	//double synchronization to avoid metastability

	
reg sck_1, sck_2;
wire sck_falling = (sck_2 & !sck_1);
always @(posedge clk) begin
	sck_1 <= sck;
	sck_2 <= sck_1;

	rx <= rx_sync;			//synchronous with clk

	if (sck_falling | load_late) begin		// Needed an extra clock delay after the falling edge of SCK due before latching the OUTPUT data (to the IDE buffer output delay). OzOnE.
		if (bit_cnt == 3'd0) sdo_reg <= in;
		else sdo_reg <= {sdo_reg[6:0],1'b0};
	end
end

//------ cmd signal generation ------//
//this signal becomes active after reception of first byte
//when any other byte is received it's deactivated indicating data bytes
always @(posedge sck or posedge _scs)
	if (_scs) first_byte <= 1'b1;		//set when CS is not active
	else if (bit_cnt == 3'd7) first_byte <= 1'b0;		//cleared after reception of first byte

always @(posedge sck)
	if (bit_cnt == 3'd7) cmd <= first_byte;		//active only when first byte received
	
//------ serial data output register ------//
//always @(negedge sck)		//output change on falling SPI clock
//	if (bit_cnt == 3'd0) sdo_reg <= in;
//	else sdo_reg <= {sdo_reg[6:0],1'b0};

//------ SPI output signal ------//
//assign sdo = ~_scs & sdo_reg[7];	//force HIGH-Z if SPI not selected
assign sdo = (!_scs) ? sdo_reg[7] : 1'bz;

endmodule
