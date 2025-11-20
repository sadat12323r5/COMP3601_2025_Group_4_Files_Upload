----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 19.11.2025 07:36:27
-- Design Name: 
-- Module Name: envelope_follower - Behavioral
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

entity envelope_follower is
    generic (
        SAMPLE_WIDTH : integer := 24;   -- same width as FIR output
        SHIFT_ATTACK : integer := 3;    -- attack time constant (2^3 = 8)
        SHIFT_RELEASE: integer := 6     -- release time constant (2^6 = 64)
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;       -- active high

        x_in    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        x_valid : in  std_logic;

        env_out : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        env_valid : out std_logic
    );
end entity envelope_follower;

architecture rtl of envelope_follower is
    signal x_abs : signed(SAMPLE_WIDTH-1 downto 0);
    signal env   : signed(SAMPLE_WIDTH-1 downto 0);
begin

    process(clk)
        variable diff : signed(SAMPLE_WIDTH-1 downto 0);
        variable adj  : signed(SAMPLE_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                env <= (others => '0');
            else
                if x_valid = '1' then

                    -- absolute value
                    if x_in(SAMPLE_WIDTH-1) = '1' then
                        x_abs <= -signed(x_in);
                    else
                        x_abs <= signed(x_in);
                    end if;

                    -- compute difference
                    diff := x_abs - env;

                    -- choose attack or release
                    if diff > 0 then
                        -- fast attack → shift by SHIFT_ATTACK
                        adj := shift_right(diff, SHIFT_ATTACK);
                        env <= env + adj;
                    else
                        -- slow release → shift by SHIFT_RELEASE
                        adj := shift_right(diff, SHIFT_RELEASE);
                        env <= env + adj;
                    end if;
                end if;
            end if;
        end if;
    end process;

    env_out   <= std_logic_vector(env);
    env_valid <= x_valid;

end architecture rtl;
