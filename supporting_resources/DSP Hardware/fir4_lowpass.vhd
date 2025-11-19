----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 19.11.2025 06:56:48
-- Design Name: 
-- Module Name: fir4_lowpass - Behavioral
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

entity fir4_lowpass is
    generic (
        SAMPLE_WIDTH : integer := 24  -- width of input/output samples
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;  -- active high synchronous reset

        x_in    : in  std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        x_valid : in  std_logic;

        y_out   : out std_logic_vector(SAMPLE_WIDTH-1 downto 0);
        y_valid : out std_logic
    );
end entity fir4_lowpass;

architecture rtl of fir4_lowpass is

    -- internal sample registers (tap delay line)
    signal x0, x1, x2, x3 : signed(SAMPLE_WIDTH-1 downto 0);

    -- accumulator width: input width + few guard bits
    constant ACC_WIDTH : integer := SAMPLE_WIDTH + 4;
    signal acc         : signed(ACC_WIDTH-1 downto 0);
    signal acc_scaled  : signed(ACC_WIDTH-1 downto 0);

    signal y_s         : signed(SAMPLE_WIDTH-1 downto 0);

    -- delay line for valid flag so it lines up with y_s
    signal v_shift     : std_logic_vector(3 downto 0);

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                x0      <= (others => '0');
                x1      <= (others => '0');
                x2      <= (others => '0');
                x3      <= (others => '0');
                acc     <= (others => '0');
                acc_scaled <= (others => '0');
                y_s     <= (others => '0');
                v_shift <= (others => '0');
            else
                -- valid pipeline
                v_shift <= v_shift(2 downto 0) & x_valid;

                -- update tap delay line on each valid input sample
                if x_valid = '1' then
                    x3 <= x2;
                    x2 <= x1;
                    x1 <= x0;
                    x0 <= signed(x_in);
                end if;

                -- multiply-accumulate using coefficients [1,3,3,1]
                acc <=
                    resize(x0, ACC_WIDTH) +
                    resize(x1 * 3, ACC_WIDTH) +
                    resize(x2 * 3, ACC_WIDTH) +
                    resize(x3, ACC_WIDTH);

                -- divide by 8 → arithmetic right shift by 3
                acc_scaled <= shift_right(acc, 3);

                -- resize back to SAMPLE_WIDTH for output
                y_s <= resize(acc_scaled, SAMPLE_WIDTH);
            end if;
        end if;
    end process;

    y_out   <= std_logic_vector(y_s);
    y_valid <= v_shift(3);  -- output valid delayed to match filter pipeline

end architecture rtl;

