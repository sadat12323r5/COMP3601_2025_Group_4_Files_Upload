----------------------------------------------------------------------------------
-- Company: UNSW
-- Engineer: Ben Huntsman (z5263694)
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity audio_pipeline_TBii is
    generic(
            PCM_PRECISION : integer := 18;
            PCM_WIDTH : integer := 24;
            DATA_WIDTH : integer := 32;
            FIFO_DEPTH : integer := 5;
            TRANSFER_LEN : integer := 5;
            C_S00_AXI_DATA_WIDTH    : integer	:= 32;
            C_S00_AXI_ADDR_WIDTH	: integer	:= 5
    );
end audio_pipeline_TBii;

architecture Behavioral of audio_pipeline_TBii is
    component audio_pipeline is
        generic(
            PCM_PRECISION : integer := 18;
            PCM_WIDTH : integer := 24;
            DATA_WIDTH : integer := 32;
            FIFO_DEPTH : integer := 5;
            TRANSFER_LEN : integer := 5;
            C_S00_AXI_DATA_WIDTH    : integer	:= 32;
            C_S00_AXI_ADDR_WIDTH	: integer	:= 5
        );
        port(
            clk: in std_logic;
            rst: in std_logic;
    
            --------------------------------------------------
            -- I2S
            --------------------------------------------------
            i2s_bclk        : out std_logic;
            i2s_lrcl        : out std_logic;
            i2s_dout        : in  std_logic;
    
            --------------------------------------------------
            -- AXI4-Stream
            --------------------------------------------------
            axis_tdata      : out std_logic_vector(DATA_WIDTH-1 downto 0);
            axis_tvalid     : out std_logic;
            axis_tready     : in  std_logic;
            axis_tlast      : out std_logic;
            
            --------------------------------------------------
            -- Control interface (AXI4-Lite)
            --------------------------------------------------
            s00_axi_aclk	: in  std_logic;
            s00_axi_aresetn	: in  std_logic;
            s00_axi_awaddr	: in  std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
            s00_axi_awprot	: in  std_logic_vector(2 downto 0);
            s00_axi_awvalid	: in  std_logic;
            s00_axi_awready	: out std_logic;
            s00_axi_wdata	: in  std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
            s00_axi_wstrb	: in  std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
            s00_axi_wvalid	: in  std_logic;
            s00_axi_wready	: out std_logic;
            s00_axi_bresp	: out std_logic_vector(1 downto 0);
            s00_axi_bvalid	: out std_logic;
            s00_axi_bready	: in  std_logic;
            s00_axi_araddr	: in  std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
            s00_axi_arprot	: in  std_logic_vector(2 downto 0);
            s00_axi_arvalid	: in  std_logic;
            s00_axi_arready	: out std_logic;
            s00_axi_rdata	: out std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
            s00_axi_rresp	: out std_logic_vector(1 downto 0);
            s00_axi_rvalid	: out std_logic;
            s00_axi_rready	: in  std_logic
        );
    end component;
    
    signal sig_clk: std_logic := '0';
    signal sig_rst : std_logic := '0';
    signal sig_i2s_bclk : std_logic := '0';
    signal sig_i2s_lrcl : std_logic := '0';
    signal sig_i2s_dout : std_logic := '0';
    signal sig_axis_tdata : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal sig_axis_tvalid : std_logic := '0';
    signal sig_axis_tready : std_logic := '0';
    signal sig_axis_tlast : std_logic := '0';
    signal sig_axi_aclk : std_logic := '0';
    signal sig_axi_aresetn : std_logic := '0';
    signal sig_axi_awaddr : std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal sig_axi_awprot : std_logic_vector(2 downto 0) := (others => '0');
    signal sig_axi_awvalid : std_logic := '0';
    signal sig_axi_awready : std_logic := '0';
    signal sig_axi_wdata : std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
    signal sig_axi_wstrb : std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0) := (others => '0');
    signal sig_axi_wvalid : std_logic := '0';
    signal sig_axi_wready : std_logic := '0';
    signal sig_axi_bresp : std_logic_vector(1 downto 0) := (others => '0');
    signal sig_axi_bvalid : std_logic := '0';
    signal sig_axi_bready : std_logic := '0';
    signal sig_axi_araddr : std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal sig_axi_arprot : std_logic_vector(2 downto 0) := (others => '0');
    signal sig_axi_arvalid : std_logic := '0';
    signal sig_axi_arready : std_logic := '0';        
    signal sig_axi_rdata : std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
    signal sig_axi_rresp : std_logic_vector(1 downto 0) := (others => '0');
    signal sig_axi_rvalid : std_logic := '0';
    signal sig_axi_rready : std_logic := '0';

    constant GLOBAL_CLK_PERIOD : time := 20ns;
