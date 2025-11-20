library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_transmitter_tb is
end i2s_transmitter_tb;

architecture sim of i2s_transmitter_tb is

    --------------------------------------------------------------------
    -- DUT generics
    --------------------------------------------------------------------
    constant DATA_WIDTH_C    : natural := 32;
    constant PCM_PRECISION_C : natural := 18;  -- unused by DUT but kept
    constant BCLK_HALF_C     : natural := 8;   -- faster BCLK for sim

    --------------------------------------------------------------------
    -- DUT I/O signals
    --------------------------------------------------------------------
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';

    signal i2s_lrcl   : std_logic;
    signal i2s_din    : std_logic;
    signal i2s_bclk   : std_logic;

    signal fifo_data  : std_logic_vector(DATA_WIDTH_C-1 downto 0);
    signal fifo_r_stb : std_logic;
    signal fifo_empty : std_logic := '0';      -- 0 = not empty (has data)

    --------------------------------------------------------------------
    -- "FIFO" sample - constant pattern to serialize
    --------------------------------------------------------------------
    constant FIFO_SAMPLE : std_logic_vector(DATA_WIDTH_C-1 downto 0) :=
        x"ABCD1234";   -- recognisable 32-bit word

    --------------------------------------------------------------------
    -- Monitor-side helpers
    --------------------------------------------------------------------
    signal prev_bclk  : std_logic := '0';
    signal bit_count  : integer range 0 to DATA_WIDTH_C := 0;
    signal cap_word   : std_logic_vector(DATA_WIDTH_C-1 downto 0)
                        := (others => '0');

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

    --------------------------------------------------------------------
    -- Reset: hold high for a short time, then release
    --------------------------------------------------------------------
    rst_process : process
    begin
        rst <= '1';
        wait for 200 ns;  -- 20 clock cycles
        rst <= '0';
        wait;
    end process;

    --------------------------------------------------------------------
    -- Constant "FIFO" source
    --------------------------------------------------------------------
    fifo_data  <= FIFO_SAMPLE;
    fifo_empty <= '0';   -- always has data, so DUT can keep popping

    --------------------------------------------------------------------
    -- DUT instantiation
    --------------------------------------------------------------------
    uut : entity work.i2s_transmitter
        generic map (
            DATA_WIDTH    => DATA_WIDTH_C,
            PCM_PRECISION => PCM_PRECISION_C,
            BCLK_HALF     => BCLK_HALF_C
        )
        port map (
            clk        => clk,
            rst        => rst,
            i2s_lrcl   => i2s_lrcl,
            i2s_din    => i2s_din,
            i2s_bclk   => i2s_bclk,
            fifo_data  => fifo_data,
            fifo_r_stb => fifo_r_stb,
            fifo_empty => fifo_empty
        );

    --------------------------------------------------------------------
    -- Monitor 1: report FIFO pops (one per channel frame)
    --------------------------------------------------------------------
    monitor_fifo : process(clk)
    begin
        if rising_edge(clk) then

            -- detect rising edge *before updating prev_bclk*
            if prev_bclk = '0' and i2s_bclk = '1' then
                -- shift MSB-first
                cap_word <= i2s_din & cap_word(31 downto 1);
                bit_count <= bit_count + 1;
            end if;

            -- now update prev_bclk AFTER using it
            prev_bclk <= i2s_bclk;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Monitor 2: reconstruct 32-bit words from I²S serial output
    --
    --  - Ignores activity while rst = '1'
    --  - Realigns bit_count at each fifo_r_stb (start of new channel frame)
    --  - Samples on BCLK rising edges
    --  - Shifts MSB-first: new bit goes into MSB of cap_word
    --------------------------------------------------------------------
    capture_word : process(clk)
        variable as_unsigned : unsigned(DATA_WIDTH_C-1 downto 0);
    begin
        if rising_edge(clk) then
            prev_bclk <= i2s_bclk;

            if rst = '1' then
                bit_count <= 0;
                cap_word  <= (others => '0');
            else
                -- realign at start of each channel frame
                if fifo_r_stb = '1' then
                    bit_count <= 0;
                    cap_word  <= (others => '0');
                end if;

                -- detect BCLK rising edge
                if prev_bclk = '0' and i2s_bclk = '1' then
                    -- MSB-first insert: new bit into MSB
                    cap_word <= i2s_din & cap_word(DATA_WIDTH_C-1 downto 1);
                    bit_count <= bit_count + 1;

                    if bit_count = DATA_WIDTH_C-1 then
                        as_unsigned := unsigned(cap_word);
                        report "Captured word (unsigned) = " &
                               integer'image(to_integer(as_unsigned)) &
                               "  LR=" & std_logic'image(i2s_lrcl);
                        bit_count <= 0;
                        cap_word  <= (others => '0');
                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Simulation end
    --------------------------------------------------------------------
    end_sim : process
    begin
        -- Let it run for a few LR frames
        wait for 5 ms;
        report "Simulation finished." severity note;
        wait;
    end process;

end sim;


