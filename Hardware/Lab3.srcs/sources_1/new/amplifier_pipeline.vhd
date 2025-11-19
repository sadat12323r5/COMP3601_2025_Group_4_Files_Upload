----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 16.11.2025 17:03:59
-- Design Name: 
-- Module Name: amplifier_pipeline - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------
----------------------------------------------------------------------------------
-- amplifier_pipeline : DMA MM2S AXI-Stream -> FIFO -> I2S transmitter (speaker)
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.aud_param.all;

entity amplifier_pipeline is
    generic(
        PCM_PRECISION        : integer := 18;
        PCM_WIDTH            : integer := 24;
        DATA_WIDTH           : integer := 32;
        FIFO_DEPTH           : integer := 12;
        TRANSFER_LEN         : integer := 5;
        C_S00_AXI_DATA_WIDTH : integer := 32;
        C_S00_AXI_ADDR_WIDTH : integer := 5
    );
    port(
        -- Fabric clock & reset (same clock as AXI DMA)
        clk   : in  std_logic;
        rst   : in  std_logic;       -- active low

        --------------------------------------------------
        -- AXI4-Stream slave from DMA MM2S (speaker path)
        --------------------------------------------------
        s_axis_tdata  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;
        s_axis_tlast  : in  std_logic;

        --------------------------------------------------
        -- I2S to PMOD speaker
        --------------------------------------------------
        i2s_bclk_speaker : out std_logic;
        i2s_lrcl_speaker : out std_logic;
        i2s_din_speaker  : out std_logic;

        --------------------------------------------------
        -- AXI-Lite control
        --------------------------------------------------
        s00_axi_aclk    : in  std_logic;
        s00_axi_aresetn : in  std_logic;
        s00_axi_awaddr  : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
        s00_axi_awprot  : in  std_logic_vector(2 downto 0);
        s00_axi_awvalid : in  std_logic;
        s00_axi_awready : out std_logic;
        s00_axi_wdata   : in  std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
        s00_axi_wstrb   : in  std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
        s00_axi_wvalid  : in  std_logic;
        s00_axi_wready  : out std_logic;
        s00_axi_bresp   : out std_logic_vector(1 downto 0);
        s00_axi_bvalid  : out std_logic;
        s00_axi_bready  : in  std_logic;
        s00_axi_araddr  : in  std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
        s00_axi_arprot  : in  std_logic_vector(2 downto 0);
        s00_axi_arvalid : in  std_logic;
        s00_axi_arready : out std_logic;
        s00_axi_rdata   : out std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
        s00_axi_rresp   : out std_logic_vector(1 downto 0);
        s00_axi_rvalid  : out std_logic;
        s00_axi_rready  : in  std_logic
    );
end amplifier_pipeline;

architecture Behavioral of amplifier_pipeline is

    --------------------------------------------------
    -- Control registers
    --------------------------------------------------
    signal sig_control_reg    : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal sig_status_reg     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal sig_gain_reg       : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal sig_speaker_enable : std_logic := '0';   -- bit 0 (unused for now)

    --------------------------------------------------
    -- FIFO (AXIS -> FIFO -> I2S)
    --------------------------------------------------
    signal fifo_rst_s     : std_logic;
    signal fifo_wr_s      : std_logic;
    signal fifo_rd_s      : std_logic;
    signal fifo_full_s    : std_logic;
    signal fifo_empty_s   : std_logic;
    signal fifo_din_s     : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal fifo_dout_s    : std_logic_vector(DATA_WIDTH-1 downto 0);

    signal axis_tready_s_int : std_logic;

    -- internal copy of BCLK so we can use it as FIFO read clock and drive the pin
    signal i2s_bclk_int  : std_logic;

