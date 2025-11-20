library ieee;
use ieee.std_logic_1164.ALL;
use ieee.numeric_std.ALL;

library work;
use work.aud_param.all;

-- I2S master interface for the SPH0645LM4H MEMS microphone
-- Cleaned and syntactically-correct version preserving original logic.

entity i2s_master is
    generic (
        DATA_WIDTH    : natural := 32;  -- total serial frame width (bits)
        PCM_PRECISION : natural := 18   -- valid bits per sample from MEMS mic
    );
    port (
        -- system clocks
        clk      : in  std_logic; -- high-speed system clock (used for BCLK divider and FIFO handshake)
        clk_1    : in  std_logic; -- unused in this module but left for compatibility

        -- I2S interface to MEMS microphone
        i2s_lrcl : out std_logic;                    -- Word select (LRCLK): '0' = left, '1' = right
        i2s_dout : in  std_logic;                    -- Serial data input (MSB first)
        i2s_bclk : out std_logic;                    -- Bit clock output (derived locally)

        -- FIFO interface to upstream logic
        fifo_din   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
        fifo_w_stb : out std_logic;                  -- Write strobe: '1' requests write
        fifo_full  : in  std_logic                    -- Active-low fullness: '1' = not full, '0' = full
    );
end i2s_master;

architecture Behavioral of i2s_master is
    -- Local BCLK generator
    signal bclk_divider : integer := 0;       -- divider counter for generating BCLK from `clk`
    signal bclk         : std_logic := '0';  -- internal BCLK signal

    -- LRCLK / word-select generation
    signal bit_count : integer := 0;          -- counts BCLK cycles within a frame
    signal lrcl      : std_logic := '0';     -- local LRCLK (word select)

    -- I2S data capture FSM
    type capture_state_type is (CAPTURE_BITS, CLEAR_FRAME);
    signal capture_state  : capture_state_type := CAPTURE_BITS;
    signal capture_count  : integer := 0;    -- counts bits read for FSM timing
    signal sample_buffer  : std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0'); -- assembled parallel sample

    -- FIFO write-state machine
    type fifo_state_type is (FIFO_IDLE, FIFO_WRITE, FIFO_RESET);
    signal fifo_state : fifo_state_type := FIFO_WRITE;

    -- Optional / status signals (kept for compatibility)
    signal last_readable   : std_logic := '0';
    signal w_stb_internal  : std_logic := '0';
    signal last_data_sent  : std_logic := '0';

begin
    ------------------------------------------------------------------
    -- BCLK generator
    -- Derive a slower bit clock from the faster `clk` using a divider.
    ------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if bclk_divider < 15 then
                bclk_divider <= bclk_divider + 1;
            else
                bclk_divider <= 0;
                bclk <= not bclk;
            end if;
        end if;
    end process;

    -- export generated BCLK
    i2s_bclk <= bclk;

    ------------------------------------------------------------------
    -- LRCLK / Word-select generator
    -- Toggle `lrcl` every DATA_WIDTH BCLKs (word/frame boundary).
    ------------------------------------------------------------------
    process (bclk)
    begin
        if falling_edge(bclk) then
            if bit_count < (DATA_WIDTH - 1) then
                bit_count <= bit_count + 1;
            else
                bit_count <= 0;
                lrcl <= not lrcl;  -- toggle at frame boundary
            end if;
        end if;
    end process;

    -- export LRCLK
    i2s_lrcl <= lrcl;

    ------------------------------------------------------------------
    -- Serial-to-parallel capture FSM
    -- Reads `PCM_PRECISION` bits from the serial line then clears the
    -- remaining DATA_WIDTH bits before the next frame boundary.
    ------------------------------------------------------------------
    process (bclk)
    begin
        if rising_edge(bclk) then
            capture_count <= capture_count + 1;

            case capture_state is
                when CAPTURE_BITS =>
                    if capture_count < PCM_PRECISION then
                        -- Shift new bit into MSB-end of sample_buffer (MSB-first serial input)
                        sample_buffer(DATA_WIDTH - 1 downto 0) <= i2s_dout & sample_buffer(DATA_WIDTH - 1 downto 1);
                        capture_state <= CAPTURE_BITS;
                    else
                        -- After reading the valid PCM bits, move to clear state
                        capture_state <= CLEAR_FRAME;
                    end if;

                when CLEAR_FRAME =>
                    if capture_count = (DATA_WIDTH - 1) then
                        -- End of frame: reset counters and buffer
                        capture_count <= 0;
                        sample_buffer <= (others => '0');
                        capture_state <= CAPTURE_BITS;
                    else
                        capture_state <= CLEAR_FRAME;
                    end if;
            end case;
        end if;
    end process;

    ------------------------------------------------------------------
    -- FIFO handshake and write
    -- When a full parallel word is available (CLEAR_FRAME) and FIFO is
    -- not full, assert `fifo_w_stb` and present `fifo_din`.
    ------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            case fifo_state is
                when FIFO_IDLE =>
                    fifo_w_stb <= '0';
                    if capture_state = CLEAR_FRAME then
                        fifo_state <= FIFO_WRITE;
                    else
                        fifo_state <= FIFO_IDLE;
                    end if;

                when FIFO_WRITE =>
                    -- NOTE: original design used fifo_full active-low.
                    if (fifo_full = '0' and lrcl = '0') then
                        fifo_w_stb <= '1';
                        -- Align captured PCM into FIFO word: keep MSBs
                        fifo_din <= "00000000000000" & sample_buffer(31 downto 14);
                    else
                        fifo_w_stb <= '0';
                    end if;
                    fifo_state <= FIFO_RESET;

                when FIFO_RESET =>
                    fifo_w_stb <= '0';
                    if capture_state = CLEAR_FRAME then
                        fifo_state <= FIFO_RESET;
                    else
                        fifo_state <= FIFO_IDLE;
                    end if;
            end case;
        end if;
    end process;

end Behavioral;
