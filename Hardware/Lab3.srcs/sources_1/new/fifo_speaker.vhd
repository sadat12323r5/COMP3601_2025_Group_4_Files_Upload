----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 18.11.2025 11:49:57
-- Design Name: 
-- Module Name: fifo_speaker - Behavioral
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

entity fifo_speaker is
    generic (
        DATA_WIDTH : positive := 32;
        FIFO_DEPTH : positive := 5      -- depth = 2**FIFO_DEPTH
    );
    port (
        clkw  : in  std_logic;  -- WRITE clock  (use as main clk)
        clkr  : in  std_logic;  -- READ  clock  (tie to same clk for now)
        rst   : in  std_logic;  -- active-high synchronous reset

        wr    : in  std_logic;  -- write enable
        rd    : in  std_logic;  -- read enable

        din   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        dout  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        empty : out std_logic;
        full  : out std_logic
    );
end fifo_speaker;

architecture arch of fifo_speaker is

    constant DEPTH : integer := 2**FIFO_DEPTH;

    type fifo_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mem : fifo_t;

    -- extra MSB bit for full/empty detection
    signal wrp : unsigned(FIFO_DEPTH downto 0) := (others => '0');
    signal rdp : unsigned(FIFO_DEPTH downto 0) := (others => '0');

    signal dout_reg  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal empty_reg : std_logic := '1';
    signal full_reg  : std_logic := '0';

begin

    --------------------------------------------------------------------
    -- Status flags
    --  empty when pointers equal
    --  full  when lower bits equal but MSB differs
    --------------------------------------------------------------------
    empty_reg <= '1' when (wrp = rdp) else '0';

    full_reg  <= '1' when
        (wrp(FIFO_DEPTH) /= rdp(FIFO_DEPTH)) and
        (wrp(FIFO_DEPTH-1 downto 0) = rdp(FIFO_DEPTH-1 downto 0))
        else '0';

    empty <= empty_reg;
    full  <= full_reg;

    dout  <= dout_reg;

    --------------------------------------------------------------------
    -- Single-clock FIFO implementation
    -- Use clkw as the only real clock; clkr is ignored for now.
    --------------------------------------------------------------------
    process (clkw)
    begin
        if rising_edge(clkw) then
            if rst = '1' then
                wrp      <= (others => '0');
                rdp      <= (others => '0');
                dout_reg <= (others => '0');

            else
                -- WRITE
                if (wr = '1') and (full_reg = '0') then
                    mem(to_integer(wrp(FIFO_DEPTH-1 downto 0))) <= din;
                    wrp <= wrp + 1;
                end if;

                -- READ
                if (rd = '1') and (empty_reg = '0') then
                    dout_reg <= mem(to_integer(rdp(FIFO_DEPTH-1 downto 0)));
                    rdp      <= rdp + 1;
                end if;
            end if;
        end if;
    end process;

    -- dummy use of clkr to avoid "unused" warnings (no functional effect)
    UNUSED_CLKR_PROC : process(clkr)
    begin
        if rising_edge(clkr) then
            -- no-op
            null;
        end if;
    end process;

end arch;

