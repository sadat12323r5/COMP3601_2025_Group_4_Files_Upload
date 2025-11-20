----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 16.10.2025 13:31:43
-- Design Name: 
-- Module Name: i2s_master_tb - Behavioral
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

entity i2s_master_tb is
end i2s_master_tb;

architecture sim of i2s_master_tb is

    --------------------------------------------------------------------
    -- DUT generics
    --------------------------------------------------------------------
    constant DATA_WIDTH_C    : natural := 32;
    constant PCM_PRECISION_C : natural := 18;

    --------------------------------------------------------------------
    -- DUT I/O signals
    --------------------------------------------------------------------
    signal clk        : std_logic := '0';
    signal clk_1      : std_logic := '0';

    signal i2s_lrcl   : std_logic;
    signal i2s_dout   : std_logic := '0';
    signal i2s_bclk   : std_logic;

    signal fifo_din   : std_logic_vector(DATA_WIDTH_C - 1 downto 0);
    signal fifo_w_stb : std_logic;
    -- NOTE: your RTL treats fifo_full = '0' as "OK to write"
    signal fifo_full  : std_logic := '0';

    --------------------------------------------------------------------
    -- I²S stimulus helpers
    --------------------------------------------------------------------
    -- 18-bit "fake audio" pattern: 1010... for easy spotting
    constant SAMPLE_WORD : std_logic_vector(PCM_PRECISION_C - 1 downto 0) :=
        "101010101010101010";

    -- local counter for bits within a 32-bit frame
    signal tb_bit_index : integer range 0 to DATA_WIDTH_C - 1 := 0;

begin

    --------------------------------------------------------------------
    -- 100 MHz system clock (10 ns period)
    --------------------------------------------------------------------
    clk_process : process
    begin
        clk <= '0';
        wait for 5 ns;
        clk <= '1';
        wait for 5 ns;
    end process;

    -- clk_1 is unused in DUT; just tie it to clk
    clk_1 <= clk;

    --------------------------------------------------------------------
    -- DUT instantiation
    --------------------------------------------------------------------
    uut : entity work.i2s_master
        generic map (
            DATA_WIDTH    => DATA_WIDTH_C,
            PCM_PRECISION => PCM_PRECISION_C
        )
        port map (
            clk        => clk,
            clk_1      => clk_1,
            i2s_lrcl   => i2s_lrcl,
            i2s_dout   => i2s_dout,
            i2s_bclk   => i2s_bclk,
            fifo_din   => fifo_din,
            fifo_w_stb => fifo_w_stb,
            fifo_full  => fifo_full
        );

    --------------------------------------------------------------------
    -- I²S serial data driver
    --
    -- Behaviour:
    --   - On every rising edge of i2s_bclk:
    --       * For the first PCM_PRECISION_C bits of each 32-bit frame,
    --         drive SAMPLE_WORD MSB-first.
    --       * For the remaining bits, drive '0'.
    --   - Local frame counter tb_bit_index wraps every 32 bits, so the
    --     pattern repeats each I²S frame.
    --------------------------------------------------------------------
    drive_i2s_dout : process(clk)
        begin
            if rising_edge(clk) then
                -- Drive data only when LRCLK = 0 (left channel)
                if i2s_lrcl = '0' then
                    if tb_bit_index < PCM_PRECISION_C then
                        i2s_dout <= SAMPLE_WORD(tb_bit_index);
                    else
                        i2s_dout <= '0';
                    end if;
        
                    tb_bit_index <= (tb_bit_index + 1) mod DATA_WIDTH_C;
                else
                    i2s_dout <= '0';
                    tb_bit_index <= 0;
                end if;
            end if;
        end process;

    --------------------------------------------------------------------
    -- Monitor: log FIFO writes (unsigned value only)
    --------------------------------------------------------------------
    monitor_fifo : process(clk)
        variable as_unsigned : unsigned(fifo_din'range);
    begin
        if rising_edge(clk) then
            if fifo_w_stb = '1' then
                as_unsigned := unsigned(fifo_din);
                report "FIFO write @ " & time'image(now) &
                       "  unsigned value = " &
                       integer'image(to_integer(as_unsigned));
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Simulation end
    --------------------------------------------------------------------
    end_sim : process
    begin
        -- let it run long enough for many frames
        wait for 2 ms;
        report "Simulation finished." severity note;
        wait;
    end process;

end sim;
