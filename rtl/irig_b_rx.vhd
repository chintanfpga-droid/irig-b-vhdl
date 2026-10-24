----------------------------------------------------------------------------------
-- irig_b_rx: IRIG-B DC level shift (B00x) time-code receiver
--
-- Input path: two-flop synchronizer, then a glitch filter that passes a level
-- only after it has held for FILT_CLKS clocks. The filter delays both edges
-- by the same amount, so pulse widths are kept.
--
-- Symbols: the high time picks the symbol. 1.0-3.5 ms is a 0, 3.5-6.5 ms a 1
-- and 6.5-9.5 ms a marker; anything else is an error. Rising edges must be
-- 9-11 ms apart, and a gap of 12 ms with no rising edge means the signal is
-- lost.
--
-- Framing: two markers in a row (P0 then Pr) align the receiver; Pr is bit 0.
-- From then on every symbol must be a marker exactly where the layout puts
-- one (irig_b_pkg). Any error (bad width, bad spacing, a marker in the wrong
-- place, signal lost) drops alignment and lock, pulses ERR_OUT, and the
-- receiver waits for the next P0, Pr pair.
--
-- Outputs:
--   TIME_VALID_OUT pulses when a whole frame (Pr .. P0) arrived without error
--     and every BCD field is in range. The *_OUT fields then hold the time of
--     that frame's on-time point (the leading edge of its Pr, about one second
--     earlier) and keep it until the next good frame. LOCKED_OUT goes high.
--   PPS_OUT pulses on the leading edge of the next frame's Pr, while locked.
--     Its time is the last decoded time + 1 s. It lags the edge at IRIG_IN by
--     a fixed FILT_CLKS + 3 clocks (19 at the default 16).
--   LOCKED_OUT drops on any error, and also when a frame's BCD is out of range.
--
-- CLK_HZ must be a multiple of 1000. INVERT expects an inverted line.
--
-- VHDL-93.
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.irig_b_pkg.all;

entity irig_b_rx is
  generic (
    CLK_HZ    : positive := 100000000;
    FILT_CLKS : positive := 16;
    INVERT    : boolean  := false
  );
  port (
    CLK            : in  std_logic;
    RST            : in  std_logic;
    IRIG_IN        : in  std_logic;   -- asynchronous
    PPS_OUT        : out std_logic;
    TIME_VALID_OUT : out std_logic;
    LOCKED_OUT     : out std_logic;
    ERR_OUT        : out std_logic;
    SEC_OUT        : out unsigned(5 downto 0);
    MIN_OUT        : out unsigned(5 downto 0);
    HOUR_OUT       : out unsigned(4 downto 0);
    DAY_OUT        : out unsigned(8 downto 0);
    YEAR_OUT       : out unsigned(6 downto 0);
    CF_OUT         : out std_logic_vector(17 downto 0);
    SBS_OUT        : out unsigned(16 downto 0)
  );
end entity irig_b_rx;

architecture rtl of irig_b_rx is

  constant MS     : positive := CLK_HZ / 1000;
  constant W_MIN  : natural  := MS;              -- shorter is noise
  constant W_01   : natural  := (7 * MS) / 2;    -- 3.5 ms: 0 / 1
  constant W_1M   : natural  := (13 * MS) / 2;   -- 6.5 ms: 1 / marker
  constant W_MAX  : natural  := (19 * MS) / 2;   -- 9.5 ms
  constant P_MIN  : natural  := 9 * MS;          -- rising-edge spacing
  constant P_MAX  : natural  := 11 * MS;
  constant T_LOST : natural  := 12 * MS;
  constant MARKS  : irig_frame_t := irig_marker_mask;

  constant SYM_ZERO : natural := 0;
  constant SYM_ONE  : natural := 1;
  constant SYM_MARK : natural := 2;
  constant SYM_BAD  : natural := 3;

  function to_sl(b : boolean) return std_logic is
  begin
    if b then
      return '1';
    end if;
    return '0';
  end function;
  constant INV : std_logic := to_sl(INVERT);

  signal s_meta, s_sync : std_logic := '0';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of s_meta : signal is "TRUE";
  attribute ASYNC_REG of s_sync : signal is "TRUE";

  signal filt_q    : std_logic := '0';
  signal filt_d    : std_logic := '0';
  signal filt_cnt  : integer range 0 to FILT_CLKS-1 := 0;

  signal hi_cnt    : integer range 0 to W_MAX+1 := 0;
  signal per_cnt   : integer range 0 to T_LOST := 0;
  signal have_edge : std_logic := '0';   -- a rising edge seen since reset/loss
  signal aligned   : std_logic := '0';   -- idx is the frame position
  signal prev_mark : std_logic := '0';   -- last symbol was a marker
  signal idx       : integer range 0 to IRIG_NBITS-1 := 0;  -- last symbol's bit
  signal bits      : irig_frame_t := (others => '0');

  signal dec_req   : std_logic := '0';
  signal dec_go    : std_logic := '0';
  signal dec_ok    : boolean := false;
  signal dec_t     : irig_time_t := IRIG_TIME_ZERO;

  signal locked_r  : std_logic := '0';
  signal pps_r     : std_logic := '0';
  signal tv_r      : std_logic := '0';
  signal err_r     : std_logic := '0';
  signal t_out     : irig_time_t := IRIG_TIME_ZERO;

