`timescale 1 ns / 1 ps

`ifdef _SDRAM_CMD_GEN_
/* Already included !! */
`else
`define _SDRAM_CMD_GEN_
module sdram_cmd_gen
(
    //-----------------------------
    // Clock and reset
    //-----------------------------
    input             rst,         // Global reset
    input             clk,         // Master clock (72 MHz)
    
    output            ram_rdy_n,   // SDRAM ready
    output            ram_ref,     // SDRAM refresh
    output      [3:0] ram_cyc,     // SDRAM cycle
    output      [3:0] ram_acc,     // SDRAM access
    output      [8:0] ram_slot,    // Slot counter
    output            slot_rst,    // Slot counter reset
    
    //-----------------------------
    // Access bank #0
    //-----------------------------
    input             rden_b0,     // Read enable
    input             wren_b0,     // Write enable
    input      [31:0] addr_b0,     // Address (up to 64 MB)
    output            valid_b0,    // Read data valid
    output            fetch_b0,    // Write data fetch
    
    //-----------------------------
    // Access bank #1
    //-----------------------------
    input             rden_b1,     // Read enable
    input             wren_b1,     // Write enable
    input      [31:0] addr_b1,     // Address (up to 64 MB)
    output            valid_b1,    // Read data valid
    output            fetch_b1,    // Write data fetch
    
    //-----------------------------
    // Access bank #2
    //-----------------------------
    input             rden_b2,     // Read enable
    input             wren_b2,     // Write enable
    input      [31:0] addr_b2,     // Address (up to 64 MB)
    output            valid_b2,    // Read data valid
    output            fetch_b2,    // Write data fetch
    
    //-----------------------------
    // Access bank #3
    //-----------------------------
    input             rden_b3,     // Read enable
    input             wren_b3,     // Write enable
    input      [31:0] addr_b3,     // Address (up to 64 MB)
    output            valid_b3,    // Read data valid
    output            fetch_b3,    // Write data fetch
    
    //-----------------------------
    // SDRAM memory signals
    //-----------------------------
    // Controls
    output            sdram_cs_n,  // SDRAM chip select
    output reg        sdram_ras_n, // SDRAM row address strobe
    output reg        sdram_cas_n, // SDRAM column address strobe
    output reg        sdram_we_n,  // SDRAM write enable
    // Addresses
    output reg  [1:0] sdram_ba,    // SDRAM bank address
    output reg [12:0] sdram_addr   // SDRAM address
);
    // Clock-to-output delay (for simulation)
    parameter Tco_dly        = 4.5;
    // Slot start value for refresh
    parameter SLOT_CTR_REFR  = 284;
    parameter ACC_CTR_REFR   = 2;
    // Number of refreshes per line
    parameter NUM_REFR_LINE  = 9;
    // Start value for slot counter
    parameter SLOT_CTR_START = 3;
    // Stop value for slot & access counters
    parameter SLOT_CTR_STOP  = 288;
    parameter ACC_CTR_STOP   = 3;
    // Number of scan-lines during SDRAM init
    parameter INIT_LINES     = 4;
    // Row addressing (12 - 13)
    parameter SDR_ROW_WIDTH  = 12; // Default : 4096 rows
    // Column addressing (8 - 11)
    parameter SDR_COL_WIDTH  =  9; // Default : 512 words
    // Bus width (8/16/32/64)
    parameter SDR_BUS_WIDTH  = 16; // Default : 16-bit bus
    // Clock frequency in MHz
    parameter SDR_CLOCK_FREQ = 50;
    // Burst length (1, 2, 4, 8)
    parameter SDR_BURST_LEN  = 2;
    
    // Memories layouts :
    // ------------------
    // SDRAM  4M x 32b (128 Mb) : 4 banks x 4096 rows x 256 cols x 32 bits
    // SDRAM  8M x 32b (256 Mb) : 4 banks x 4096 rows x 512 cols x 32 bits
    // SDRAM  8M x 16b (128 Mb) : 4 banks x 4096 rows x 512 cols x 16 bits
    // SDRAM 16M x 16b (256 Mb) : 4 banks x 8192 rows x 512 cols x 16 bits
    
    //=========================================================================
    // SDRAM commands
    //=========================================================================
    
    localparam [2:0]
        CMD_LMR = 3'b000,
        CMD_REF = 3'b001,
        CMD_PRE = 3'b010,
        CMD_ACT = 3'b011,
        CMD_WR  = 3'b100,
        CMD_RD  = 3'b101,
        CMD_BST = 3'b110,
        CMD_NOP = 3'b111;
        
    //=========================================================================
    // SDRAM sequencer control
    //=========================================================================
    
    // Cycles in one access
    reg [3:0] r_ram_cyc;
    // Access in one slot
    reg [3:0] r_ram_acc;
    reg [1:0] r_ba0_ctr;
    reg [1:0] r_ba1_ctr;
    // Slot counter
    reg [8:0] r_slot_ctr;
    // Slot counter clear
    reg       r_slot_clr;
    reg       r_slot_rst;
    // Initialization counter
    reg [3:0] r_init_ctr;
    // Initialization done
    wire      w_init_done = r_init_ctr[3];
    reg       r_refr_ena;
    reg [4:0] r_refr_ctr;
    
    always@(posedge rst or posedge clk) begin : SEQUENCER_CTRL
        reg v_refr_beg; // Start SDRAM refresh
        reg v_refr_end; // Stop SDRAM refresh
        
        if (rst) begin
            r_ram_cyc  <= 4'b0001;
            r_ram_acc  <= 4'b0001;
            r_ba0_ctr  <= 2'd0;
            r_ba1_ctr  <= 2'd3;
            r_slot_ctr <= SLOT_CTR_START[8:0];
            r_slot_clr <= 1'b0;
            r_slot_rst <= 1'b0;
            r_init_ctr <= 4'd8 - INIT_LINES[3:0];
            r_refr_ena <= 1'b0;
            r_refr_ctr <= 5'd0;
            v_refr_beg <= 1'b0;
            v_refr_end <= 1'b0;
        end
        else begin
            // 4 cycles per bank access
            r_ram_cyc <= { r_ram_cyc[2:0], r_ram_cyc[3] };
            
            if (r_ram_cyc[3]) begin
                if (r_slot_clr) begin
                    // End of scan-line
                    r_ram_acc  <= 4'b0001;
                    r_ba0_ctr  <= 2'd0;
                    r_ba1_ctr  <= 2'd3;
                    r_slot_ctr <= SLOT_CTR_START[8:0];
                    // Initialization done after INIT_LINES scan-lines
                    if (!w_init_done) begin
                        r_init_ctr <= r_init_ctr + 4'd1;
                    end
                end
                else begin
                    // 4 bank access per slot
                    r_ram_acc  <= { r_ram_acc[2:0], r_ram_acc[3] };
                    // Manage the bank counters
                    r_ba0_ctr  <= r_ba0_ctr + 2'd1;
                    r_ba1_ctr  <= r_ba1_ctr + 2'd1;
                    // Manage the slot counter
                    if (r_ram_acc[3]) begin
                        r_slot_ctr <= r_slot_ctr + 9'd1;
                    end
                end
                // SDRAM refresh enable / disable
                if (r_refr_ena)
                    r_refr_ctr <= r_refr_ctr + 5'd1;
                else
                    r_refr_ctr <= 5'd0;
                if (v_refr_beg)
                    r_refr_ena <= 1'b1;
                else if (v_refr_end)
                    r_refr_ena <= 1'b0;
            end
            // Slot counter clear comparator
            r_slot_clr <= (r_slot_ctr == SLOT_CTR_STOP[8:0]) ? r_ram_acc[ACC_CTR_STOP[1:0]] : 1'b0;
            
            // Slot counter reset
            r_slot_rst <= r_slot_clr & r_ram_cyc[2];
            // Start SDRAM refresh
            v_refr_beg <= (r_slot_ctr == SLOT_CTR_REFR[8:0]) ? r_ram_acc[ACC_CTR_REFR[1:0]] : 1'b0;
            // Stop SDRAM refresh
            v_refr_end <= (r_refr_ctr == { NUM_REFR_LINE[3:0], 1'b0 }) ? 1'b1 : 1'b0;
        end
    end
    
    assign slot_rst  = r_slot_rst;
    assign ram_ref   = r_refr_ena;
    assign ram_cyc   = r_ram_cyc;
    assign ram_acc   = r_ram_acc;
    assign ram_slot  = r_slot_ctr;
    assign ram_rdy_n = ~w_init_done;
    
    //=========================================================================
    // SDRAM phase generation
    //=========================================================================
    
    reg [3:0] r_rd_act; // Read active for bank #0 - 3
    reg [3:0] r_wr_act; // Write active for bank #0 - 3
    
    reg       r_act_ph; // Activate phase
    reg       r_rd_ph;  // Burst read phase
    reg       r_wr_ph;  // Burst write phase
    reg       r_ref_ph; // Auto-refresh phase
    reg [4:0] r_ini_ph; // Initialization phases
    reg       r_pre_ph; // Precharge phase
    reg       r_lmr_ph; // Load mode register phase
    
    always@(posedge rst or posedge clk) begin : PHASE_GEN
        reg v_init;
    
        if (rst) begin
            r_rd_act <= 4'b0000;
            r_wr_act <= 4'b0000;
            
            r_act_ph <= 1'b0;
            r_rd_ph  <= 1'b0;
            r_wr_ph  <= 1'b0;
            r_ref_ph <= 1'b0;
            r_ini_ph <= 5'b00000;
            r_pre_ph <= 1'b0;
            r_lmr_ph <= 1'b0;
            v_init   <= 1'b0;
        end
        else begin
            if (r_ram_cyc[0]) begin
                // Access port #0 read/write
                if (r_ram_acc[0]) begin
                    r_rd_act[0] <= rden_b0 & ~r_refr_ena;
                    r_wr_act[0] <= wren_b0 & ~r_refr_ena & ~rden_b0;
                end
                else if (r_ram_acc[2]) begin
                    r_rd_act[0] <= 1'b0;
                    r_wr_act[0] <= 1'b0;
                end
                // Access port #1 read/write
                if (r_ram_acc[1]) begin
                    r_rd_act[1] <= rden_b1 & ~r_refr_ena;
                    r_wr_act[1] <= wren_b1 & ~r_refr_ena & ~rden_b1;
                end
                else if (r_ram_acc[3]) begin
                    r_rd_act[1] <= 1'b0;
                    r_wr_act[1] <= 1'b0;
                end
                // Access port #2 read/write
                if (r_ram_acc[2]) begin
                    r_rd_act[2] <= rden_b2 & ~r_refr_ena;
                    r_wr_act[2] <= wren_b2 & ~r_refr_ena & ~rden_b2;
                end
                else if (r_ram_acc[0]) begin
                    r_rd_act[2] <= 1'b0;
                    r_wr_act[2] <= 1'b0;
                end
                // Access port #3 read/write
                if (r_ram_acc[3]) begin
                    r_rd_act[3] <= rden_b3 & ~r_refr_ena;
                    r_wr_act[3] <= wren_b3 & ~r_refr_ena & ~rden_b3;
                end
                else if (r_ram_acc[1]) begin
                    r_rd_act[3] <= 1'b0;
                    r_wr_act[3] <= 1'b0;
                end
            end
            
            if (r_ram_cyc[0] & w_init_done) begin
                // Activate phase
                r_act_ph <= (r_ram_acc[0] & (rden_b0 | wren_b0) & ~r_refr_ena)
                          | (r_ram_acc[1] & (rden_b1 | wren_b1) & ~r_refr_ena)
                          | (r_ram_acc[2] & (rden_b2 | wren_b2) & ~r_refr_ena)
                          | (r_ram_acc[3] & (rden_b3 | wren_b3) & ~r_refr_ena);
            end
            
            if (r_ram_cyc[3] & w_init_done) begin
                // Read phase
                r_rd_ph  <= (r_ram_acc[0] & r_rd_act[0])
                          | (r_ram_acc[1] & r_rd_act[1])
                          | (r_ram_acc[2] & r_rd_act[2])
                          | (r_ram_acc[3] & r_rd_act[3]);
                // Write phase
                r_wr_ph  <= (r_ram_acc[0] & r_wr_act[0])
                          | (r_ram_acc[1] & r_wr_act[1])
                          | (r_ram_acc[2] & r_wr_act[2])
                          | (r_ram_acc[3] & r_wr_act[3]);
            end

            // Initialization phases (0:PRE, 1:REF, 2:REF, 3:LMR)
            if (r_ram_cyc[3] & r_ram_acc[2]) begin
                if (v_init) begin
                    if (!r_ini_ph[4]) begin
                        r_ini_ph <= { r_ini_ph[3:0], ~|r_ini_ph };
                    end
                end
                else begin
                    r_ini_ph <= 5'b00000;
                end
            end
            v_init <= (r_init_ctr == 4'd7) ? r_refr_ena : 1'b0;
            
            // Precharge phase
            r_pre_ph <= r_ini_ph[0] & r_ram_acc[0];
            
            // Refresh phase
            r_ref_ph <= r_refr_ena & w_init_done & r_refr_ctr[0]    // Normal
                      | (r_ini_ph[1] | r_ini_ph[2]) & r_ram_acc[0]; // Initialization
            
            // Load mode register phase
            r_lmr_ph <= r_ini_ph[3] & r_ram_acc[0];
            
        end
    end
    
    //=========================================================================
    // SDRAM address generation
    //=========================================================================
    
    wire [12:0] w_addr_lmr; // Address for LMR command
    reg  [25:0] r_addr_mux; // Up to 64 MB per bank
    reg  [12:0] r_addr_col; // Maximum, 13 address lines
    reg  [12:0] r_addr_sdr; // Maximum, 13 address lines
    reg   [1:0] r_ba_sdr;   // 4 banks
    
    assign w_addr_lmr[12:3] = (SDR_CLOCK_FREQ <= 100)
                            ? 10'b000_1_00_010_0  // WB = 1, Normal Op, CAS = 2, Seq
                            : 10'b000_1_00_011_0; // WB = 1, Normal Op, CAS = 3, Seq
    assign w_addr_lmr[ 2:0] = (SDR_BURST_LEN == 1) ? 3'b000 // BL = 1
                            : (SDR_BURST_LEN == 2) ? 3'b001 // BL = 2
                            : (SDR_BURST_LEN == 4) ? 3'b010 // BL = 4
                            : (SDR_BURST_LEN == 8) ? 3'b011 // BL = 8
                            : 3'b000;
    
    always@(posedge rst or posedge clk) begin : ADDRESS_GEN
        reg [12:0] v_addr_col;
        reg [12:0] v_addr_row;
    
        if (rst) begin
            r_addr_mux <= 26'd0;
            r_addr_col <= 13'd0;
            r_addr_sdr <= 13'd0;
            r_ba_sdr   <= 2'd0;
        end
        else begin
            // Port address multiplexer
            if (r_ram_cyc[0]) begin
                case (SDR_BUS_WIDTH)
                    // 8-bit bus
                    8 : begin
                        r_addr_mux <= addr_b0[25:0] & {26{r_ram_acc[0] & (rden_b0 | wren_b0) }}
                                    | addr_b1[25:0] & {26{r_ram_acc[1] & (rden_b1 | wren_b1) }}
                                    | addr_b2[25:0] & {26{r_ram_acc[2] & (rden_b2 | wren_b2) }}
                                    | addr_b3[25:0] & {26{r_ram_acc[3] & (rden_b3 | wren_b3) }};
                    end
                    // 16-bit bus
                    16 : begin
                        r_addr_mux <= addr_b0[26:1] & {26{r_ram_acc[0] & (rden_b0 | wren_b0) }}
                                    | addr_b1[26:1] & {26{r_ram_acc[1] & (rden_b1 | wren_b1) }}
                                    | addr_b2[26:1] & {26{r_ram_acc[2] & (rden_b2 | wren_b2) }}
                                    | addr_b3[26:1] & {26{r_ram_acc[3] & (rden_b3 | wren_b3) }};
                    end
                    // 32-bit bus
                    32 : begin
                        r_addr_mux <= addr_b0[27:2] & {26{r_ram_acc[0] & (rden_b0 | wren_b0) }}
                                    | addr_b1[27:2] & {26{r_ram_acc[1] & (rden_b1 | wren_b1) }}
                                    | addr_b2[27:2] & {26{r_ram_acc[2] & (rden_b2 | wren_b2) }}
                                    | addr_b3[27:2] & {26{r_ram_acc[3] & (rden_b3 | wren_b3) }};
                    end
                    // 64-bit bus
                    64 : begin
                        r_addr_mux <= addr_b0[28:3] & {26{r_ram_acc[0] & (rden_b0 | wren_b0) }}
                                    | addr_b1[28:3] & {26{r_ram_acc[1] & (rden_b1 | wren_b1) }}
                                    | addr_b2[28:3] & {26{r_ram_acc[2] & (rden_b2 | wren_b2) }}
                                    | addr_b3[28:3] & {26{r_ram_acc[3] & (rden_b3 | wren_b3) }};
                    end
                endcase
            end

            // Column address (for read/write op.)
            if (r_ram_cyc[3]) begin
                r_addr_col <=
                    (SDR_COL_WIDTH ==  8) ? { 5'b0, r_addr_mux[7:0] } :                       //  256 columns
                    (SDR_COL_WIDTH ==  9) ? { 4'b0, r_addr_mux[8:0] } :                       //  512 columns
                    (SDR_COL_WIDTH == 10) ? { 3'b0, r_addr_mux[9:0] } :                       // 1024 columns
                    (SDR_COL_WIDTH == 11) ? { 1'b0, r_addr_mux[10], 1'b0, r_addr_mux[9:0] } : // 2048 columns (we must skip A10)
                    13'd0;
            end
            
            // Row / col address
            v_addr_col = r_addr_col[12:0]
                       ^ { 2'b00, 1'b1, 8'b000000000, r_rd_ph, 1'b0 }; // With auto-precharge
            v_addr_row = (SDR_COL_WIDTH ==  8) ? r_addr_mux[20: 8]
                       : (SDR_COL_WIDTH ==  9) ? r_addr_mux[21: 9]
                       : (SDR_COL_WIDTH == 10) ? r_addr_mux[22:10]
                       : (SDR_COL_WIDTH == 11) ? r_addr_mux[23:11]
                       : 13'd0;
            
            r_addr_sdr <= { r_addr_col[12:0]    } & {13{r_rd_ph  & r_ram_cyc[0]}}  // Read BL2
                        | { v_addr_row[12:0]    } & {13{r_act_ph & r_ram_cyc[1]}}  // Activate row
                        | { v_addr_col[12:0]    } & {13{r_rd_ph  & r_ram_cyc[2]}}  // Read BL2 with AP
                        | { v_addr_col[12:0]    } & {13{r_wr_ph  & r_ram_cyc[3]}}  // Write BL2 with AP
                        | { 13'b00_1_0000000000 } & {13{r_ini_ph[0]            }}  // Init : precharge all
                        | { w_addr_lmr[12:0]    } & {13{r_ini_ph[3]            }}; // Init : load mode register
            
            // Bank address
            r_ba_sdr   <= r_ba1_ctr & {2{r_rd_ph  & r_ram_cyc[0]}}  // Read
                        | r_ba0_ctr & {2{r_act_ph & r_ram_cyc[1]}}  // Activate
                        | r_ba1_ctr & {2{r_rd_ph  & r_ram_cyc[2]}}  // Read with auto-precharge
                        | r_ba1_ctr & {2{r_wr_ph  & r_ram_cyc[3]}}; // Write with auto-precharge
        end
    end
    
    //=========================================================================
    // SDRAM command generation
    //=========================================================================
    
    reg  [2:0] r_cmd_sdr;
        
    always@(posedge rst or posedge clk) begin : COMMAND_GEN
        reg [2:0] v_cmd_act;
        reg [2:0] v_cmd_rd;
        reg [2:0] v_cmd_wr;
        reg [2:0] v_cmd_pre;
        reg [2:0] v_cmd_ref;
        reg [2:0] v_cmd_lmr;
    
        if (rst) begin
            r_cmd_sdr <= CMD_NOP;
        end
        else begin
            v_cmd_act = CMD_ACT | {3{~r_act_ph}};
            v_cmd_rd  = CMD_RD  | {3{~r_rd_ph }};
            v_cmd_wr  = CMD_WR  | {3{~r_wr_ph }};
            v_cmd_pre = CMD_PRE | {3{~r_pre_ph}};
            v_cmd_ref = CMD_REF | {3{~r_ref_ph}};
            v_cmd_lmr = CMD_LMR | {3{~r_lmr_ph}};
            
            r_cmd_sdr <= (v_cmd_rd  | {3{~r_ram_cyc[0]}})
                       & (v_cmd_act | {3{~r_ram_cyc[1]}})
                       & (v_cmd_rd  | {3{~r_ram_cyc[2]}})
                       & (v_cmd_wr  | {3{~r_ram_cyc[3]}})
                       & (v_cmd_pre | {3{~r_ram_cyc[3]}})
                       & (v_cmd_ref | {3{~r_ram_cyc[3]}})
                       & (v_cmd_lmr | {3{~r_ram_cyc[3]}});
        end
    end
    
    assign sdram_cs_n  = 1'b0;
    
    // Command and address
    /* verilator lint_off STMTDLY */
    always@(*) sdram_ras_n = #Tco_dly r_cmd_sdr[2];
    always@(*) sdram_cas_n = #Tco_dly r_cmd_sdr[1];
    always@(*) sdram_we_n  = #Tco_dly r_cmd_sdr[0];
    always@(*) sdram_ba    = #Tco_dly r_ba_sdr;
    always@(*) sdram_addr  = #Tco_dly r_addr_sdr;
    /* verilator lint_on STMTDLY */
    
    //=========================================================================
    // Data valid (read)
    //=========================================================================
    
    reg   [3:0] r_cas2_vld;
    reg   [3:0] r_cas3_vld;
    
    always@(posedge rst or posedge clk) begin : DATA_VALID
    
        if (rst) begin
            r_cas2_vld  <= 4'b0000;
            r_cas3_vld  <= 4'b0000;
        end
        else begin
            if (r_ram_cyc[3]) begin
                r_cas2_vld[0] <= r_rd_act[0] & r_ram_acc[1];
                r_cas2_vld[1] <= r_rd_act[1] & r_ram_acc[2];
                r_cas2_vld[2] <= r_rd_act[2] & r_ram_acc[3];
                r_cas2_vld[3] <= r_rd_act[3] & r_ram_acc[0];
            end
            r_cas3_vld <= r_cas2_vld;
        end
    end
    
    // Access Port #0
    assign valid_b0 = (SDR_CLOCK_FREQ <= 100) ? r_cas2_vld[0] : r_cas3_vld[0];
    
    // Access Port #1
    assign valid_b1 = (SDR_CLOCK_FREQ <= 100) ? r_cas2_vld[1] : r_cas3_vld[1];
    
    // Access Port #2
    assign valid_b2 = (SDR_CLOCK_FREQ <= 100) ? r_cas2_vld[2] : r_cas3_vld[2];
    
    // Access Port #3
    assign valid_b3 = (SDR_CLOCK_FREQ <= 100) ? r_cas2_vld[3] : r_cas3_vld[3];
    
    //=========================================================================
    // Data fetch (write)
    //=========================================================================
    
    reg   [3:0] r_data_fe;
    
    always@(posedge rst or posedge clk) begin : DATA_FETCH
    
        if (rst) begin
            r_data_fe <= 4'b0000;
        end
        else begin
            if (r_ram_cyc[3]) begin
                r_data_fe <= r_wr_act & r_ram_acc;
            end
            else if (r_ram_cyc[1]) begin
                r_data_fe <= 4'b0000;
            end
        end
    end
    
    // Access Port #0
    assign fetch_b0 = r_data_fe[0];
    
    // Access Port #1
    assign fetch_b1 = r_data_fe[1];
    
    // Access Port #2
    assign fetch_b2 = r_data_fe[2];
    
    // Access Port #3
    assign fetch_b3 = r_data_fe[3];
    
endmodule
`endif /* _SDRAM_CMD_GEN_ */
