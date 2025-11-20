library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity I2S_FIFO_TB is
end I2S_FIFO_TB;

architecture testbench of I2S_FIFO_TB is
    
    -- Constants
    constant CLK_PERIOD : time := 10 ns;
    constant DATA_WIDTH : natural := 32;
    constant FIFO_DEPTH : positive := 5;
    
    -- Clock and reset
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal test_done : boolean := false;
    
    -- I2S signals
    signal i2s_lrcl : std_logic;
    signal i2s_dout : std_logic := '0';
    signal i2s_bclk : std_logic;
    
    -- Interconnect signals
    signal fifo_din : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal fifo_w_stb : std_logic;
    signal fifo_full : std_logic;
    signal fifo_empty : std_logic;
    signal fifo_dout : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal fifo_rd : std_logic := '0';
    
    -- Test data
    type test_array is array (0 to 7) of std_logic_vector(31 downto 0);
    constant TEST_DATA : test_array := (
        X"00000000", X"FFFFFFFF", X"AAAAAAAA", X"55555555",
        X"DEADBEEF", X"CAFEBABE", X"12345678", X"ABCDEF00"
    );
    
begin

    -- Clock generation
    clk_proc: process
    begin
        while not test_done loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;
    
    -- Reset generation
    rst_proc: process
    begin
        rst <= '1';
        wait for 50 ns;
        rst <= '0';
        wait;
    end process;
    
    -- I2S Master DUT
    i2s_inst: entity work.i2s_master
        generic map (DATA_WIDTH => DATA_WIDTH, PCM_PRECISION => 18)
        port map (
            clk => clk, i2s_lrcl => i2s_lrcl, i2s_dout => i2s_dout,
            i2s_bclk => i2s_bclk, fifo_din => fifo_din,
            fifo_w_stb => fifo_w_stb, fifo_full => fifo_full
        );
    
    -- FIFO DUT
    fifo_inst: entity work.fifo
        generic map (DATA_WIDTH => DATA_WIDTH, FIFO_DEPTH => FIFO_DEPTH)
        port map (
            clkw => clk, clkr => clk, rst => rst,
            wr => fifo_w_stb, rd => fifo_rd, din => fifo_din,
            empty => fifo_empty, full => fifo_full, dout => fifo_dout
        );
    
    -- I2S Microphone Simulator
    -- Per lecture slide 10: Slave outputs data on FALLING edge of BCLK
    -- (so master samples on falling edge, data is stable on rising edge)
    i2s_sim: process
        variable l : line;
        
        procedure send_sample(constant data : std_logic_vector(31 downto 0)) is
        begin
            wait until i2s_lrcl = '0';
            wait until rising_edge(i2s_bclk);
            for i in 31 downto 0 loop
                -- Microphone (slave) changes data on rising edge
                -- So it's stable when master samples on falling edge
                i2s_dout <= data(i);
                wait until rising_edge(i2s_bclk);  -- Wait for next bit time
            end loop;
        end procedure;
        
    begin
        wait for 100 ns;
        
        report "=== Sending I2S samples ===";
        for i in 0 to 7 loop
            send_sample(TEST_DATA(i));
            write(l, string'("Sent sample "));
            write(l, i);
            write(l, string'(": 0x"));
            hwrite(l, TEST_DATA(i));
            report l.all;
            deallocate(l);
            wait for 2 us;
        end loop;
        
        report "I2S transmission complete";
        wait;
    end process;
    
    -- FIFO Reader and Verifier
    verify: process
        variable l : line;
        variable errors : integer := 0;
    begin
        wait for 200 ns;
        
        report "=== Reading and verifying FIFO ===";
        for i in 0 to 7 loop
            -- Wait for data
            wait until fifo_empty = '0';
            wait until rising_edge(clk);
            
            -- Read
            fifo_rd <= '1';
            wait until rising_edge(clk);
            fifo_rd <= '0';
            wait for 1 ns;
            
            -- Verify
            if fifo_dout = TEST_DATA(i) then
                write(l, string'("PASS: Sample "));
                write(l, i);
                write(l, string'(" = 0x"));
                hwrite(l, fifo_dout);
                report l.all;
                deallocate(l);
            else
                write(l, string'("FAIL: Sample "));
                write(l, i);
                write(l, string'(" - Got 0x"));
                hwrite(l, fifo_dout);
                write(l, string'(", Expected 0x"));
                hwrite(l, TEST_DATA(i));
                report l.all severity error;
                deallocate(l);
                errors := errors + 1;
            end if;
            
            wait for 50 ns;
        end loop;
        
        -- Final report
        report "========================================";
        if errors = 0 then
            report "ALL TESTS PASSED!";
        else
            write(l, string'("TESTS FAILED - Errors: "));
            write(l, errors);
            report l.all severity error;
            deallocate(l);
        end if;
        report "========================================";
        
        test_done <= true;
        wait;
    end process;
    
    -- Monitor
    monitor: process
        variable l : line;
    begin
        wait until rising_edge(clk);
        if fifo_w_stb = '1' then
            write(l, string'("  FIFO Write: 0x"));
            hwrite(l, fifo_din);
            report l.all;
            deallocate(l);
        end if;
    end process;

end testbench;