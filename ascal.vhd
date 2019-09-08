--------------------------------------------------------------------------------
-- AVALON SCALER
--------------------------------------------------------------------------------
-- TEMLIB 10/2018
--------------------------------------------------------------------------------
-- This code can be used for any purpose, but, if you find any bug, or want to
-- suggest an enhancement, you ought to send a mail to info@temlib.org
--------------------------------------------------------------------------------

-- 3 clock domains
--  i_xxx   : Input video
--  o_xxx   : Output video
--  avl_xxx : Avalon memory bus

--------------------------------------------
-- Mode 24bits

-- 5 pixels = 120 bits = 2 x 64bits
-- Burst 32 x 64bits  = 80 pixels = 256 octets
-- Burst 16 x 128bits

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY ascal IS
  GENERIC (
     -- RAM base address for framebuffer
    RAMBASE   : unsigned(31 DOWNTO 0);
    -- Read Only. Another block updates the framebuffer
    RO     : boolean := false;
    FORMAT : natural RANGE 1 TO 8 :=8;
    N_DW  : natural RANGE 32 TO 128 := 128; -- Data bus width
    N_AW  : natural RANGE 8 TO 32 := 32; -- Avalon Address bus width
    HRES : natural RANGE 1 TO 2048 :=1024; -- Max. input resolution (2^x !!)
    N_BURST : natural := 256 -- 256 bytes per burst
    );
  PORT (
    -- Input video
    i_r   : unsigned(7 DOWNTO 0);
    i_g   : unsigned(7 DOWNTO 0);
    i_b   : unsigned(7 DOWNTO 0);
    i_hs  : std_logic;
    i_vs  : std_logic;
    i_de  : std_logic;
    i_ce  : std_logic;
    i_clk : std_logic; -- Input clock

    -- Output video
    o_r   : OUT unsigned(7 DOWNTO 0);
    o_g   : OUT unsigned(7 DOWNTO 0);
    o_b   : OUT unsigned(7 DOWNTO 0);
    o_hs  : OUT std_logic; -- H sychro
    o_vs  : OUT std_logic; -- V sychro
    o_de  : OUT std_logic; -- Display Enable
    o_ce  : IN  std_logic; -- Clock Enable
    o_clk : IN  std_logic; -- Output clock

    -- Input video parameters
    iauto : IN std_logic; -- 1=Autodetect image size 1=Choose window
    himin : IN natural RANGE 0 TO 4095;
    himax : IN natural RANGE 0 TO 4095;
    vimin : IN natural RANGE 0 TO 4095;
    vimax : IN natural RANGE 0 TO 4095;
    
    -- Output video parameters
    run   : IN std_logic;
    mode  : IN unsigned(3 DOWNTO 0);
    -- 0000 : Nearest
    -- 0010 : Hlinear
    -- 0011 : Bilinear
    -- SYNC  |________________________/"""""""""\_______|
    -- DE    |""""""""""""""""""\_______________________|
    -- RGB   |    <#IMAGE#>     ^HDISP                  |
    --            ^HMIN   ^HMAX       ^HSSTART  ^HSSEND ^HTOTAL
    htotal  : IN natural RANGE 0 TO 4095;
    hsstart : IN natural RANGE 0 TO 4095;
    hsend   : IN natural RANGE 0 TO 4095;
    hdisp   : IN natural RANGE 0 TO 4095;
    hmin    : IN natural RANGE 0 TO 4095;
    hmax    : IN natural RANGE 0 TO 4095;
    vtotal  : IN natural RANGE 0 TO 4095;
    vsstart : IN natural RANGE 0 TO 4095;
    vsend   : IN natural RANGE 0 TO 4095;
    vdisp   : IN natural RANGE 0 TO 4095;
    vmin    : IN natural RANGE 0 TO 4095;
    vmax    : IN natural RANGE 0 TO 4095;
    
    -- Avalon 64bits
    avl_clk            : IN    std_logic; -- Avalon clock
    avl_waitrequest    : IN    std_logic;
    avl_readdata       : IN    std_logic_vector(N_DW-1 DOWNTO 0);
    avl_readdatavalid  : IN    std_logic;
    avl_burstcount     : OUT   std_logic_vector(7 DOWNTO 0);
    avl_writedata      : OUT   std_logic_vector(N_DW-1 DOWNTO 0);
    avl_address        : OUT   std_logic_vector(N_AW-1 DOWNTO 0);
    avl_write          : OUT   std_logic;
    avl_read           : OUT   std_logic;
    avl_byteenable     : OUT   std_logic_vector(N_DW/8-1 DOWNTO 0);

    reset_na           : IN    std_logic
    );

BEGIN
  ASSERT N_DW=32 OR N_DW=64 OR N_DW=128 REPORT "DW" SEVERITY failure;
  
END ENTITY ascal;

--##############################################################################

ARCHITECTURE rtl OF ascal IS
  
  ----------------------------------------------------------
  FUNCTION ilog2 (CONSTANT v : natural) RETURN natural IS
    VARIABLE r : natural := 1;
    VARIABLE n : natural := 0;
  BEGIN
    WHILE v>r LOOP
      n:=n+1;
      r:=r*2;
    END LOOP;
    RETURN n;
  END FUNCTION ilog2;
  FUNCTION to_std_logic (a : boolean) RETURN std_logic IS
  BEGIN
    IF a THEN RETURN '1';
         ELSE RETURN '0';
    END IF;
  END FUNCTION to_std_logic;
  
  ----------------------------------------------------------
  CONSTANT NB_BURST : natural :=ilog2(N_BURST);
  CONSTANT NB_LA : natural :=ilog2(N_DW/8); -- Low address bits
  CONSTANT BLEN : natural :=N_BURST / N_DW * 8; -- Burst length
  CONSTANT NP : natural :=24;
  
  ----------------------------------------------------------
  SIGNAL bg_col : unsigned(23 DOWNTO 0); -- Background colour
  
  ----------------------------------------------------------
  -- Input image
  -- IHSIZE=IHMAX-IHMIN
  SIGNAL i_run : std_logic;
  SIGNAL i_hsize,i_hmin,i_hmax,i_hcpt : natural RANGE 0 TO 4095;
  SIGNAL i_vsize,i_vmin,i_vmax,i_vmaxc,i_vcpt : natural RANGE 0 TO 4095;
  SIGNAL i_vminset : std_logic;
  SIGNAL i_iauto : std_logic;
  SIGNAL i_ven : std_logic;
  SIGNAL i_wr : std_logic;
  SIGNAL i_de_pre : std_logic;
  SIGNAL i_hs_pre : std_logic;
  SIGNAL i_write : std_logic;
  SIGNAL i_push : std_logic;
  SIGNAL i_hburst,i_hbcpt : natural RANGE 0 TO HRES/N_BURST;
  SIGNAL i_shift : unsigned(N_DW-1 DOWNTO 0);
  SIGNAL i_acpt : natural RANGE 0 TO 7;
  TYPE arr_dw IS  ARRAY (natural RANGE <>) OF unsigned(N_DW-1 DOWNTO 0);
  SIGNAL i_dpram,o_dpram : arr_dw(0 TO BLEN*2-1);
  ATTRIBUTE ramstyle : string;
  ATTRIBUTE ramstyle OF i_dpram : SIGNAL IS "no_rw_check";
  ATTRIBUTE ramstyle OF o_dpram : SIGNAL IS "no_rw_check";

  SIGNAL i_ad,i_ad_pre : natural RANGE  0 TO BLEN*2-1;
  SIGNAL i_dw : unsigned(N_DW-1 DOWNTO 0);
  SIGNAL i_adrs,i_adrsi : unsigned(31 DOWNTO 0); -- Avalon address
  SIGNAL i_reset_na : std_logic;
  ----------------------------------------------------------
  -- Avalon
  TYPE type_avl_state IS (sIDLE,sWRITE,sREAD);
  SIGNAL avl_state : type_avl_state;
  
  SIGNAL avl_write_i,avl_write_sync,avl_write_sync2 : std_logic;
  SIGNAL avl_read_i,avl_read_sync,avl_read_sync2 : std_logic;
  SIGNAL avl_read_pulse,avl_write_pulse : std_logic;
  SIGNAL avl_vs : std_logic;
  SIGNAL avl_reading : std_logic;
  SIGNAL avl_read_sr,avl_write_sr,avl_read_clr,avl_write_clr : std_logic;
  SIGNAL avl_rad,avl_rad_c,avl_wad : natural RANGE 0 TO 2*BLEN-1;
  SIGNAL avl_dw,avl_dr : unsigned(N_DW-1 DOWNTO 0);
  SIGNAL avl_wr : std_logic;
  SIGNAL avl_readack : std_logic;
  SIGNAL avl_radrs,avl_wadrs : unsigned(31 DOWNTO 0);
  SIGNAL avl_reset_na : std_logic;
  
  ----------------------------------------------------------
  -- Output
  SIGNAL o_run : std_logic;
  SIGNAL o_mode : unsigned(3 DOWNTO 0);
  SIGNAL o_htotal,o_hsstart,o_hsend : natural RANGE 0 TO 4095;
  SIGNAL o_hmin,o_hmax,o_hdisp : natural RANGE 0 TO 4095;
  SIGNAL o_vtotal,o_vsstart,o_vsend : natural RANGE 0 TO 4095;
  SIGNAL o_vmin,o_vmax,o_vdisp : natural RANGE 0 TO 4095;
  SIGNAL o_divcpt : natural RANGE 0 TO 36;
  SIGNAL o_divstart : std_logic;
  SIGNAL o_divrun : std_logic;
  TYPE type_o_state IS (sDISP,sHSYNC,sREAD,sWAITREAD);
  SIGNAL o_state : type_o_state;
  SIGNAL o_copy,o_readack,o_readack_sync,o_readack_sync2 : std_logic;
  SIGNAL o_adrs : unsigned(31 DOWNTO 0); -- Avalon address
  SIGNAL o_ad : natural RANGE 0 TO 2*BLEN-1;
  SIGNAL o_dr : unsigned(N_DW-1 DOWNTO 0);
  SIGNAL o_reset_na : std_logic;

  TYPE arr_pix IS ARRAY (natural RANGE <>) OF unsigned(NP-1 DOWNTO 0);
  SIGNAL o_line0,o_line1,o_line2,o_line3 : arr_pix(0 TO HRES-1);
  ATTRIBUTE ramstyle OF o_line0 : SIGNAL IS "no_rw_check";
  ATTRIBUTE ramstyle OF o_line1 : SIGNAL IS "no_rw_check";
  ATTRIBUTE ramstyle OF o_line2 : SIGNAL IS "no_rw_check";
  ATTRIBUTE ramstyle OF o_line3 : SIGNAL IS "no_rw_check";
  SIGNAL o_wadl,o_radl0,o_radl1,o_radl2,o_radl3 : natural RANGE 0 TO HRES-1;
  SIGNAL o_ldw,o_ldr0,o_ldr1,o_ldr2,o_ldr3 : unsigned(NP-1 DOWNTO 0);
  SIGNAL o_wr0,o_wr1,o_wr2,o_wr3 : std_logic;
  SIGNAL o_hcpt,o_vcpt     : natural RANGE 0 TO 4095;
  SIGNAL o_hdelta,o_vdelta : unsigned(23 DOWNTO 0);
  SIGNAL o_ihsize,o_ivsize : natural RANGE 0 TO 4095;
  SIGNAL o_hdivi,o_vdivi   : unsigned(11 DOWNTO 0);
  SIGNAL o_hdivr,o_vdivr   : unsigned(35 DOWNTO 0);

  SIGNAL o_hpos,o_vpos,o_vpos_pre,o_hini,o_vini : unsigned(23 DOWNTO 0); -- [23:12].[11.0]
  SIGNAL o_hpos1,o_hpos2,o_hpos3,o_hpos4,o_hpos5 : unsigned(23 DOWNTO 0);
  SIGNAL o_vposi : natural RANGE 0 TO 4095;
  SIGNAL o_hsync_i,o_hsync_pre,o_vsync_i,o_vsync_pre,o_de_i : std_logic;
  SIGNAL o_hs1,o_hs2,o_hs3,o_hs4,o_hs5 : std_logic;
  SIGNAL o_vs1,o_vs2,o_vs3,o_vs4,o_vs5 : std_logic;
  SIGNAL o_de1,o_de2,o_de3,o_de4,o_de5 : std_logic;
  SIGNAL o_read,o_readpend : std_logic;
  SIGNAL o_hburst,o_hbcpt : natural RANGE 0 TO HRES/N_BURST;
  SIGNAL o_fload : natural RANGE 0 TO 2;
  SIGNAL o_acpt : natural RANGE 0 TO 7; -- Alternance pixels FIFO
  SIGNAL o_lcpt : natural RANGE 0 TO HRES-1;
  SIGNAL o_alt : std_logic;
  SIGNAL o_pix,o_pix01,o_pix23 : unsigned(23 DOWNTO 0);

  -----------------------------------------------------------------------------
  FUNCTION linearu(frac  : unsigned(11 DOWNTO 0);
                   p0,p1 : unsigned(7 DOWNTO 0)) RETURN unsigned IS
    VARIABLE x,y : unsigned(16 DOWNTO 0);
    CONSTANT Z : unsigned(11 DOWNTO 0):=(OTHERS =>'0');
  BEGIN
    x:=p1 * ('0' & frac(11 DOWNTO 4));
    y:=p0 * (('1' & Z(11 DOWNTO 4)) - ('0' & frac(11 DOWNTO 4)));
    x:=x+y;
    IF x(16)='1' THEN
      RETURN x"FF";
    ELSE
      RETURN x(15 DOWNTO 8);
    END IF;
  END FUNCTION;

  FUNCTION nearestu(frac  : unsigned(11 DOWNTO 0);
                    p0,p1 : unsigned(7 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    IF frac(11)='1' THEN
      RETURN p1;
    ELSE
      RETURN p0;
    END IF;
  END FUNCTION;
  
  -----------------------------------------------------------------------------
  FUNCTION linear(frac  : unsigned(11 DOWNTO 0);
                  p0,p1 : unsigned(23 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    RETURN
      linearu(frac,p0(23 DOWNTO 16),p1(23 DOWNTO 16)) &
      linearu(frac,p0(15 DOWNTO 8),p1(15 DOWNTO 8)) &
      linearu(frac,p0(7 DOWNTO 0),p1(7 DOWNTO 0));
  END FUNCTION linear;
  FUNCTION nearest(frac  : unsigned(11 DOWNTO 0);
                  p0,p1 : unsigned(23 DOWNTO 0)) RETURN unsigned IS
  BEGIN
    RETURN
      nearestu(frac,p0(23 DOWNTO 16),p1(23 DOWNTO 16)) &
      nearestu(frac,p0(15 DOWNTO 8),p1(15 DOWNTO 8)) &
      nearestu(frac,p0(7 DOWNTO 0),p1(7 DOWNTO 0));
  END FUNCTION nearest;
  
BEGIN

  i_reset_na<='0' WHEN reset_na='0' ELSE '1' WHEN rising_edge(i_clk);
  o_reset_na<='0' WHEN reset_na='0' ELSE '1' WHEN rising_edge(o_clk);
  avl_reset_na<='0' WHEN reset_na='0' ELSE '1' WHEN rising_edge(avl_clk);
  
  -----------------------------------------------------------------------------
  -- Input pixels FIFO and shreg
  InAT:PROCESS(i_clk,i_reset_na) IS
  BEGIN
    IF i_reset_na='0' THEN
      i_write<='0';
      
    ELSIF rising_edge(i_clk) THEN
      i_push<='0';
      i_run <= run; -- <ASYNC>
      i_iauto<=iauto; -- <ASYNC> ?

      IF i_ce='1' THEN
        --------------------------------
        i_hs_pre<=i_hs;
        i_de_pre<=i_de;
        
        --------------------------------
        IF i_hs='1' THEN
          i_hcpt<=0;
        ELSE
          i_hcpt<=i_hcpt+1;
        END IF;
        
        IF i_vs='1' THEN
          i_vcpt<=0;
          i_adrsi<=(OTHERS =>'0');
          i_vminset<='0';
          i_ad_pre<=0;
        END IF;
        
        IF i_hs='1' AND i_hs_pre='0' THEN
          i_vcpt<=i_vcpt+1;
        END IF;
        
        i_ven<=to_std_logic(i_hcpt>=i_hmin AND i_hcpt<i_hmax AND i_hs='0' AND
                            i_vcpt>=i_vmin AND i_vcpt<i_vmax AND i_vs='0');
        
        ----------------------------------------------------
        -- Auto-sizing of the input image
        IF i_iauto='1' THEN
          IF i_de='1' AND i_de_pre='0' THEN
            i_hmin<=i_hcpt;
          END IF;
          IF i_de='0' AND i_de_pre='1' THEN
            i_hmax<=i_hcpt;
          END IF;
          
          IF i_de='1' AND i_de_pre='0' AND i_vminset='0' THEN
            i_vmin<=i_vcpt;
            i_vminset<='1';
          END if;
          IF i_de='1' AND i_de_pre='0' THEN
            i_vmaxc<=i_vcpt;
          END IF;
          IF i_vs='1' THEN
            i_vmax<=i_vmaxc;
          END IF;
        ELSE
          -- Forced image
          i_hmin<=himin;
          i_hmax<=himax;
          i_vmin<=vimin;
          i_vmax<=vimax;
        END IF;
        
        i_hsize<=(4096+i_hmax-i_hmin) MOD 4096;
        i_vsize<=(4096+i_vmax-i_vmin) MOD 4096;
        
        ----------------------------------------------------
        -- Assemble pixels
        i_shift(23+24*(4-i_acpt) DOWNTO 24*(4-i_acpt))<= i_r & i_g & i_b;
        IF i_ven='1' THEN
          IF i_acpt=4 THEN
            i_acpt<=0;
            i_push<='1';
          ELSE
            i_acpt<=i_acpt+1;
          END IF;
        END IF;
        
        IF i_hs='1' AND i_hs_pre='0' THEN
          i_acpt<=0;
          IF i_acpt/=0 THEN
            i_push<='1';
          END IF;
        END IF;
        
        IF i_hs='0' AND i_hs_pre='1' AND i_vs='0' THEN
          i_hbcpt<=0; -- Bursts per line counter
          IF i_hbcpt>0 THEN
            i_hburst<=i_hbcpt;
          END IF;
          IF i_ad_pre MOD BLEN/=0 THEN
            i_ad_pre<=((i_ad_pre/BLEN+1) MOD 2)*BLEN;
          END IF;
        END IF;
        
      END IF; -- IF i_ce='1'
      
      ------------------------------------------------------
      -- Push pixels to DPRAM
      i_wr<='0';
      IF i_push='1' AND i_run='1' THEN
        i_dw<=i_shift;
        i_wr<='1';
        i_ad_pre<=(i_ad_pre+1) MOD (BLEN*2);
        IF (i_ad MOD BLEN=BLEN-1) OR i_hs='1' THEN
          i_hbcpt<=(i_hbcpt+1) MOD (HRES/N_BURST);
          i_write<=NOT i_write;
          i_adrs<=i_adrsi;
          i_adrsi<=i_adrsi+N_BURST;
        END IF;
      END IF;
      
      i_ad<=i_ad_pre;
      
    END IF;
  END PROCESS;

  -----------------------------------------------------------------------------
  -- DPRAM INPUT

  PROCESS (i_clk) IS
  BEGIN
    IF rising_edge(i_clk) THEN
      IF i_wr='1' THEN
        i_dpram(i_ad)<=i_dw;
      END IF;
    END IF;
  END PROCESS;
  
  avl_dr<=i_dpram(avl_rad_c) WHEN rising_edge(avl_clk);
  
  -----------------------------------------------------------------------------
  -- AVALON interface
  Avaloir:PROCESS(avl_clk,avl_reset_na) IS
  BEGIN
    IF avl_reset_na='0' THEN
      avl_reading<='0';
      avl_state<=sIDLE;
      avl_write_sr<='0';
      avl_read_sr<='0';
      avl_readack<='0';
      
    ELSIF rising_edge(avl_clk) THEN
      ----------------------------------
      avl_write_sync<=i_write; -- <ASYNC>
      avl_write_sync2<=avl_write_sync;
      avl_write_pulse<=avl_write_sync XOR avl_write_sync2;
      
      avl_wadrs <=i_adrs; -- <ASYNC>

      avl_vs<=i_vs; -- <ASYNC>
      ----------------------------------
      avl_read_sync<=o_read; -- <ASYNC>
      avl_read_sync2<=avl_read_sync;
      avl_read_pulse<=avl_read_sync XOR avl_read_sync2;
      
      avl_radrs <=o_adrs; -- <ASYNC>
      
      --------------------------------------------
      --avl_writedata<=std_logic_vector(avl_dr);
      avl_dw<=unsigned(avl_readdata);
      avl_read_i<='0';
      avl_write_i<='0';
      
      avl_write_sr<=(avl_write_sr OR avl_write_pulse) AND NOT avl_write_clr;
      avl_read_sr <=(avl_read_sr OR avl_read_pulse) AND NOT avl_read_clr;
      avl_write_clr<='0';
      avl_read_clr <='0';

      avl_rad<=avl_rad_c;
      
      --------------------------------------------
      CASE avl_state IS
        WHEN sIDLE =>
          avl_rad<=(avl_rad/BLEN) * BLEN;
          IF avl_vs='1' THEN
            avl_rad<=0;
          END IF;
          IF avl_write_sr='1' THEN
            avl_state<=sWRITE;
            avl_write_clr<='1';
          ELSIF avl_read_sr='1' AND avl_reading='0' THEN
            avl_wad<=2*BLEN - 1;
            avl_state<=sREAD;
            avl_read_clr<='1';
          END IF;
          
        WHEN sWRITE =>
          avl_address<=std_logic_vector(RAMBASE(N_AW+NB_LA-1 DOWNTO NB_LA) +
            avl_wadrs(N_AW+NB_LA-1 DOWNTO NB_LA));
          avl_write_i<='1';
          IF avl_write_i='1' AND avl_waitrequest='0' THEN
            IF (avl_rad MOD BLEN)=BLEN-1 THEN
              avl_write_i<='0';
              avl_state<=sIDLE;
            END IF;
          END IF;
          
        WHEN sREAD =>
          avl_address<=std_logic_vector(RAMBASE(N_AW+NB_LA-1 DOWNTO NB_LA) +
            avl_radrs(N_AW+NB_LA-1 DOWNTO NB_LA));
          avl_read_i<='1';
          avl_reading<='1';
          IF avl_read_i='1' AND avl_waitrequest='0' THEN
            avl_state<=sIDLE;
            avl_read_i<='0';
          END IF;
          
      END CASE;

      --------------------------------------------
      -- Pipelined data read
      avl_wr<='0';
      IF avl_readdatavalid='1' THEN
        avl_wr<='1';
        avl_wad<=(avl_wad+1) MOD (2*BLEN);
        IF avl_wad=BLEN-2 THEN
          avl_reading<='0';
          avl_readack<=NOT avl_readack;
        END IF;
      END IF;
      
      --------------------------------------------
    END IF;
  END PROCESS Avaloir;

  avl_read<=avl_read_i;
  avl_write<=avl_write_i;
  avl_writedata<=std_logic_vector(avl_dr);
  avl_burstcount<=std_logic_vector(to_unsigned(BLEN,8));
  avl_byteenable<=(OTHERS =>'1');
  
  avl_rad_c<=(avl_rad+1) MOD (2*BLEN)
              WHEN avl_write_i='1' AND avl_waitrequest='0' ELSE avl_rad;
  
  -----------------------------------------------------------------------------
  -- DPRAM OUTPUT
  PROCESS (avl_clk) IS
  BEGIN
    IF rising_edge(avl_clk) THEN
      IF avl_wr='1' THEN
        o_dpram(avl_wad)<=avl_dw;
      END IF;
    END IF;
  END PROCESS;
      
  o_dr<=o_dpram(o_ad) WHEN rising_edge(o_clk);
  
  -----------------------------------------------------------------------------
  -- Dividers
  o_ihsize<=i_hsize WHEN rising_edge(o_clk); -- <ASYNC>
  o_ivsize<=i_vsize WHEN rising_edge(o_clk); -- <ASYNC>
  
  --------------------------------------
  -- Hdelta = IHsize / (OHmax-OHmin)
  -- Vdelta = IVsize / (OVmax-OVmin)

  -- Division : [12] / [12] --> [12].[12]
  
  Dividers:PROCESS (o_clk,o_reset_na) IS
  BEGIN
    IF o_reset_na='0' THEN
      
    ELSIF rising_edge(o_clk) THEN
      o_hdivi<=to_unsigned(o_hmax - o_hmin,12);
      o_vdivi<=to_unsigned(o_vmax - o_vmin,12);
      o_hdivr<=to_unsigned(o_ihsize * 4096,36);
      o_vdivr<=to_unsigned(o_ivsize * 4096,36);

      --------------------------------------------
      IF o_divstart='1' THEN
        o_divcpt<=0;
        o_divrun<='1';
        
      ELSIF o_divrun='1' THEN
        ------------------------------------------
        IF o_divcpt=24 THEN
          o_divrun<='0';
          o_hdelta<=o_hdivr(22 DOWNTO 0) & NOT o_hdivr(35);
          o_vdelta<=o_vdivr(22 DOWNTO 0) & NOT o_vdivr(35);
        ELSE
          o_divcpt<=o_divcpt+1;
        END IF;
        
        ------------------------------------------
        IF o_hdivr(35)='0' THEN
          o_hdivr(35 DOWNTO 24)<=o_hdivr(34 DOWNTO 23) - o_hdivi;
        ELSE
          o_hdivr(35 DOWNTO 24)<=o_hdivr(34 DOWNTO 23) + o_hdivi;
        END IF;
        o_hdivr(23 DOWNTO 0)<=o_hdivr(22 DOWNTO 0) & NOT o_hdivr(35);
        
        IF o_vdivr(35)='0' THEN
          o_vdivr(35 DOWNTO 24)<=o_vdivr(34 DOWNTO 23) - o_vdivi;
        ELSE
          o_vdivr(35 DOWNTO 24)<=o_vdivr(34 DOWNTO 23) + o_vdivi;
        END IF;
        o_vdivr(23 DOWNTO 0)<=o_vdivr(22 DOWNTO 0) & NOT o_vdivr(35);
        
        ------------------------------------------
      END IF;
    END IF;
  END PROCESS Dividers;
  
  -----------------------------------------------------------------------------
  Scalaire:PROCESS (o_clk,o_reset_na) IS
    VARIABLE mul_v : unsigned(47 DOWNTO 0);
  BEGIN
    IF o_reset_na='0' THEN
      o_copy<='0';
      o_state<=sDISP;
      o_read<='0';
      o_readpend<='0';
      
    ELSIF rising_edge(o_clk) THEN
      ------------------------------------------------------
      o_mode   <=mode; -- <ASYNC> ?
      o_run    <=run; -- <ASYNC> ?
      
      o_htotal <=htotal; -- <ASYNC> ?
      o_hsstart<=hsstart; -- <ASYNC> ?
      o_hsend  <=hsend; -- <ASYNC> ?
      o_hdisp  <=hdisp; -- <ASYNC> ?
      o_hmin   <=hmin; -- <ASYNC> ?
      o_hmax   <=hmax; -- <ASYNC> ?
      
      o_vtotal <=vtotal; -- <ASYNC> ?
      o_vsstart<=vsstart; -- <ASYNC> ?
      o_vsend  <=vsend; -- <ASYNC> ?
      o_vdisp  <=vdisp; -- <ASYNC> ?
      o_vmin   <=vmin; -- <ASYNC> ?
      o_vmax   <=vmax; -- <ASYNC> ?
      
      o_hburst<=i_hburst; -- <ASYNC> Bursts per line
      
      ------------------------------------------------------
      -- Initial values
      mul_v:=o_hmin * o_hdelta;
      o_hini<=x"000000" - mul_v(47 DOWNTO 24);
      mul_v:=o_vmin * o_vdelta;
      o_vini<=x"000000" - mul_v(47 DOWNTO 24);
      
      ------------------------------------------------------
      
      -- End DRAM READ
      o_readack_sync<=avl_readack; -- <ASYNC>
      o_readack_sync2<=o_readack_sync;
      o_readack<=o_readack_sync XOR o_readack_sync2;
      
      o_divstart<=o_vsync_pre AND NOT o_vsync_i;
      
      o_hsync_pre<=o_hsync_i;
      o_vsync_pre<=o_vsync_i;
      
      ------------------------------------------------------
      -- Balayage
      IF o_ce='1' THEN
        -- Output pixels count
        IF o_hcpt<o_htotal THEN
          o_hcpt<=o_hcpt+1;
        ELSE
          o_hcpt<=0;
          IF o_vcpt<o_vtotal THEN
            o_vcpt<=o_vcpt+1;
          ELSE
            o_vcpt<=0;
          END IF;
        END IF;
        
        -- Input pixels position
        IF o_hcpt<o_hdisp THEN
          o_hpos<=o_hpos+o_hdelta;
        ELSIF o_hcpt=o_hdisp THEN
          o_hpos<=o_hini;
          IF o_vcpt<=o_vdisp THEN
            o_vpos<=o_vpos+o_vdelta;
          ELSE
            o_vpos<=o_vini;
          END IF;
        END IF;
        
        o_de_i<=to_std_logic(o_hcpt<o_hdisp AND o_vcpt<o_vdisp);
        o_hsync_i<=to_std_logic(o_hcpt>=o_hsstart AND o_hcpt<o_hsend);
        o_vsync_i<=to_std_logic(o_vcpt>=o_vsstart AND o_vcpt<o_vsend);
      END IF;
      
      ------------------------------------------------------
      CASE o_state IS
          --------------------------------------------------
        WHEN sDISP =>
          IF o_hsync_i='1' AND o_hsync_pre='0' THEN
            o_state<=sHSYNC;
          END IF;
          IF o_vsync_i='1' AND o_vsync_pre='0' THEN
            o_fload<=2; -- Force load 2 lines at top of screen
          END IF;
          
          --------------------------------------------------
        WHEN sHSYNC =>
          o_vpos_pre<=o_vpos;
          o_lcpt<=0; -- Clear pixel counter on line
          o_hbcpt<=0; -- Clear burst counter on line
          IF o_vpos(12)/=o_vpos_pre(12) OR o_fload>0 THEN
            o_state<=sREAD;
          ELSE
            o_state<=sDISP;
          END IF;
          
        WHEN sREAD =>
          -- Read a line. Trigger a burst
          -- <Il faut pipeliner : lecture / recopie vers RDP / recopie ligne>
          o_read<=NOT o_read;
          o_readpend<='1';
          o_state <=sWAITREAD;
          IF o_fload=2 THEN
            o_adrs<=to_unsigned((to_integer(
              o_vpos(23 DOWNTO 12)) * o_hburst + o_hbcpt) * N_BURST,32);
            o_alt<=o_vpos(12);
            
          ELSIF o_fload=1 THEN
            o_adrs<=to_unsigned((to_integer(
              o_vpos(23 DOWNTO 12)+1) * o_hburst + o_hbcpt) * N_BURST,32);
            o_alt<=NOT o_vpos(12);
          ELSE
            o_adrs<=to_unsigned((to_integer(
              o_vpos(23 DOWNTO 12)+1) * o_hburst + o_hbcpt) * N_BURST,32);
            o_alt<=NOT o_vpos(12);
          END IF;
          
        WHEN sWAITREAD =>
          IF o_readpend='0' THEN -- End copy pixels to DPRAM
            o_hbcpt<=o_hbcpt+1;
            IF o_fload=2 AND o_hbcpt=o_hburst-1 THEN
              o_fload<=1;
              o_lcpt<=0;
              o_hbcpt<=0;
              o_state<=sREAD;
            ELSIF o_fload=1 AND o_hbcpt=o_hburst-1 THEN
              o_state<=sDISP;
              o_fload<=0;
            ELSIF o_hbcpt<o_hburst-1 THEN
              -- If more lines to load, or not finshed line, read more
              o_state<=sREAD;
            ELSE
              o_state<=sDISP;
            END IF;
          END IF;
          
          --------------------------------------------------
      END CASE;
      
      ------------------------------------------------------
      -- Copy from buffered memory to pixel lines
      -- acpt : Position pixel dans le mot de 64 ou 128bits
      -- pcpt : Numéro mot dans burst
      -- lcpt : Numéro pixel dans la ligne
      IF o_copy='0' THEN
        IF o_readack='1' THEN
          o_copy<='1';
        END IF;
        o_acpt<=0; -- Alternance position pixels dans mot 64/128bits
        o_ad<=0; -- Pixels burst count
      ELSE
        o_lcpt<=o_lcpt+1; -- Pixel line count
        IF o_ad=BLEN THEN -- Pixel count
          o_copy<='0';
          o_readpend<='0';
        END IF;
        IF o_acpt=3 THEN
          o_ad<=o_ad+1;
        END IF;
        IF o_acpt=4 THEN
          o_acpt<=0;
        ELSE
          o_acpt<=o_acpt+1;
        END IF;

        o_wadl<=o_lcpt;
        o_ldw<=o_dr(23+24*(4-o_acpt) DOWNTO 24*(4-o_acpt));
      END IF;
      o_wr0<=o_copy AND NOT o_alt;
      o_wr1<=o_copy AND NOT o_alt;
      o_wr2<=o_copy AND o_alt;
      o_wr3<=o_copy AND o_alt;
      
      ------------------------------------------------------
    END IF;
  END PROCESS Scalaire;
  
  -----------------------------------------------------------------------------
  -- Line buffers 4 x (imgsize) x (R+G+B)
  OLBUF:PROCESS(o_clk) IS
  BEGIN
    IF rising_edge(o_clk) THEN
      -- WRITES
      IF o_wr0='1' THEN
        o_line0(o_wadl)<=o_ldw;
      END IF;
      IF o_wr1='1' THEN
        o_line1(o_wadl)<=o_ldw;
      END IF;
      IF o_wr2='1' THEN
        o_line2(o_wadl)<=o_ldw;
      END IF;
      IF o_wr3='1' THEN
        o_line3(o_wadl)<=o_ldw;
      END IF;

      -- READS
      o_ldr0<=o_line0(o_radl0);
      o_ldr1<=o_line1(o_radl1);
      o_ldr2<=o_line2(o_radl2);
      o_ldr3<=o_line3(o_radl3);
      
    END IF;
  END PROCESS OLBUF;
  
  -----------------------------------------------------------------------------
  -- Interpoler

  -- HPOS / VPOS
  
  --  Pixels    [0  1]
  --  position  [2  3]
  
  InterPol:PROCESS(o_clk) IS
    VARIABLE pix0_v,pix1_v,pix2_v,pix3_v : unsigned(NP-1 DOWNTO 0);
  BEGIN
    IF rising_edge(o_clk) THEN

      ------------------------------------------------------
      -- Pixel Pipeline !
      IF o_ce='1' THEN
        -- CYCLE 1 -----------------------------------------
        -- Setup RAM addresses
        o_hpos1<=o_hpos; -- delay
        o_hs1<=o_hsync_i;
        o_vs1<=o_vsync_i;
        o_de1<=o_de_i;
        
        o_radl0<=to_integer(o_hpos(23 DOWNTO 12)) MOD HRES;
        o_radl1<=to_integer(o_hpos(23 DOWNTO 12)+1) MOD HRES;
        o_radl2<=to_integer(o_hpos(23 DOWNTO 12)) MOD HRES;
        o_radl3<=to_integer(o_hpos(23 DOWNTO 12)+1) MOD HRES;

        o_vposi<=to_integer(o_vpos(23 DOWNTO 12)); -- Simu!

        -- CYCLE 2 ----------------------------------------
        -- Read mem
        o_hpos2<=o_hpos1; -- delay
        o_hs2<=o_hs1;
        o_vs2<=o_vs1;
        o_de2<=o_de1;
        
        -- CYCLE 3 ----------------------------------------
        -- Horizontal interpolation
        --o_hpos3<=o_hpos2; -- delay
        o_hs3<=o_hs2;
        o_vs3<=o_vs2;
        o_de3<=o_de2;
        
        IF o_vpos(12)='0' THEN
          pix0_v:=o_ldr0;
          pix1_v:=o_ldr1;
          pix2_v:=o_ldr2;
          pix3_v:=o_ldr3;
        ELSE
          pix0_v:=o_ldr2;
          pix1_v:=o_ldr3;
          pix2_v:=o_ldr0;
          pix3_v:=o_ldr1;
        END IF;

        CASE o_mode IS
          WHEN "0010" | "0011" => -- Hlinear, bilinear
            o_pix01<=linear(o_hpos2(11 DOWNTO 0),pix0_v,pix1_v);
            o_pix23<=linear(o_hpos2(11 DOWNTO 0),pix2_v,pix3_v);
            
          WHEN OTHERS => -- Nearest
            o_pix01<=nearest(o_hpos2(11 DOWNTO 0),pix0_v,pix1_v);
            o_pix23<=nearest(o_hpos2(11 DOWNTO 0),pix2_v,pix3_v);
            
        END CASE;
              
        -- CYCLE 4 ----------------------------------------
        -- Vertical interpolation
        --o_hpos4<=o_hpos3; -- delay
        o_hs4<=o_hs3;
        o_vs4<=o_vs3;
        o_de4<=o_de3;
        
        CASE o_mode IS
          WHEN "0011" => -- Bilinear
            o_pix<=linear(o_vpos(11 DOWNTO 0),o_pix01,o_pix23);
            
          WHEN OTHERS => -- Nearest, hlinear
            o_pix<=nearest(o_vpos(11 DOWNTO 0),o_pix01,o_pix23);
            
        END CASE;
        
        -- CYCLE 5 -----------------------------------------
        -- Outputs
        --o_hpos5<=o_hpos4;
        --o_hs5<=o_hs4;
        --o_vs5<=o_vs4;
        --o_de5<=o_de4;

        o_r<=o_pix(23 DOWNTO 16);
        o_g<=o_pix(15 DOWNTO 8);
        o_b<=o_pix(7 DOWNTO 0);
        o_hs<=o_hs4;
        o_vs<=o_vs4;
        o_de<=o_de4;
        
      END IF;
    END IF;

  END PROCESS InterPol;
  

END ARCHITECTURE rtl;
