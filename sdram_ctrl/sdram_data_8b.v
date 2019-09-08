`timescale 1 ns / 1 ps

`ifdef _SDRAM_DATA_8B_
/* Already included !! */
`else
`define _SDRAM_DATA_8B_
module sdram_data_8b
(
    //-----------------------------
    // Clock and reset
    //-----------------------------
    input             clk,         // Master clock (72 MHz)

    //-----------------------------
    // Internal bus
    //-----------------------------
    output      [7:0] rd_data,     // Read data from banks #0-3
    
    input       [3:0] data_fetch,  // Write data fetch (p0)
    input       [7:0] wr_data_b0,  // Write data to bank #0 (p2)
    input       [7:0] wr_data_b1,  // Write data to bank #1 (p2)
    input       [7:0] wr_data_b2,  // Write data to bank #2 (p2)
    input       [7:0] wr_data_b3,  // Write data to bank #3 (p2)
    
    //-----------------------------
    // External bus
    //-----------------------------
    output reg        sdram_dq_oe, // SDRAM data output enable
    output reg  [7:0] sdram_dq_o,  // SDRAM data output
    input       [7:0] sdram_dq_i   // SDRAM data input
);
    // Clock-to-output delay (for simulation)
    parameter Tco_dly = 4.5;

    //=========================================================================
    
    reg [7:0] r_rd_data;
    
    always@(posedge clk) begin : READ_DATA_PATH
    
        r_rd_data <= sdram_dq_i;
    end
    
    assign rd_data = r_rd_data;

    //=========================================================================
    
    reg [3:0] r_data_fe_p1;
    reg [3:0] r_data_fe_p2;
    
    reg       r_data_oe_p3;
    reg       r_data_oe_p4;
    
    reg [7:0] r_wr_data_p3 [0:1];
    reg [7:0] r_wr_data_p4;
    
    always@(posedge clk) begin : WRITE_DATA_PATH
    
        r_data_fe_p1 <= data_fetch;
        r_data_fe_p2 <= r_data_fe_p1;
        
        r_data_oe_p3 <= |r_data_fe_p2;
        r_data_oe_p4 <= r_data_oe_p3;
        
        r_wr_data_p3[0] <= wr_data_b0 & {8{r_data_fe_p2[0]}}
                         | wr_data_b1 & {8{r_data_fe_p2[1]}};
        r_wr_data_p3[1] <= wr_data_b2 & {8{r_data_fe_p2[2]}}
                         | wr_data_b3 & {8{r_data_fe_p2[3]}};
        r_wr_data_p4    <= r_wr_data_p3[0]
                         | r_wr_data_p3[1];
    end
    
    // Output mask, data & enable
    /* verilator lint_off STMTDLY */
    always@(*) sdram_dq_o  = #Tco_dly r_wr_data_p4;
    always@(*) sdram_dq_oe = #Tco_dly r_data_oe_p4;
    /* verilator lint_on STMTDLY */
    
    //=========================================================================
    
endmodule
`endif /* _SDRAM_DATA_8B_ */