begin
    ----------------------------------------------------------------
    -- Status constant
    ----------------------------------------------------------------
    sig_status_reg <= x"0CA7CAFE";

    ----------------------------------------------------------------
    -- AXI-Lite control interface
    ----------------------------------------------------------------
    inst_ctrl_bus : ctrl_bus
    generic map(
        C_S_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
        C_S_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH
    )
    port map(
        cb_control_reg => sig_control_reg,
        cb_status_reg  => sig_status_reg,
        cb_gain_reg    => sig_gain_reg,

        S_AXI_ACLK     => s00_axi_aclk,
        S_AXI_ARESETN  => s00_axi_aresetn,
        S_AXI_AWADDR   => s00_axi_awaddr,
        S_AXI_AWPROT   => s00_axi_awprot,
        S_AXI_AWVALID  => s00_axi_awvalid,
        S_AXI_AWREADY  => s00_axi_awready,
        S_AXI_WDATA    => s00_axi_wdata,
        S_AXI_WSTRB    => s00_axi_wstrb,
        S_AXI_WVALID   => s00_axi_wvalid,
        S_AXI_WREADY   => s00_axi_wready,
        S_AXI_BRESP    => s00_axi_bresp,
        S_AXI_BVALID   => s00_axi_bvalid,
        S_AXI_BREADY   => s00_axi_bready,
        S_AXI_ARADDR   => s00_axi_araddr,
        S_AXI_ARPROT   => s00_axi_arprot,
        S_AXI_ARVALID  => s00_axi_arvalid,
        S_AXI_ARREADY  => s00_axi_arready,
        S_AXI_RDATA    => s00_axi_rdata,
        S_AXI_RRESP    => s00_axi_rresp,
        S_AXI_RVALID   => s00_axi_rvalid,
        S_AXI_RREADY   => s00_axi_rready
    );

    ----------------------------------------------------------------
    -- FIFO reset (FIFO expects active-high reset)
    ----------------------------------------------------------------
    fifo_rst_s <= not rst;  -- rst is active-low at top level

    ----------------------------------------------------------------
    -- AXI-Stream slave side (from DMA)
    ----------------------------------------------------------------
    -- Backpressure when FIFO is full (you can also AND this with sig_speaker_enable later)
    axis_tready_s_int <= '1' when fifo_full_s = '0' else '0';
    s_axis_tready     <= axis_tready_s_int;

    fifo_din_s <= s_axis_tdata;
    fifo_wr_s  <= s_axis_tvalid and axis_tready_s_int;
    -- s_axis_tlast currently ignored (stream is just continuous data)

    ----------------------------------------------------------------
    -- FIFO instance
    ----------------------------------------------------------------
    inst_fifo_speaker : entity work.fifo_speaker
    generic map(
        DATA_WIDTH => DATA_WIDTH,
        FIFO_DEPTH => FIFO_DEPTH
    )
    port map(
        clkw  => clk,      -- same clock
        clkr  => clk,      -- same clock (for now)
        rst   => fifo_rst_s,

        wr    => fifo_wr_s,
        rd    => fifo_rd_s,
        din   => fifo_din_s,
        dout  => fifo_dout_s,
        empty => fifo_empty_s,
        full  => fifo_full_s
    );

    ----------------------------------------------------------------
    -- I2S transmitter (drains FIFO)
    ----------------------------------------------------------------
    inst_i2s_tx : entity work.i2s_transmitter
    generic map(
        DATA_WIDTH    => DATA_WIDTH,
        PCM_PRECISION => PCM_PRECISION,
        BCLK_HALF     => 16   -- as before
    )
    port map(
        clk        => clk,
        rst        => fifo_rst_s,         -- active-high reset (same as FIFO)

        i2s_lrcl   => i2s_lrcl_speaker,
        i2s_din    => i2s_din_speaker,
        i2s_bclk   => i2s_bclk_int,

        fifo_data  => fifo_dout_s,
        fifo_r_stb => fifo_rd_s,
        fifo_empty => fifo_empty_s
    );

    -- Drive external BCLK pin from internal BCLK
    i2s_bclk_speaker <= i2s_bclk_int;

end Behavioral;
