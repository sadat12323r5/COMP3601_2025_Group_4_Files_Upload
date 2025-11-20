----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 19.11.2025 07:48:37
-- Design Name: 
-- Module Name: dynamics_core - Behavioral
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

entity dynamics_core is
    generic (
        SAMPLE_WIDTH : integer := 24;

        -- thresholds are magnitudes in raw sample units (0 .. 2^(SAMPLE_WIDTH-1)-1)
        GATE_LEVEL   : integer := 2**15;  -- below this, treat as noise → gate
        BOOST_LEVEL  : integer := 2**18;  -- below this, apply boost
        COMP_LEVEL   : integer := 2**20;  -- above this, apply compression

        -- gain factors implemented as shifts
        BOOST_SHIFT  : integer := 1;      -- +6 dB approx (×2)
        COMP_SHIFT   : integer := 1       -- -6 dB approx (/2)
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;  -- active high

        x_in     : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0); -- filtered audio
        env_in   : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0); -- envelope
        x_valid  : in  std_logic;

        y_out    : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        y_valid  : out std_logic
    );
end entity dynamics_core;

architecture rtl of dynamics_core is
    signal y_s       : signed(SAMPLE_WIDTH-1 downto 0);
    signal valid_reg : std_logic;
begin

    process(clk)
        variable x_s      : signed(SAMPLE_WIDTH-1 downto 0);
        variable env_mag  : unsigned(SAMPLE_WIDTH-1 downto 0);
        variable y_tmp    : signed(SAMPLE_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                y_s       <= (others => '0');
                valid_reg <= '0';
            else
                if x_valid = '1' then
                    valid_reg <= '1';

                    -- cast inputs
                    x_s     := signed(x_in);
                    env_mag := unsigned(env_in);  -- envelope is non-negative

                    -- region selection based on envelope magnitude
                    if env_mag < to_unsigned(GATE_LEVEL, SAMPLE_WIDTH) then
                        -- 1) Noise gate: very quiet → mute
                        y_tmp := (others => '0');

                    elsif env_mag < to_unsigned(BOOST_LEVEL, SAMPLE_WIDTH) then
                        -- 2) Expansion / boost for quiet-but-not-noise
                        y_tmp := shift_left(x_s, BOOST_SHIFT);

                    elsif env_mag < to_unsigned(COMP_LEVEL, SAMPLE_WIDTH) then
                        -- 3) Unity region: normal speech/music
                        y_tmp := x_s;

                    else
                        -- 4) Compression / limiting region for loud peaks
                        y_tmp := shift_right(x_s, COMP_SHIFT);
                    end if;

                    y_s <= y_tmp;

                else
                    -- no new sample this cycle
                    valid_reg <= '0';
                end if;
            end if;
        end if;
    end process;

    y_out   <= std_logic_vector(y_s);
    y_valid <= valid_reg;

end architecture rtl;
