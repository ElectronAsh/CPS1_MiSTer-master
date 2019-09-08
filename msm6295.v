// OKI / MSM6295 ADPCM core.
//
// ElectronAsh (Ash Evans) 2018.
//
//

module msm6295 (
	input RESET_N,
	
	input CLK,
	
	inout [7:0] CPU_DI,
	
	output [7:0] CPU_DO,
	
	input CS_N,
	
	input RD_N,
	input WR_N,
	
	input SS,		// Select sampling rate (start value for the counter).
	
	output reg [17:0] ROM_ADDR,
	
	input [7:0] ROM_DATA,
	
	output wire signed [21:0] SOUND_OUT,
	
	output reg [3:0] V1_STATE,
	
	output reg [2:0] MAIN_STATE,
	
	output reg [17:0] V1_SA,
	output reg [17:0] V1_EA,
	
	output reg V1_GATE, V2_GATE, V3_GATE, V4_GATE,
	
	output wire WR_N_RISING,
	
	output reg WRITE_STATE,
	
	output wire [7:0] CPU_DI_DBG,
	
	output wire [3:0] V1_NIB,
	output wire [3:0] V2_NIB,
	output wire [3:0] V3_NIB,
	output wire [3:0] V4_NIB,

	output reg signed [17:0] V1_SAMP_OUT,
	output reg signed [17:0] V2_SAMP_OUT,
	output reg signed [17:0] V3_SAMP_OUT,
	output reg signed [17:0] V4_SAMP_OUT,
	
	output reg signed [12:0] V1_SIGNAL,
	output reg signed [12:0] V2_SIGNAL,
	output reg signed [12:0] V3_SIGNAL,
	output reg signed [12:0] V4_SIGNAL,
	
	output reg SAMP_PULSE
);

wire signed [21:0] SOUND_MIX = {V1_SAMP_OUT[17],V1_SAMP_OUT} + {V2_SAMP_OUT[17],V2_SAMP_OUT} + {V3_SAMP_OUT[17],V3_SAMP_OUT} + {V4_SAMP_OUT[17],V4_SAMP_OUT};
assign SOUND_OUT = SOUND_MIX;


assign CPU_DI_DBG = CPU_DI;


//assign CPU_DO = (!CS_N && !RD_N) ? {4'hF, V4_GATE, V3_GATE, V2_GATE, V1_GATE} : 8'hzz;
`ifndef VERILATOR 
assign CPU_DO = {4'b1111, V4_GATE, V3_GATE, V2_GATE, V1_GATE};
`endif