begin

  assert CLK_HZ mod 1000 = 0
    report "irig_b_rx: CLK_HZ must be a multiple of 1000" severity failure;

  process (CLK)
    variable rise, fall : boolean;
    variable sym        : natural range 0 to 3;
    variable nidx       : integer range 0 to IRIG_NBITS-1;
    variable err        : boolean;
    variable keep_mark  : boolean;   -- error on a good symbol: keep prev_mark
  begin
    if rising_edge(CLK) then
      -- synchronizer and glitch filter
      s_meta <= IRIG_IN xor INV;
      s_sync <= s_meta;
      if s_sync /= filt_q then
        if filt_cnt = FILT_CLKS-1 then
          filt_q   <= s_sync;
          filt_cnt <= 0;
        else
          filt_cnt <= filt_cnt + 1;
        end if;
      else
        filt_cnt <= 0;
      end if;
      filt_d <= filt_q;

      pps_r   <= '0';
      tv_r    <= '0';
      err_r   <= '0';
      dec_req <= '0';
      dec_go  <= '0';

      if RST = '1' then
        hi_cnt    <= 0;
        per_cnt   <= 0;
        have_edge <= '0';
        aligned   <= '0';
        prev_mark <= '0';
        idx       <= 0;
        locked_r  <= '0';
      else
        rise      := filt_q = '1' and filt_d = '0';
        fall      := filt_q = '0' and filt_d = '1';
        err       := false;
        keep_mark := false;

        -- high time of the current pulse, and time since the last rising edge
        if rise then
          hi_cnt <= 1;
        elsif filt_q = '1' and hi_cnt < W_MAX+1 then
          hi_cnt <= hi_cnt + 1;
        end if;
        if rise then
          per_cnt <= 1;
        elsif per_cnt < T_LOST then
          per_cnt <= per_cnt + 1;
        end if;

        -- signal lost: no rising edge for T_LOST (stuck high or stuck low)
        if per_cnt = T_LOST and have_edge = '1' then
          err       := true;
          have_edge <= '0';
        end if;

        if rise then
          if have_edge = '1' and (per_cnt < P_MIN or per_cnt > P_MAX) then
            err := true;
          end if;
          have_edge <= '1';
          -- after P0 the next rising edge is the on-time point
          if not err and locked_r = '1' and aligned = '1' and idx = IRIG_NBITS-1 then
            pps_r <= '1';
          end if;
        end if;

        if fall then
          if hi_cnt < W_MIN or hi_cnt > W_MAX then
            sym := SYM_BAD;
          elsif hi_cnt < W_01 then
            sym := SYM_ZERO;
          elsif hi_cnt < W_1M then
            sym := SYM_ONE;
          else
            sym := SYM_MARK;
          end if;

          if sym = SYM_BAD then
            err := true;
          else
            keep_mark := true;
            if sym = SYM_MARK then
              prev_mark <= '1';
            else
              prev_mark <= '0';
            end if;

            if aligned = '1' then
              if idx = IRIG_NBITS-1 then
                nidx := 0;
              else
                nidx := idx + 1;
              end if;
              if (MARKS(nidx) = '1') /= (sym = SYM_MARK) then
                err := true;
              else
                idx <= nidx;
                if sym = SYM_ONE then
                  bits(nidx) <= '1';
                else
                  bits(nidx) <= '0';
                end if;
                if nidx = IRIG_NBITS-1 then
                  dec_req <= '1';
                end if;
              end if;
            elsif sym = SYM_MARK and prev_mark = '1' then
              aligned <= '1';           -- P0, Pr: this marker is bit 0
              idx     <= 0;
            end if;
          end if;
        end if;

        -- decode a complete frame (bits is final one clock after the P0 fall)
        if dec_req = '1' then
          dec_t  <= irig_decode(bits);
          dec_ok <= irig_valid(bits);
          dec_go <= '1';
        end if;
        if dec_go = '1' then
          if dec_ok then
            t_out    <= dec_t;
            tv_r     <= '1';
            locked_r <= '1';
          else
            err_r    <= '1';
            locked_r <= '0';
          end if;
        end if;

        if err then
          err_r    <= '1';
          aligned  <= '0';
          locked_r <= '0';
          if not keep_mark then
            prev_mark <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;

  PPS_OUT        <= pps_r;
  TIME_VALID_OUT <= tv_r;
  LOCKED_OUT     <= locked_r;
  ERR_OUT        <= err_r;
  SEC_OUT        <= t_out.sec;
  MIN_OUT        <= t_out.min;
  HOUR_OUT       <= t_out.hour;
  DAY_OUT        <= t_out.day;
  YEAR_OUT       <= t_out.year;
  CF_OUT         <= t_out.cf;
  SBS_OUT        <= t_out.sbs;

end architecture rtl;
