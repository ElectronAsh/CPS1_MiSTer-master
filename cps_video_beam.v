// Bus timing :
// ------------
// 81 MHz bus clock (3 x 27)
// 321.75 phases / line (line rate : 15734.265 Hz)
// 4 bank access / phase
// 4 clocks / bank access
// 5148 clocks / line
// 263 lines / frame
// 59.826 Hz frame rate

// 160 68000 access / line
// 227.5 Z80 access / line
// 3x64 tile blocks (8x2) / 2 lines
// 1024 sprite blocks (8x2) / 2 lines

// Video timing :
// --------------
// 108 MHz pixel clock (4 x 27)
// 1716 clocks / line (line rate : 62937 Hz)
// 1052 lines / frame
// 59.826 Hz frame rate

module cps_video_beam
(
    input         bus_rst,         // Bus reset
    input         bus_clk,         // Bus clock (81 MHz)
    
    input         ram_ref,         // SDRAM refresh active
    input   [3:0] ram_cyc,         // SDRAM cycles
    input   [3:0] ram_acc,         // SDRAM access
    input   [8:0] ram_slot,        // Slot counter
    input         slot_rst,        // Slot counter reset
    
    output        bus_eof,         // Bus end-of-frame
    output  [6:0] bus_vbl,         // Bus vertical blanking
    output  [8:0] bus_vpos,        // Bus vertical position
    output        bus_dma_ena,     // Bus DMAs enable
    output        bus_frd_ena,     // Bus FIFOs read enable
    
    input         vid_rst,         // Video reset
    input         vid_clk,         // Video clock (108 MHz)
    output  [2:0] vid_clk_ena,     // Video clock enable
    
    output        vid_eol,         // Video end-of-line
    output        vid_eof,         // Video end-of-frame
    output [10:0] vid_hpos,        // Horizontal position (0 - 1715)
    output [10:0] vid_vpos,        // Vertical position (0 - 1051)
    output        vid_hsync,       // Horizontal synchronization
    output        vid_vsync,       // Vertical synchronization
    output        vid_dena         // Display enable
);

    // ========================================================================
    // Vertical position : 0 - 262 (bus clock)
    // ========================================================================
    
    reg [8:0] r_bus_vpos; // Vertical position
    reg [6:0] r_bus_vbl;  // Vertical blanking
    reg       r_bus_frd;  // FIFO read enable
    
    always@(posedge bus_rst or posedge bus_clk) begin : BUS_VPOS
    
        if (bus_rst) begin
            r_bus_vpos <= 9'd256;
            r_bus_vbl  <= 7'b0000001;
            r_bus_frd  <= 1'b0;
        end
        else begin
            // Vertical position
            if (slot_rst) begin
                r_bus_vpos <= (r_bus_vbl[6]) ? 9'd0 : r_bus_vpos + 9'd1;
            end
            // Vertical blanking
            if (slot_rst) begin
                r_bus_vbl  <= { r_bus_vbl[5:0], &r_bus_vpos[7:0] };
            end
            // FIFOs read enable
            if (ram_acc[3] & ram_cyc[3]) begin
                if (ram_slot == 9'h1FF)
                    r_bus_frd <= ~r_bus_vpos[8];
                else if (ram_slot == 9'h0BF)
                    r_bus_frd <= 1'b0;
            end
        end
    end
    
    assign bus_eof       = r_bus_vbl[6] & slot_rst;
    assign bus_vpos      = r_bus_vpos;
    assign bus_vbl       = r_bus_vbl;
    assign bus_dma_ena   = ~r_bus_vpos[8];
    assign bus_frd_ena   = r_bus_frd;

    // ========================================================================
    // Vertical position   : 0 - 1051 (video clock)
    // Horizontal position : 0 - 1715 (video clock)
    // ========================================================================
    
    reg [10:0] r_vid_vpos;    // Vertical position
    reg [10:0] r_vid_hpos;    // Horizontal position
    reg        r_vid_eol;     // End of line
    reg        r_vid_eof;     // End of frame
    reg        r_vid_lock;    // Video locked
    reg  [2:0] r_vid_clk_ena; // Clock enable
    
    always@(posedge vid_rst or posedge vid_clk) begin : VID_HVPOS
        reg [2:0] v_ref_cc;
        reg [2:0] v_eof_cc;
    
        if (vid_rst) begin
            r_vid_vpos    <= 11'd0;
            r_vid_hpos    <= 11'd0;
            r_vid_eol     <= 1'b0;
            r_vid_eof     <= 1'b0;
            r_vid_lock    <= 1'b0;
            r_vid_clk_ena <= 3'b000;
            v_ref_cc      <= 3'b000;
            v_eof_cc      <= 3'b000;
        end
        else begin
            if (r_vid_lock) begin
                // Vertical position
                if (r_vid_eol) begin
                    r_vid_vpos <= (r_vid_eof) ? 11'd0 : r_vid_vpos + 11'd1;
                end
                // Horizontal position
                r_vid_hpos    <= (r_vid_eol) ? 11'd0 : r_vid_hpos + 11'd1;
                // Clock enable (108 MHz -> 36 MHz)
                r_vid_clk_ena <= { r_vid_clk_ena[1:0], r_vid_clk_ena[2] };
            end
            else begin
                r_vid_vpos    <= 11'd1024;
                r_vid_hpos    <= 11'd0;
                r_vid_clk_ena <= 3'b001;
            end
            
            // Lock signal on end of frame
            if ((v_ref_cc[2:1] == 2'b01) && (v_eof_cc[2:1] == 2'b11)) begin
                r_vid_lock <= 1'b1;
            end
            
            // End of frame flag
            r_vid_eof <= (r_vid_vpos == 11'd1051) ? 1'b1 : 1'b0;
            // End of line flag
            r_vid_eol <= (r_vid_hpos == 11'd1714) ? 1'b1 : 1'b0;
            
            // Clock domain crossing (81 MHz -> 108 MHz)
            v_ref_cc <= { v_ref_cc[1:0], ram_ref };
            v_eof_cc <= { v_eof_cc[1:0], r_bus_vbl[4] };
        end
    end
    
    assign vid_eof     = r_vid_eol & r_vid_eof;
    assign vid_eol     = r_vid_eol;
    assign vid_hpos    = r_vid_hpos;
    assign vid_vpos    = r_vid_vpos;
    assign vid_clk_ena = r_vid_clk_ena;
    
    // ========================================================================
    // Vertical front porch   : 1 line
    // Vertical synchro       : 3 lines
    // Vertical back proch    : 20 lines
    // Horizontal front porch : 48 cycles (1668 -1715)
    // Horizontal synchro     : 140 cycles (0 - 139)
    // Horizontal back porch  : 248 cycles (140 - 387)
    // Display enable         : 1280 cycles (388 - 1667)
    // ========================================================================
    
    reg        r_vid_vsync;  // Vertical synchro
    reg        r_vid_hsync;  // Horizontal synchro
    reg        r_vid_dena;   // Display enable
    
    always@(posedge vid_rst or posedge vid_clk) begin : VID_HVSYNC
        reg v_vs_strt;
        reg v_vs_stop;
        reg v_hs_stop;
        reg v_de_strt;
        reg v_de_stop;
        
        if (vid_rst) begin
          r_vid_vsync <= 1'b0;
          r_vid_hsync <= 1'b0;
          r_vid_dena  <= 1'b0;
          v_vs_strt   <= 1'b0;
          v_vs_stop   <= 1'b0;
          v_hs_stop   <= 1'b0;
          v_de_strt   <= 1'b0;
          v_de_stop   <= 1'b0;
        end
        else begin
            // Vertical synchro (line 1027 - 1033)
            if (r_vid_eol) begin
                r_vid_vsync <= (r_vid_vsync & ~v_vs_stop) | v_vs_strt;
            end
            v_vs_strt   <= (r_vid_vpos == 11'd1028) ? 1'b1 : 1'b0;
            v_vs_stop   <= (r_vid_vpos == 11'd1031) ? 1'b1 : 1'b0;
            // Horizontal synchro (cycles 0 - 139)
            r_vid_hsync <= (r_vid_hsync & ~v_hs_stop) | r_vid_eol;
            v_hs_stop   <= (r_vid_hpos ==  11'd138) ? 1'b1 : 1'b0;
            // Display enable (cycles 388 - 1667 & lines 0 - 1023)
            r_vid_dena  <= (r_vid_dena & ~v_de_stop)
                         | (v_de_strt & ~r_vid_vpos[10]);
            v_de_strt   <= (r_vid_hpos ==  11'd386) ? 1'b1 : 1'b0;
            v_de_stop   <= (r_vid_hpos == 11'd1666) ? 1'b1 : 1'b0;
        end
    end
    
    assign vid_dena  = r_vid_dena;
    assign vid_hsync = r_vid_hsync;
    assign vid_vsync = r_vid_vsync;

endmodule
