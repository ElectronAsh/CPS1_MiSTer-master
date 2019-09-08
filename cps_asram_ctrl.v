module cps_asram_ctrl
(
    //-----------------------------
    // Clock and reset
    //-----------------------------
    input          bus_rst,         // Bus reset
    input          bus_clk,         // Bus clock (81 MHz)

    input          ram_ref,         // SDRAM refresh active
    input    [3:0] ram_cyc,         // SDRAM cycles
    input    [3:0] ram_acc,         // SDRAM access
    
    //-----------------------------
    // VRAM access from 68000 CPU
    //-----------------------------
    input          cpu_rden,        // Read enable
    input          cpu_wren,        // Write enable
    input    [1:0] cpu_bena,        // Bytes enables
    input   [19:0] cpu_addr,        // Address (up to 1 MB)
    input   [15:0] cpu_wdata,       // Data written to SRAM
    output  [15:0] cpu_rdata,       // Data read from SRAM
    output         cpu_valid,       // Read data valid
    
    //-----------------------------
    // VRAM access from GPU
    //-----------------------------
    input          gpu_rden,        // Read enable
    input   [19:0] gpu_addr,        // Address (up to 1 MB)
    output  [31:0] gpu_rdata,       // Data read from SRAM
    output         gpu_valid,       // Read data valid
    
    //-----------------------------
    // SRAM memory signals
    //-----------------------------
    output         sram_ce_n,       // SRAM chip enable
    output         sram_oe_n,       // SRAM output enable
    output         sram_we_n,       // SRAM write enable
    output   [3:0] sram_be_n,       // SRAM byte enable
    output  [19:2] sram_addr,       // SRAM address bus
    output         sram_dq_oe,      // SRAM data output enable
    output  [31:0] sram_dq_o,       // SRAM data output
    input   [31:0] sram_dq_i        // SRAM data input
);

    //=========================================================================
    // SRAM control
    //=========================================================================
    
    wire       w_cpu_acc = ram_acc[0] | ram_acc[2];
    wire       w_gpu_acc = ram_acc[1] | ram_acc[3];
    
    // p1 : ram_cyc[0]
    reg        r_ram_rden_p1;
    reg        r_ram_wren_p1;
    reg  [3:0] r_ram_bena_p1;
    reg [19:0] r_ram_addr_p1;
    reg [31:0] r_ram_wdata_p1;
    // p2 : ram_cyc[1]
    reg        r_ram_ce_n_p2;
    reg        r_ram_oe_n_p2;
    reg        r_ram_we_n_p2;
    reg  [3:0] r_ram_be_n_p2;
    // p3 : ram_cyc[2]
    reg [31:0] r_ram_rdata_p3;
    // p4 : ram_cyc[3]
    reg [15:0] r_cpu_rdata_p4;
    reg        r_cpu_valid_p4;
    reg [31:0] r_gpu_rdata_p4;
    reg        r_gpu_valid_p4;
    
    always@(posedge bus_rst or posedge bus_clk) begin : SRAM_CTRL_P1_P4
    
        if (bus_rst) begin
            r_ram_rden_p1  <= 1'b0;
            r_ram_wren_p1  <= 1'b0;
            r_ram_bena_p1  <= 4'b0000;
            r_ram_addr_p1  <= 20'd0;
            r_ram_wdata_p1 <= 32'h00000000;
            
            r_ram_ce_n_p2  <= 1'b1;
            r_ram_oe_n_p2  <= 1'b1;
            r_ram_we_n_p2  <= 1'b1;
            r_ram_be_n_p2  <= 4'b1111;
            
            r_ram_rdata_p3 <= 32'h00000000;
            
            r_cpu_rdata_p4 <= 16'h0000;
            r_cpu_valid_p4 <= 1'b0;
            r_gpu_rdata_p4 <= 32'h00000000;
            r_gpu_valid_p4 <= 1'b0;
        end
        else begin
            // Cycle #1
            if (ram_cyc[0]) begin
                // SRAM read/write controls
                r_ram_rden_p1  <= w_gpu_acc & gpu_rden | w_cpu_acc & cpu_rden;
                r_ram_wren_p1  <= w_cpu_acc & cpu_wren;
                // SRAM bytes enables
                if (w_cpu_acc) begin
                    // CPU : 16 bits -> 32 bits, big endian
                    r_ram_bena_p1[3] <= (cpu_rden | cpu_wren) & cpu_bena[1] & ~cpu_addr[1]; // 00 : MSB
                    r_ram_bena_p1[2] <= (cpu_rden | cpu_wren) & cpu_bena[0] & ~cpu_addr[1]; // 01
                    r_ram_bena_p1[1] <= (cpu_rden | cpu_wren) & cpu_bena[1] &  cpu_addr[1]; // 10
                    r_ram_bena_p1[0] <= (cpu_rden | cpu_wren) & cpu_bena[0] &  cpu_addr[1]; // 11 : LSB
                end
                else begin
                    // GPU : always 32 bits
                    r_ram_bena_p1 <= {4{gpu_rden}};
                end
                // SRAM address
                r_ram_addr_p1  <= (w_gpu_acc) ? gpu_addr[19:0] : cpu_addr[19:0];
                // SRAM write (16 bits -> 32 bits)
                r_ram_wdata_p1 <= { cpu_wdata[15:0], cpu_wdata[15:0] };
            end
            
            // Cycle #2
            if (ram_cyc[1]) begin
                // SRAM controls, negative logic
                r_ram_ce_n_p2 <= ~r_ram_rden_p1 & ~r_ram_wren_p1;
                r_ram_oe_n_p2 <= ~r_ram_rden_p1;
                r_ram_we_n_p2 <= ~r_ram_wren_p1;
                r_ram_be_n_p2 <= ~r_ram_bena_p1;
            end
            else begin
                // Disabled outside cycle #2
                r_ram_ce_n_p2 <= 1'b1;
                r_ram_oe_n_p2 <= 1'b1;
                r_ram_we_n_p2 <= 1'b1;
                r_ram_be_n_p2 <= 4'b1111;
            end
            
            // SRAM read (Cycle #3)
            r_ram_rdata_p3 <= sram_dq_i;
            
            // CPU VRAM read (16-bit)
            if (ram_cyc[3] & w_cpu_acc) begin
                r_cpu_rdata_p4 <= (r_ram_addr_p1[1]) ? r_ram_rdata_p3[15:0] : r_ram_rdata_p3[31:16];
                r_cpu_valid_p4 <= r_ram_rden_p1;
            end
            else begin
                r_cpu_valid_p4 <= 1'b0;
            end
            
            // GPU VRAM read (32-bit)
            if (ram_cyc[3] & w_gpu_acc) begin
                r_gpu_rdata_p4 <= r_ram_rdata_p3;
                r_gpu_valid_p4 <= r_ram_rden_p1;
            end
            else begin
                r_gpu_valid_p4 <= 1'b0;
            end
        end
    end
    
    assign sram_addr  = r_ram_addr_p1[19:2];
    assign sram_dq_oe = r_ram_wren_p1;
    assign sram_dq_o  = r_ram_wdata_p1;
    
    assign sram_ce_n = r_ram_ce_n_p2;
    assign sram_oe_n = r_ram_oe_n_p2;
    assign sram_we_n = r_ram_we_n_p2;
    assign sram_be_n = r_ram_be_n_p2;
    
    assign cpu_rdata = r_cpu_rdata_p4;
    assign cpu_valid = r_cpu_valid_p4;
    
    assign gpu_rdata = r_gpu_rdata_p4;
    assign gpu_valid = r_gpu_valid_p4;

endmodule
