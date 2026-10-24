----------------------------------------------------------------------------------
-- irig_b_tx: IRIG-B DC level shift (B00x) time-code generator
--
-- Sends one 100-bit frame per second (frame layout: irig_b_pkg). A frame
-- starts on the rising edge of PPS_IN (EXT_PPS = true) or every CLK_HZ clocks
-- from enable (EXT_PPS = false), and carries the time on the *_IN ports as
-- sampled on that start clock. That time is the time of the frame's on-time
-- point, so it must already be the new second when PPS_IN rises.
-- FRAME_START_OUT pulses one clock after the start clock, which is the
-- moment to present the next second's time.
--
-- Timing:
--   IRIG_OUT rises 2 clocks after the clock edge that first samples PPS_IN
--   high (1 clock after FRAME_START_OUT). Every bit lasts exactly CLK_HZ/100
--   clocks, so the 100th bit ends exactly CLK_HZ clocks after the start.
--   With EXT_PPS, a PPS that comes early restarts the frame at once (the last
--   bit is cut short); one that comes late leaves the line idle (low) in
--   between. Without a PPS the line stays idle after bit 99.
--   PPS_IN must be synchronous to CLK.
--
-- CLK_HZ must be a multiple of 1000 (pulse widths are whole milliseconds).
-- INVERT flips the output (idle high). EN = 0 holds the line idle.
--
-- VHDL-93.
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.irig_b_pkg.all;

entity irig_b_tx is
  generic (
    CLK_HZ  : positive := 100000000;
    EXT_PPS : boolean  := true;
    INVERT  : boolean  := false
  );
  port (
    CLK             : in  std_logic;
    RST             : in  std_logic;
    EN              : in  std_logic;
    PPS_IN          : in  std_logic;
    SEC_IN          : in  unsigned(5 downto 0);
    MIN_IN          : in  unsigned(5 downto 0);
    HOUR_IN         : in  unsigned(4 downto 0);
    DAY_IN          : in  unsigned(8 downto 0);
    YEAR_IN         : in  unsigned(6 downto 0);
    CF_IN           : in  std_logic_vector(17 downto 0);
    SBS_IN          : in  unsigned(16 downto 0);
    FRAME_START_OUT : out std_logic;
    IRIG_OUT        : out std_logic
  );
end entity irig_b_tx;

architecture rtl of irig_b_tx is

  constant MS       : positive := CLK_HZ / 1000;
  constant BIT_CLKS : positive := 10 * MS;
  constant HI_ZERO  : positive := 2 * MS;
  constant HI_ONE   : positive := 5 * MS;
  constant HI_MARK  : positive := 8 * MS;
  constant MARKS    : irig_frame_t := irig_marker_mask;

  function to_sl(b : boolean) return std_logic is
  begin
    if b then
      return '1';
    end if;
    return '0';
  end function;
  constant INV : std_logic := to_sl(INVERT);

  signal pps_d   : std_logic := '0';
  signal running : std_logic := '0';
  signal bit_idx : integer range 0 to IRIG_NBITS-1 := 0;
  signal cnt     : integer range 0 to BIT_CLKS-1 := 0;
  signal sec_cnt : integer range 0 to CLK_HZ-1 := CLK_HZ-1;
  signal t_lat   : irig_time_t := IRIG_TIME_ZERO;
  signal data    : irig_frame_t := (others => '0');
  signal out_r   : std_logic := '0';
  signal fs_r    : std_logic := '0';

begin

  assert CLK_HZ mod 1000 = 0
    report "irig_b_tx: CLK_HZ must be a multiple of 1000" severity failure;

  process (CLK)
    variable start : boolean;
    variable hl    : natural;
  begin
    if rising_edge(CLK) then
      -- t_lat changes only on a start clock; bit 0 is a marker, so data has
      -- 10 ms to catch up.
      data  <= irig_encode(t_lat);
      fs_r  <= '0';
      start := false;

      if RST = '1' or EN = '0' then
        running <= '0';
        bit_idx <= 0;
        cnt     <= 0;
        sec_cnt <= CLK_HZ-1;            -- internal mode: first frame at once
        out_r   <= '0';
      else
        -- line level for the current position
        if running = '1' then
          if MARKS(bit_idx) = '1' then
            hl := HI_MARK;
          elsif data(bit_idx) = '1' then
            hl := HI_ONE;
          else
            hl := HI_ZERO;
          end if;
          if cnt < hl then
            out_r <= '1';
          else
            out_r <= '0';
          end if;
        else
          out_r <= '0';
        end if;

        -- frame start
        if EXT_PPS then
          start := PPS_IN = '1' and pps_d = '0';
        elsif sec_cnt = CLK_HZ-1 then
          sec_cnt <= 0;
          start   := true;
        else
          sec_cnt <= sec_cnt + 1;
        end if;

        if start then
          running     <= '1';
          bit_idx     <= 0;
          cnt         <= 0;
          t_lat.sec   <= SEC_IN;
          t_lat.min   <= MIN_IN;
          t_lat.hour  <= HOUR_IN;
          t_lat.day   <= DAY_IN;
          t_lat.year  <= YEAR_IN;
          t_lat.cf    <= CF_IN;
          t_lat.sbs   <= SBS_IN;
          fs_r        <= '1';
        elsif running = '1' then
          if cnt = BIT_CLKS-1 then
            cnt <= 0;
            if bit_idx = IRIG_NBITS-1 then
              running <= '0';           -- frame done; wait for the next start
            else
              bit_idx <= bit_idx + 1;
            end if;
          else
            cnt <= cnt + 1;
          end if;
        end if;
      end if;

      pps_d <= PPS_IN;
    end if;
  end process;

  FRAME_START_OUT <= fs_r;
  IRIG_OUT        <= out_r xor INV;

end architecture rtl;