// Limited these to 6 bits, since the maximum value is 0x20 for the volumes.
//
// These don't need to be signed to multiply with the SIGNAL_OUT stuff, since volumes never go negative.
//
wire signed [6:0] V1_VOL_MUL =  (V1_ATTEN==4'd0) ? 8'h20 :   //   0 dB
						 (V1_ATTEN==4'd1) ? 8'h16 :   //  -3.2 dB
						 (V1_ATTEN==4'd2) ? 8'h10 :   //  -6.0 dB
						 (V1_ATTEN==4'd3) ? 8'h0B :   //  -9.2 dB
						 (V1_ATTEN==4'd4) ? 8'h08 :   // -12.0 dB
						 (V1_ATTEN==4'd5) ? 8'h06 :   // -14.5 dB
						 (V1_ATTEN==4'd6) ? 8'h04 :   // -18.0 dB
						 (V1_ATTEN==4'd7) ? 8'h03 :   // -20.5 dB
						 (V1_ATTEN==4'd8) ? 8'h02 :   // -24.0 dB
							8'h00;	// All other values (9-15) are zero.
										
wire signed [6:0] V2_VOL_MUL =  (V2_ATTEN==4'd0) ? 8'h20 :   //   0 dB
						 (V2_ATTEN==4'd1) ? 8'h16 :   //  -3.2 dB
						 (V2_ATTEN==4'd2) ? 8'h10 :   //  -6.0 dB
						 (V2_ATTEN==4'd3) ? 8'h0B :   //  -9.2 dB
						 (V2_ATTEN==4'd4) ? 8'h08 :   // -12.0 dB
						 (V2_ATTEN==4'd5) ? 8'h06 :   // -14.5 dB
						 (V2_ATTEN==4'd6) ? 8'h04 :   // -18.0 dB
						 (V2_ATTEN==4'd7) ? 8'h03 :   // -20.5 dB
						 (V2_ATTEN==4'd8) ? 8'h02 :   // -24.0 dB
							8'h00;	// All other values (9-15) are zero.
										
wire signed [6:0] V3_VOL_MUL =  (V3_ATTEN==4'd0) ? 8'h20 :   //   0 dB
						 (V3_ATTEN==4'd1) ? 8'h16 :   //  -3.2 dB
						 (V3_ATTEN==4'd2) ? 8'h10 :   //  -6.0 dB
						 (V3_ATTEN==4'd3) ? 8'h0B :   //  -9.2 dB
						 (V3_ATTEN==4'd4) ? 8'h08 :   // -12.0 dB
						 (V3_ATTEN==4'd5) ? 8'h06 :   // -14.5 dB
						 (V3_ATTEN==4'd6) ? 8'h04 :   // -18.0 dB
						 (V3_ATTEN==4'd7) ? 8'h03 :   // -20.5 dB
						 (V3_ATTEN==4'd8) ? 8'h02 :   // -24.0 dB
							8'h00;	// All other values (9-15) are zero.
										
wire signed [6:0] V4_VOL_MUL =  (V4_ATTEN==4'd0) ? 8'h20 :   //   0 dB
						 (V4_ATTEN==4'd1) ? 8'h16 :   //  -3.2 dB
						 (V4_ATTEN==4'd2) ? 8'h10 :   //  -6.0 dB
						 (V4_ATTEN==4'd3) ? 8'h0B :   //  -9.2 dB
						 (V4_ATTEN==4'd4) ? 8'h08 :   // -12.0 dB
						 (V4_ATTEN==4'd5) ? 8'h06 :   // -14.5 dB
						 (V4_ATTEN==4'd6) ? 8'h04 :   // -18.0 dB
						 (V4_ATTEN==4'd7) ? 8'h03 :   // -20.5 dB
						 (V4_ATTEN==4'd8) ? 8'h02 :   // -24.0 dB
							8'h00;	// All other values (9-15) are zero.


reg [6:0] PHRASE_SEL;

//reg WRITE_STATE;

assign V1_NIB = (!V1_INDEX[0]) ? ROM_DATA[7:4] : ROM_DATA[3:0];
assign V2_NIB = (!V2_INDEX[0]) ? ROM_DATA[7:4] : ROM_DATA[3:0];
assign V3_NIB = (!V3_INDEX[0]) ? ROM_DATA[7:4] : ROM_DATA[3:0];
assign V4_NIB = (!V4_INDEX[0]) ? ROM_DATA[7:4] : ROM_DATA[3:0];


reg WR_N_1;
//wire WR_N_RISING = (!WR_N_1 && WR_N);
assign WR_N_RISING = (!WR_N_1 && WR_N);

//reg V1_GATE;
//reg V2_GATE;
//reg V3_GATE;
//reg V4_GATE;

// LSB bit selects each NIBBLE of each ADPCM data byte!
// Bits [18:1] can be used directly for ROM_ADDR[17:0];
reg [18:0] V1_INDEX;
reg [18:0] V2_INDEX;
reg [18:0] V3_INDEX;
reg [18:0] V4_INDEX;

//reg [17:0] V1_SA;
reg [17:0] V2_SA;
reg [17:0] V3_SA;
reg [17:0] V4_SA;

//reg [17:0] V1_EA;
reg [17:0] V2_EA;
reg [17:0] V3_EA;
reg [17:0] V4_EA;

reg [3:0] V1_ATTEN;
reg [3:0] V2_ATTEN;
reg [3:0] V3_ATTEN;
reg [3:0] V4_ATTEN;

//reg [3:0] V1_STATE;
reg [3:0] V2_STATE;
reg [3:0] V3_STATE;
reg [3:0] V4_STATE;

reg [9:0] COUNTER;

always @(posedge CLK or negedge RESET_N)
if (!RESET_N) begin
	WR_N_1 <= 1'b1;
	WRITE_STATE <= 1'b0;
	
	V1_INDEX <= 0;
	
	V1_GATE <= 1'b0;
	V2_GATE <= 1'b0;
	V3_GATE <= 1'b0;
	V4_GATE <= 1'b0;
	
	V1_ATTEN <= 4'd0;
	V2_ATTEN <= 4'd0;
	V3_ATTEN <= 4'd0;
	V4_ATTEN <= 4'd0;
	
	V1_STATE <= 4'd0;
	V2_STATE <= 4'd0;
	V3_STATE <= 4'd0;
	V4_STATE <= 4'd0;
	
	MAIN_STATE <= 3'd0;
	
	COUNTER <= 10'd1;
end
else begin
	WR_N_1 <= WR_N;
	
	SAMP_PULSE <= 1'b0;	

	if (COUNTER==10'd0) begin
		SAMP_PULSE <= 1'b1;
		
		//if (!SS) COUNTER <= 10'd165;// Slower samp rate.
		//else COUNTER <= 10'd132;		// Faster samp rate.
		
		if (!SS) COUNTER <= 10'd492;	// Slower samp rate.
		else COUNTER <= 10'd393;		// Faster samp rate.
		
	end
	else COUNTER <= COUNTER - 1'b1;


	if (!WRITE_STATE && !CS_N && !WR_N && !CPU_DI[7]) begin // CPU_DI[7] is LOW, so Voice OFF. (one-byte command).
		if (CPU_DI[3]) V1_GATE <= 1'b0;
		if (CPU_DI[4]) V2_GATE <= 1'b0;
		if (CPU_DI[5]) V3_GATE <= 1'b0;
		if (CPU_DI[6]) V4_GATE <= 1'b0;		
	end	
	


	if (!WRITE_STATE && !CS_N && !WR_N && CPU_DI[7]) begin	// CPU_DI[7] is HIGH, so Voice ON. (two-byte command)
		PHRASE_SEL <= CPU_DI[6:0];
		WRITE_STATE <= 1'b1;
	end

	if (WRITE_STATE && !CS_N && !WR_N) begin		// Byte two of two-byte command...
		// The MSM6295 datasheet says "It is not possible to specify multiple channels at the same time. For example,
		// it is not possible to specify channel 1 and channel 3 simultaneously."
		//
		// So we prioritize the lower voices first here ("else if" statements)...
		//
		// Maybe the real chip only looks for the specific bit patterns on CPU_DI[7:4], though? eg...
		//
		// CPU_DI[7:4]=
		//
		// b0001 = Channel 1
		// b0010 = Channel 2
		// b0100 = Channel 3
		// b1000 = Channel 4
		//
		if (CPU_DI[4]) begin
			V1_INDEX <= {PHRASE_SEL, 4'b0000};
			V1_ATTEN <= CPU_DI[3:0];
			V1_STATE <= 4'd0;
			V1_GATE <= 1'b1;
		end
		else if (CPU_DI[5]) begin
			V2_INDEX <= {PHRASE_SEL, 4'b0000};
			V2_ATTEN <= CPU_DI[3:0];
			V2_STATE <= 4'd0;
			V2_GATE <= 1'b1;
		end
		else if (CPU_DI[6]) begin
			V3_INDEX <= {PHRASE_SEL, 4'b0000};
			V3_ATTEN <= CPU_DI[3:0];
			V3_STATE <= 4'd0;
			V3_GATE <= 1'b1;
		end
		else if (CPU_DI[7]) begin
			V4_INDEX <= {PHRASE_SEL, 4'b0000};
			V4_ATTEN <= CPU_DI[3:0];
			V4_STATE <= 4'd0;
			V4_GATE <= 1'b1;
		end
		WRITE_STATE <= 1'b0;
	end


	case (MAIN_STATE)
	// VOICE 1.
	0: begin
		case (V1_STATE)
		0: begin
			if (V1_GATE) begin
				V1_SIGNAL <= -2;
				V1_STEP <= 0;
				ROM_ADDR <= V1_INDEX[18:1];
				V1_STATE <= V1_STATE + 1;
			end
			else MAIN_STATE <= MAIN_STATE + 3'd1;
		end
	
		1: begin
			V1_SA[17:16] <= ROM_DATA[1:0];
			ROM_ADDR <= ROM_ADDR + 1;
			V1_STATE <= V1_STATE + 1;
		end

		2: begin
			V1_SA[15:8] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V1_STATE <= V1_STATE + 1;
		end

		3: begin
			V1_SA[7:0] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V1_STATE <= V1_STATE + 1;
		end

		4: begin
			V1_EA[17:16] <= ROM_DATA[1:0];
			ROM_ADDR <= ROM_ADDR + 1;
			V1_STATE <= V1_STATE + 1;
		end

		5: begin
			V1_EA[15:8] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V1_STATE <= V1_STATE + 1;
		end

		6: begin
			V1_EA[7:0] <= ROM_DATA;
			V1_STATE <= V1_STATE + 1;
		end
		
		7: begin
			ROM_ADDR <= V1_SA;
			V1_INDEX <= {V1_SA, 1'b0};
			V1_STATE <= V1_STATE + 1;
		end
		
		8: begin
			ROM_ADDR <= V1_INDEX[18:1];
			V1_STATE <= V1_STATE + 1;
		end
		
		9: begin
			if (V1_GATE && (V1_INDEX[18:1]>18'h3ff) && (V1_INDEX[18:1]>=V1_SA) && (V1_INDEX[18:1]<=V1_EA)) begin
			
				V1_SIGNAL <= V1_SIGNAL + ADPCM_DATA;

				case (V1_NIB[2:0])
				0: V1_STEP <= V1_STEP + -1;
				1: V1_STEP <= V1_STEP + -1;
				2: V1_STEP <= V1_STEP + -1;
				3: V1_STEP <= V1_STEP + -1;
				4: V1_STEP <= V1_STEP + 2;
				5: V1_STEP <= V1_STEP + 4;
				6: V1_STEP <= V1_STEP + 6;
				7: V1_STEP <= V1_STEP + 8;
				default:;
				endcase

				V1_INDEX <= V1_INDEX + 1;
				V1_STATE <= 4'd8;
			end
			else begin
				V1_GATE <= 1'b0;
				V1_STATE <= 4'd0;
			end
			MAIN_STATE <= MAIN_STATE + 3'd1;
		end
		
		default:;
		endcase
	end
	
	// VOICE 2.
	1: begin
		case (V2_STATE)
		0: begin
			if (V2_GATE) begin
				V2_SIGNAL <= -2;
				V2_STEP <= 0;
				ROM_ADDR <= V2_INDEX[18:1];
				V2_STATE <= V2_STATE + 1;
			end
			else MAIN_STATE <= MAIN_STATE + 3'd1;
		end
	
		1: begin
			V2_SA[17:16] <= ROM_DATA[1:0];
			ROM_ADDR <= ROM_ADDR + 1;
			V2_STATE <= V2_STATE + 1;
		end

		2: begin
			V2_SA[15:8] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V2_STATE <= V2_STATE + 1;
		end

		3: begin
			V2_SA[7:0] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V2_STATE <= V2_STATE + 1;
		end

		4: begin
			V2_EA[17:16] <= ROM_DATA[1:0];
			ROM_ADDR <= ROM_ADDR + 1;
			V2_STATE <= V2_STATE + 1;
		end

		5: begin
			V2_EA[15:8] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V2_STATE <= V2_STATE + 1;
		end

		6: begin
			V2_EA[7:0] <= ROM_DATA;
			V2_STATE <= V2_STATE + 1;
		end
		
		7: begin
			ROM_ADDR <= V2_SA;
			V2_INDEX <= {V2_SA, 1'b0};
			V2_STATE <= V2_STATE + 1;
		end
		
		8: begin
			ROM_ADDR <= V2_INDEX[18:1];
			V2_STATE <= V2_STATE + 1;
		end
		
		9: begin
			if (V2_GATE && (V2_INDEX[18:1]>18'h3ff) && (V2_INDEX[18:1]>=V2_SA) && (V2_INDEX[18:1]<=V2_EA)) begin
			
				V2_SIGNAL <= V2_SIGNAL + ADPCM_DATA;

				case (V2_NIB[2:0])
				0: V2_STEP <= V2_STEP + -1;
				1: V2_STEP <= V2_STEP + -1;
				2: V2_STEP <= V2_STEP + -1;
				3: V2_STEP <= V2_STEP + -1;
				4: V2_STEP <= V2_STEP + 2;
				5: V2_STEP <= V2_STEP + 4;
				6: V2_STEP <= V2_STEP + 6;
				7: V2_STEP <= V2_STEP + 8;
				default:;
				endcase

				V2_INDEX <= V2_INDEX + 1;
				V2_STATE <= 4'd8;
			end
			else begin

				V2_GATE <= 1'b0;
				V2_STATE <= 4'd0;
			end
			MAIN_STATE <= MAIN_STATE + 3'd1;
		end
		
		default:;
		endcase
	end
	
	// VOICE 3.
	2: begin
		case (V3_STATE)
		0: begin
			if (V3_GATE) begin
				V3_SIGNAL <= -2;
				V3_STEP <= 0;
				ROM_ADDR <= V3_INDEX[18:1];
				V3_STATE <= V3_STATE + 1;
			end
			else MAIN_STATE <= MAIN_STATE + 3'd1;
		end
	
		1: begin
			V3_SA[17:16] <= ROM_DATA[1:0];
			ROM_ADDR <= ROM_ADDR + 1;
			V3_STATE <= V3_STATE + 1;
		end

		2: begin
			V3_SA[15:8] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V3_STATE <= V3_STATE + 1;
		end

		3: begin
			V3_SA[7:0] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V3_STATE <= V3_STATE + 1;
		end

		4: begin
			V3_EA[17:16] <= ROM_DATA[1:0];
			ROM_ADDR <= ROM_ADDR + 1;
			V3_STATE <= V3_STATE + 1;
		end

		5: begin
			V3_EA[15:8] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V3_STATE <= V3_STATE + 1;
		end

		6: begin
			V3_EA[7:0] <= ROM_DATA;
			V3_STATE <= V3_STATE + 1;
		end
		
		7: begin
			ROM_ADDR <= V3_SA;
			V3_INDEX <= {V3_SA, 1'b0};
			V3_STATE <= V3_STATE + 1;
		end
		
		8: begin
			ROM_ADDR <= V3_INDEX[18:1];
			V3_STATE <= V3_STATE + 1;
		end
		
		9: begin
			if (V3_GATE && (V3_INDEX[18:1]>18'h3ff) && (V3_INDEX[18:1]>=V3_SA) && (V3_INDEX[18:1]<=V3_EA)) begin
			
				V3_SIGNAL <= V3_SIGNAL + ADPCM_DATA;

				case (V3_NIB[2:0])
				0: V3_STEP <= V3_STEP + -1;
				1: V3_STEP <= V3_STEP + -1;
				2: V3_STEP <= V3_STEP + -1;
				3: V3_STEP <= V3_STEP + -1;
				4: V3_STEP <= V3_STEP + 2;
				5: V3_STEP <= V3_STEP + 4;
				6: V3_STEP <= V3_STEP + 6;
				7: V3_STEP <= V3_STEP + 8;
				default:;
				endcase

				V3_INDEX <= V3_INDEX + 1;
				V3_STATE <= 4'd8;
			end
			else begin
				V3_GATE <= 1'b0;
				V3_STATE <= 4'd0;
			end
			MAIN_STATE <= MAIN_STATE + 3'd1;
		end
		
		default:;
		endcase
	end
	
	// VOICE 4.
	3: begin
		case (V4_STATE)
		0: begin
			if (V4_GATE) begin
				V4_SIGNAL <= -2;
				V4_STEP <= 0;
				ROM_ADDR <= V4_INDEX[18:1];
				V4_STATE <= V4_STATE + 1;
			end
			else MAIN_STATE <= MAIN_STATE + 3'd1;
		end
	
		1: begin
			V4_SA[17:16] <= ROM_DATA[1:0];
			ROM_ADDR <= ROM_ADDR + 1;
			V4_STATE <= V4_STATE + 1;
		end

		2: begin
			V4_SA[15:8] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V4_STATE <= V4_STATE + 1;
		end

		3: begin
			V4_SA[7:0] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V4_STATE <= V4_STATE + 1;
		end

		4: begin
			V4_EA[17:16] <= ROM_DATA[1:0];
			ROM_ADDR <= ROM_ADDR + 1;
			V4_STATE <= V4_STATE + 1;
		end

		5: begin
			V4_EA[15:8] <= ROM_DATA;
			ROM_ADDR <= ROM_ADDR + 1;
			V4_STATE <= V4_STATE + 1;
		end

		6: begin
			V4_EA[7:0] <= ROM_DATA;
			V4_STATE <= V4_STATE + 1;
		end
		
		7: begin
			ROM_ADDR <= V4_SA;
			V4_INDEX <= {V4_SA, 1'b0};
			V4_STATE <= V4_STATE + 1;
		end
		
		8: begin
			ROM_ADDR <= V4_INDEX[18:1];
			V4_STATE <= V4_STATE + 1;
		end
		
		9: begin
			if (V4_GATE && (V4_INDEX[18:1]>18'h3ff) && (V4_INDEX[18:1]>=V4_SA) && (V4_INDEX[18:1]<=V4_EA)) begin
			
				V4_SIGNAL <= V4_SIGNAL + ADPCM_DATA;

				case (V4_NIB[2:0])
				0: V4_STEP <= V4_STEP + -1;
				1: V4_STEP <= V4_STEP + -1;
				2: V4_STEP <= V4_STEP + -1;
				3: V4_STEP <= V4_STEP + -1;
				4: V4_STEP <= V4_STEP + 2;
				5: V4_STEP <= V4_STEP + 4;
				6: V4_STEP <= V4_STEP + 6;
				7: V4_STEP <= V4_STEP + 8;
				default:;
				endcase

				V4_INDEX <= V4_INDEX + 1;
				V4_STATE <= 4'd8;
			end
			else begin
				V4_GATE <= 1'b0;
				V4_STATE <= 4'd0;
			end
			MAIN_STATE <= MAIN_STATE + 3'd1;
		end
		
		default:;
		endcase
	end
	
	// "VOICE" (state) 5.
	4: begin
		// Clamp the SIGNAL values. Definitely needs this!
		if (V1_SIGNAL > 2047) V1_SIGNAL <= 2047;
		else if (V1_SIGNAL < -2048) V1_SIGNAL <= -2048;
		if (V2_SIGNAL > 2047) V2_SIGNAL <= 2047;
		else if (V2_SIGNAL < -2048) V2_SIGNAL <= -2048;
		if (V3_SIGNAL > 2047) V3_SIGNAL <= 2047;
		else if (V3_SIGNAL < -2048) V3_SIGNAL <= -2048;
		if (V4_SIGNAL > 2047) V4_SIGNAL <= 2047;
		else if (V4_SIGNAL < -2048) V4_SIGNAL <= -2048;
		
		// Clamp the STEP values. Definitely needs this!
		if (V1_STEP > 48) V1_STEP <= 48;
		else if (V1_STEP < 0) V1_STEP <= 0;
		if (V2_STEP > 48) V2_STEP <= 48;
		else if (V2_STEP < 0) V2_STEP <= 0;
		if (V3_STEP > 48) V3_STEP <= 48;
		else if (V3_STEP < 0) V3_STEP <= 0;
		if (V4_STEP > 48) V4_STEP <= 48;
		else if (V4_STEP < 0) V4_STEP <= 0;
		
		MAIN_STATE <= MAIN_STATE + 3'd1;
	end
	
	// Wait for next SAMP_PULSE before updating the output samples.
	5: begin	
		if (SAMP_PULSE) begin
			V1_SAMP_OUT <= (V1_GATE) ? V1_SIGNAL * V1_VOL_MUL : 18'd0;
			V2_SAMP_OUT <= (V2_GATE) ? V2_SIGNAL * V2_VOL_MUL : 18'd0;
			V3_SAMP_OUT <= (V3_GATE) ? V3_SIGNAL * V3_VOL_MUL : 18'd0;
			V4_SAMP_OUT <= (V4_GATE) ? V4_SIGNAL * V4_VOL_MUL : 18'd0;
			MAIN_STATE <= 3'd0;
		end
	end
	
	default:;
	endcase	// "case (MAIN_STATE)".

end

// Using 13-bits, to allow checking for overflow / underflow / clamping!
//reg signed [12:0] V1_SIGNAL;
//reg signed [12:0] V2_SIGNAL;
//reg signed [12:0] V3_SIGNAL;
//reg signed [12:0] V4_SIGNAL;

// Reduced these to 7 bits.
// (48 as the max STEP clamping value, and not negative. Still need the extra MSB bits for sign and clamp checking!)
reg signed [6:0] V1_STEP;
reg signed [6:0] V2_STEP;
reg signed [6:0] V3_STEP;
reg signed [6:0] V4_STEP;


wire [11:0] ADPCM_ADDR = (MAIN_STATE==0) ? (V1_STEP * 16) + V1_NIB :
								 (MAIN_STATE==1) ? (V2_STEP * 16) + V2_NIB :
								 (MAIN_STATE==2) ? (V3_STEP * 16) + V3_NIB :
														 (V4_STEP * 16) + V4_NIB;

wire signed [15:0] ADPCM_DATA;

ADPCM_LUT_ROM ADPCM_LUT_ROM
(
	.ADDR( ADPCM_ADDR ) ,	// input [11:0] ADDR
	.DATA( ADPCM_DATA ) 		// output [15:0] DATA
);


endmodule