begin
    --global clocks
    sig_clk <= not sig_clk after (GLOBAL_CLK_PERIOD / 2);
    --sig_axi_aclk <= sig_clk;

    --test process
    process is
    begin
        wait for 5us;
        sig_rst <= '1';
        sig_axi_aresetn <= '1';
        
        wait for 1us;
        
        -- Simulate I2S serial data: toggle '0'/'1'
        for i in 0 to 4095 loop
            if(i mod 2 = 0) then
                sig_i2s_dout <= '0';
            else
                sig_i2s_dout <='1';
            end if;
            wait for ((GLOBAL_CLK_PERIOD * 3) / 2);
        end loop;
        
        wait for GLOBAL_CLK_PERIOD * 50;
        sig_axis_tready <= '1';
        
        wait for 1us;
        sig_axis_tready <= '0';
        
        -- Simulate I2S serial data: toggle '0'/'1'
        for i in 0 to 4095 loop
            if(i mod 2 = 0) then
                sig_i2s_dout <= '0';
            else
                sig_i2s_dout <='1';
            end if;
            wait for ((GLOBAL_CLK_PERIOD * 3) / 2);
        end loop;
        
        wait for 500ms;
        sig_axis_tready <= '1';
        
        wait;
    end process;
    
    --handshake test
    process(sig_clk)
    begin
      if rising_edge(sig_clk) then
        if sig_axis_tvalid='1' and sig_axis_tready='1' and sig_axis_tlast='1' then
          report "AXIS TLAST handshake seen at time " & time'image(now);
        end if;
      end if;
    end process;


    --instantiation
    uut : audio_pipeline port map(
        clk => sig_clk,
        rst => sig_rst,
        i2s_bclk => sig_i2s_bclk,
        i2s_lrcl => sig_i2s_lrcl,
        i2s_dout => sig_i2s_dout,
        axis_tdata => sig_axis_tdata,
        axis_tvalid => sig_axis_tvalid,
        axis_tready => sig_axis_tready,
        axis_tlast => sig_axis_tlast,
        s00_axi_aclk => sig_clk,
        s00_axi_aresetn => sig_axi_aresetn,
        s00_axi_awaddr => sig_axi_awaddr,
        s00_axi_awprot => sig_axi_awprot,
        s00_axi_awvalid => sig_axi_awvalid,
        s00_axi_awready => sig_axi_awready,
        s00_axi_wdata => sig_axi_wdata,
        s00_axi_wstrb => sig_axi_wstrb,
        s00_axi_wvalid => sig_axi_wvalid,
        s00_axi_wready => sig_axi_wready,
        s00_axi_bresp => sig_axi_bresp,
        s00_axi_bvalid => sig_axi_bvalid,
        s00_axi_bready => sig_axi_bready,
        s00_axi_araddr => sig_axi_araddr,
        s00_axi_arprot => sig_axi_arprot,
        s00_axi_arvalid => sig_axi_arvalid,
        s00_axi_arready => sig_axi_arready,
        s00_axi_rdata => sig_axi_rdata,
        s00_axi_rresp => sig_axi_rresp,
        s00_axi_rvalid => sig_axi_rvalid,
        s00_axi_rready => sig_axi_rready
    );

end Behavioral;
