----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 16.11.2025 17:04:58
-- Design Name: 
-- Module Name: i2s_transmitter - Behavioral
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
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_transmitter is
    generic (
        DATA_WIDTH    : natural := 32;   -- bits per I2S sample word
        PCM_PRECISION : natural := 18;   -- kept for compatibility, unused
        -- BCLK generator: clk / (2 * BCLK_HALF) ≈ desired BCLK
        -- e.g. clk=100MHz, BCLK_HALF=16 -> ~3.125 MHz
        BCLK_HALF     : natural := 16
    );
    port (
        clk        : in  std_logic;      -- fabric clock (same as FIFO / AXI)
        rst        : in  std_logic;      -- active-high synchronous reset

        -- I²S outputs
        i2s_lrcl   : out std_logic;      -- 0 = Left, 1 = Right (word select)
        i2s_din    : out std_logic;      -- serial data (MSB first)
        i2s_bclk   : out std_logic;      -- bit clock

        -- FIFO interface (from speaker FIFO)
        fifo_data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        fifo_r_stb : out std_logic;      -- 1-cycle pulse to pop one word
        fifo_empty : in  std_logic
    );
end i2s_transmitter;

architecture rtl of i2s_transmitter is

    ------------------------------------------------------------------------
    -- BCLK generator state
    ------------------------------------------------------------------------
    signal bclk_cnt  : unsigned(15 downto 0) := (others => '0');  -- big enough
    signal bclk      : std_logic := '0';
    signal bclk_rise : std_logic := '0';  -- 1 clk-cycle pulse on BCLK rising edge

    ------------------------------------------------------------------------
    -- LRCLK + per-channel bit counting
    ------------------------------------------------------------------------
    -- LRCLK toggles every 32 BCLK rising edges:
    -- 32 bits left, 32 bits right  => full LR frame = 64 BCLKs
    signal lrclk        : std_logic := '0';
    signal lr_bclk_cnt  : unsigned(5 downto 0) := (others => '0');  -- 0..31

    ------------------------------------------------------------------------
    -- I²S shifter state
    ------------------------------------------------------------------------
    signal bit_idx     : unsigned(5 downto 0) := (others => '0');   -- 0..31
    signal msb_hold    : std_logic := '0';      -- 1-BCLK MSB delay after LR edge
    signal sample_buf  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal i2s_din_reg : std_logic := '0';

begin

    ------------------------------------------------------------------------
    -- Drive outputs
    ------------------------------------------------------------------------
    i2s_bclk <= bclk;
    i2s_lrcl <= lrclk;
    i2s_din  <= i2s_din_reg;

    ------------------------------------------------------------------------
    -- Main sequential process: everything in 'clk' domain
    ------------------------------------------------------------------------
    process (clk)
        variable new_channel : std_logic;
        variable idx_int     : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                ----------------------------------------------------------------
                -- Reset all internal state
                ----------------------------------------------------------------
                bclk_cnt    <= (others => '0');
                bclk        <= '0';
                bclk_rise   <= '0';

                lrclk       <= '0';
                lr_bclk_cnt <= (others => '0');

                bit_idx     <= (others => '0');
                msb_hold    <= '0';
                sample_buf  <= (others => '0');

                fifo_r_stb  <= '0';
                i2s_din_reg <= '0';

            else
                ----------------------------------------------------------------
                -- Default strobes
                ----------------------------------------------------------------
                fifo_r_stb <= '0';
                bclk_rise  <= '0';
                new_channel := '0';

                ----------------------------------------------------------------
                -- BCLK generator: toggle every BCLK_HALF cycles
                ----------------------------------------------------------------
                if bclk_cnt = to_unsigned(BCLK_HALF-1, bclk_cnt'length) then
                    bclk_cnt <= (others => '0');

                    -- use old bclk value to detect rising edge
                    if bclk = '0' then
                        bclk      <= '1';
                        bclk_rise <= '1';   -- this is a rising edge
                    else
                        bclk      <= '0';   -- falling edge
                    end if;
                else
                    bclk_cnt <= bclk_cnt + 1;
                end if;

                ----------------------------------------------------------------
                -- On each BCLK rising edge: update LRCLK, shifter, FIFO pops
                ----------------------------------------------------------------
                if bclk_rise = '1' then
                    ------------------------------------------------------------
                    -- LRCLK: toggle every 32 BCLK rising edges
                    ------------------------------------------------------------
                    if lr_bclk_cnt = to_unsigned(31, lr_bclk_cnt'length) then
                        lr_bclk_cnt <= (others => '0');
                        lrclk       <= not lrclk;  -- new channel window (L/R)
                        new_channel := '1';
                    else
                        lr_bclk_cnt <= lr_bclk_cnt + 1;
                    end if;

                    --------------------------------------------------------
                    -- I²S shifter w/ MSB delay and LR-aligned fetch
                    --------------------------------------------------------
                    if new_channel = '1' then
                        -- Start of a left or right channel frame
                        bit_idx  <= to_unsigned(DATA_WIDTH-1, bit_idx'length);
                        msb_hold <= '1';

                        if fifo_empty = '0' then
                            sample_buf <= fifo_data;
                            fifo_r_stb <= '1';  -- one pop per channel frame
                        else
                            sample_buf <= (others => '0');
                        end if;

                        -- Do NOT update i2s_din_reg here: enforce MSB delay

                    else
                        -- Within current channel frame
                        if msb_hold = '1' then
                            -- 1-BCLK delay after LR edge: now output MSB
                            msb_hold <= '0';

                            idx_int := to_integer(bit_idx);
                            if idx_int >= 0 and idx_int < DATA_WIDTH then
                                i2s_din_reg <= sample_buf(idx_int);
                            else
                                i2s_din_reg <= '0';
                            end if;

                        else
                            -- Shift through remaining bits
                            idx_int := to_integer(bit_idx);
                            if idx_int >= 0 and idx_int < DATA_WIDTH then
                                i2s_din_reg <= sample_buf(idx_int);
                            else
                                i2s_din_reg <= '0';
                            end if;

                            if bit_idx /= to_unsigned(0, bit_idx'length) then
                                bit_idx <= bit_idx - 1;
                            end if;
                        end if;
                    end if;
                end if; -- bclk_rise
            end if; -- rst
        end if; -- rising_edge(clk)
    end process;

end rtl;

