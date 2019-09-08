`timescale 1 ns / 1 ps

`ifdef _SDRAM_CTRL_64B_
/* Already included !! */
`else
`define _SDRAM_CTRL_64B_
module sdram_ctrl_64b
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
    
    output     [63:0] rd_data,     // Read data from banks #0-3
    //-----------------------------
    // Access bank #0
    //-----------------------------
    input             rden_b0,     // Read enable
    input             wren_b0,     // Write enable
    input      [31:0] addr_b0,     // Address (up to 64 MB)
    output            valid_b0,    // Read data valid
    output            fetch_b0,    // Write data fetch (p0)
    input       [7:0] wr_bena_b0,  // Write byte enable (p2)
    input      [63:0] wr_data_b0,  // Write data (p2)
    
    //-----------------------------
    // Access bank #1
    //-----------------------------
    input             rden_b1,     // Read enable
    input             wren_b1,     // Write enable
    input      [31:0] addr_b1,     // Address (up to 64 MB)
    output            valid_b1,    // Read data valid
    output            fetch_b1,    // Write data fetch (p0)
    input       [7:0] wr_bena_b1,  // Write byte enable (p2)
    input      [63:0] wr_data_b1,  // Write data (p2)
    
    //-----------------------------
    // Access bank #2
    //-----------------------------
    input             rden_b2,     // Read enable
    input             wren_b2,     // Write enable
    input      [31:0] addr_b2,     // Address (up to 64 MB)
    output            valid_b2,    // Read data valid
    output            fetch_b2,    // Write data fetch (p0)
    input       [7:0] wr_bena_b2,  // Write byte enable (p2)
    input      [63:0] wr_data_b2,  // Write data (p2)
    
    //-----------------------------
    // Access bank #3
    //-----------------------------
    input             rden_b3,     // Read enable
    input             wren_b3,     // Write enable
    input      [31:0] addr_b3,     // Address (up to 64 MB)
    output            valid_b3,    // Read data valid
    output            fetch_b3,    // Write data fetch (p0)
    input       [7:0] wr_bena_b3,  // Write byte enable (p2)
    input      [63:0] wr_data_b3,  // Write data to (p2)
    
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
    output reg [12:0] sdram_addr,  // SDRAM address
    // Data
    output reg  [7:0] sdram_dqm_n, // SDRAM DQ masks
    output reg        sdram_dq_oe, // SDRAM data output enable
    output reg [63:0] sdram_dq_o,  // SDRAM data output
    input      [63:0] sdram_dq_i   // SDRAM data input
);
    // Clock-to-output delay (for simulation)
    parameter Tco_dly        = 4.5;
    // Slot start value for refresh
    parameter SLOT_CTR_REFR  = 284;
    // Number of refreshes per line
    parameter NUM_REFR_LINE  = 9;
    // Start value for slot counter
    parameter SLOT_CTR_START = 3;
    // Stop value for slot counter
    parameter SLOT_CTR_STOP  = 288;
    parameter ACC_CTR_STOP   = 3;
    // Number of scan-lines during SDRAM init
    parameter INIT_LINES     = 4;
    // Row addressing (12 - 13)
    `ifdef SDR_ROW_WIDTH
    parameter SDR_ROW_WIDTH  = `SDR_ROW_WIDTH;
    `else
    parameter SDR_ROW_WIDTH  = 12; // Default : 4096 rows
    `endif
    // Column addressing (8 - 11)
    `ifdef SDR_COL_WIDTH
    parameter SDR_COL_WIDTH  = `SDR_COL_WIDTH;
    `else
    parameter SDR_COL_WIDTH  =  9; // Default : 512 words
    `endif
    // Clock frequency in MHz
    `ifdef SDR_CLOCK_FREQ
    parameter SDR_CLOCK_FREQ = `SDR_CLOCK_FREQ;
    `else
    parameter SDR_CLOCK_FREQ = 50;
    `endif
    // Burst length
    `ifdef SDR_BURST_LEN
    parameter SDR_BURST_LEN = `SDR_BURST_LEN;
    `else
    parameter SDR_BURST_LEN = 2;
    `endif

    sdram_cmd_gen
    #(
        .Tco_dly        (Tco_dly),
        .SLOT_CTR_REFR  (SLOT_CTR_REFR),
        .NUM_REFR_LINE  (NUM_REFR_LINE),
        .SLOT_CTR_START (SLOT_CTR_START),
        .SLOT_CTR_STOP  (SLOT_CTR_STOP),
        .ACC_CTR_STOP   (ACC_CTR_STOP),
        .INIT_LINES     (INIT_LINES),
        .SDR_ROW_WIDTH  (SDR_ROW_WIDTH),
        .SDR_COL_WIDTH  (SDR_COL_WIDTH),
        .SDR_BUS_WIDTH  (64),
        .SDR_CLOCK_FREQ (SDR_CLOCK_FREQ),
        .SDR_BURST_LEN  (SDR_BURST_LEN)
    )
    U_sdram_cmd_gen
    (
        .rst         (rst),
        .clk         (clk),
        //
        .ram_rdy_n   (ram_rdy_n),
        .ram_ref     (ram_ref),
        .ram_cyc     (ram_cyc),
        .ram_acc     (ram_acc),
        .ram_slot    (ram_slot),
        .slot_rst    (slot_rst),
        //
        .rden_b0     (rden_b0),
        .wren_b0     (wren_b0),
        .addr_b0     (addr_b0),
        .valid_b0    (valid_b0),
        .fetch_b0    (fetch_b0),
        //
        .rden_b1     (rden_b1),
        .wren_b1     (wren_b1),
        .addr_b1     (addr_b1),
        .valid_b1    (valid_b1),
        .fetch_b1    (fetch_b1),
        //
        .rden_b2     (rden_b2),
        .wren_b2     (wren_b2),
        .addr_b2     (addr_b2),
        .valid_b2    (valid_b2),
        .fetch_b2    (fetch_b2),
        //
        .rden_b3     (rden_b3),
        .wren_b3     (wren_b3),
        .addr_b3     (addr_b3),
        .valid_b3    (valid_b3),
        .fetch_b3    (fetch_b3),
        //
        .sdram_cs_n  (sdram_cs_n),
        .sdram_ras_n (sdram_ras_n),
        .sdram_cas_n (sdram_cas_n),
        .sdram_we_n  (sdram_we_n),
        .sdram_ba    (sdram_ba),
        .sdram_addr  (sdram_addr) 
    );
    
    sdram_data_64b
    #(
        .Tco_dly     (Tco_dly)
    )
    U_sdram_data
    (
        .clk         (clk),
        //
        .rd_data     (rd_data),
        .data_fetch  ({ fetch_b3, fetch_b2, fetch_b1, fetch_b0 }),
        .wr_bena_b0  (wr_bena_b0),
        .wr_data_b0  (wr_data_b0),
        .wr_bena_b1  (wr_bena_b1),
        .wr_data_b1  (wr_data_b1),
        .wr_bena_b2  (wr_bena_b2),
        .wr_data_b2  (wr_data_b2),
        .wr_bena_b3  (wr_bena_b3),
        .wr_data_b3  (wr_data_b3),
        //
        .sdram_dqm_n (sdram_dqm_n),
        .sdram_dq_oe (sdram_dq_oe),
        .sdram_dq_o  (sdram_dq_o), 
        .sdram_dq_i  (sdram_dq_i)
    );
    
endmodule
`endif /* _SDRAM_CTRL_64B_ */
