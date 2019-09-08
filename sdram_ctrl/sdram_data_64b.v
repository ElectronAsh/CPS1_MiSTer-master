`timescale 1 ns / 1 ps

`ifdef _SDRAM_DATA_64B_
/* Already included !! */
`else
`define _SDRAM_DATA_64B_
module sdram_data_64b
(
    //-----------------------------
    // Clock and reset
    //-----------------------------
    input             clk,         // Master clock (72 MHz)

    //-----------------------------
    // Internal bus
    //-----------------------------
    output     [63:0] rd_data,     // Read data from banks #0-3
    
    input       [3:0] data_fetch,  // Write data fetch (p0)
    // Bank #0
    input       [7:0] wr_bena_b0,  // Write byte enable (p2)
    input      [63:0] wr_data_b0,  // Write data (p2)
    // Bank #1
    input       [7:0] wr_bena_b1,  // Write byte enable (p2)
    input      [63:0] wr_data_b1,  // Write data (p2)
    // Bank #2
    input       [7:0] wr_bena_b2,  // Write byte enable (p2)
    input      [63:0] wr_data_b2,  // Write data (p2)
    // Bank #3
    input       [7:0] wr_bena_b3,  // Write byte enable (p2)
    input      [63:0] wr_data_b3,  // Write data (p2)
    
    //-----------------------------
    // External bus
    //-----------------------------
    output reg  [7:0] sdram_dqm_n, // SDRAM DQ masks
    output reg        sdram_dq_oe, // SDRAM data output enable
    output reg [63:0] sdram_dq_o,  // SDRAM data output
    input      [63:0] sdram_dq_i   // SDRAM data input
);
    // Clock-to-output delay (for simulation)
    parameter Tco_dly = 4.5;

    //=========================================================================
    
    reg [63:0] r_rd_data;
    
    always@(posedge clk) begin : READ_DATA_PATH
    
        r_rd_data <= sdram_dq_i;
    end
    
    assign rd_data = r_rd_data;

    //=========================================================================
    
    reg  [3:0] r_data_fe_p1;
    reg  [3:0] r_data_fe_p2;
    
    reg        r_data_oe_p3;
    reg        r_data_oe_p4;
    
    reg  [7:0] r_wr_bena_p3 [0:2];
    reg  [7:0] r_wr_bena_p4;
    
    reg [63:0] r_wr_data_p3 [0:1];
    reg [63:0] r_wr_data_p4;
    
    always@(posedge clk) begin : WRITE_DATA_PATH
    
        r_data_fe_p1 <= data_fetch;
        r_data_fe_p2 <= r_data_fe_p1;
        
        r_data_oe_p3 <= |r_data_fe_p2;
        r_data_oe_p4 <= r_data_oe_p3;
        
        r_wr_bena_p3[0] <= wr_bena_b0 & {8{r_data_fe_p2[0]}}
                         | wr_bena_b1 & {8{r_data_fe_p2[1]}};
        r_wr_bena_p3[1] <= wr_bena_b2 & {8{r_data_fe_p2[2]}}
                         | wr_bena_b3 & {8{r_data_fe_p2[3]}};
        r_wr_bena_p3[2] <= {8{~|r_data_fe_p2}};
        r_wr_bena_p4    <= ~( r_wr_bena_p3[0]
                            | r_wr_bena_p3[1]
                            | r_wr_bena_p3[2] );
                         
        r_wr_data_p3[0] <= wr_data_b0 & {64{r_data_fe_p2[0]}}
                         | wr_data_b1 & {64{r_data_fe_p2[1]}};
        r_wr_data_p3[1] <= wr_data_b2 & {64{r_data_fe_p2[2]}}
                         | wr_data_b3 & {64{r_data_fe_p2[3]}};
        r_wr_data_p4    <= r_wr_data_p3[0]
                         | r_wr_data_p3[1];
    end
    
    // Output mask, data & enable
    /* verilator lint_off STMTDLY */
    always@(*) sdram_dqm_n = #Tco_dly r_wr_bena_p4;
    always@(*) sdram_dq_o  = #Tco_dly r_wr_data_p4;
    always@(*) sdram_dq_oe = #Tco_dly r_data_oe_p4;
    /* verilator lint_on STMTDLY */
    
    //=========================================================================
    
endmodule
`endif /* _SDRAM_DATA_64B_ */
