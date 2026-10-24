----------------------------------------------------------------------------------
-- tb_irig_b: self-checking bench for irig_b_xcvr (VHDL-2008)
--
-- TX -> line -> RX loopback at CLK_HZ = 1 MHz (one frame = 1e6 clocks), over
-- 8 frames whose time rolls over the year: 2026 day 365 23:59:58 onwards.
--
-- 1. Every TX pulse is checked against an independent copy of the IRIG 200
--    bit table (TAB below, written out by hand, not taken from irig_b_pkg):
--    exact width (2/5/8 ms), exact 10 ms spacing, fixed lag from PPS.
-- 2. RX decodes: every TIME_VALID must carry the time of the frame on the
--    line, and exactly frames 1, 2, 3, 5, 6, 7 must decode (frame 0 is used
--    to align; frame 4 is broken on purpose).
-- 3. RX PPS: exactly on frames 2, 3, 4, 6, 7, 8, each a fixed number of
--    clocks after the line's on-time edge. (A ninth PPS keeps the line live:
--    without it the receiver correctly reports the signal lost after frame 7.)
-- 4. Noise: frames 2 and 3 carry 27 glitches each (high spikes and low
--    dropouts, FILT_CLKS-2 clocks wide), which must not cost a frame.
-- 5. Dropout: the line is held idle 403-445 ms into frame 4. RX must flag an
--    error in frame 4 only, lose lock, and relock on frame 5.
-- 6. PPS jitter of a few clocks between frames (early and late).
-- Generic INVERT runs the whole bench with an inverted line.
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_irig_b is
  generic (INVERT : boolean := false);
end entity;

architecture sim of tb_irig_b is

  constant CLK_HZ : positive := 1000000;
  constant MS     : positive := CLK_HZ / 1000;
  constant FILT   : positive := 16;
  constant NFR    : positive := 8;        -- frames checked
  constant NPPS   : positive := NFR + 1;  -- frames sent

  type int_arr is array (natural range <>) of integer;
  constant JIT : int_arr(0 to NPPS-1) := (0, 4, -3, 2, 0, -5, 1, 0, 3);
  function pps_at(n : natural) return natural is
  begin
    return 100 + n * CLK_HZ + JIT(n);
  end function;

  -- time of frame n
  type tod_t is record
    sec, min, hour, day, year, cf, sbs : natural;
  end record;
  function tb_time(n : natural) return tod_t is
    variable sod : natural := 86398 + n;
    variable d   : natural := 365;
    variable y   : natural := 26;
    variable t   : tod_t;
  begin
    if sod >= 86400 then
      sod := sod - 86400;
      d   := d + 1;
      if d > 365 then
        d := 1;
        y := y + 1;
      end if;
    end if;
    t.sbs  := sod;
    t.hour := sod / 3600;
    t.min  := (sod / 60) mod 60;
    t.sec  := sod mod 60;
    t.day  := d;
    t.year := y;
    t.cf   := (n * 74565 + 12345) mod 262144;
    return t;
  end function;

  -- independent IRIG 200 format B bit table
  type kind_t is (KM, KZ, KS, KN, KH, KD, KT, KY, KC, KB);
  type ent_t is record
    k : kind_t;
    w : natural;
  end record;
  type tab_t is array (0 to 99) of ent_t;
  constant TAB : tab_t := (
     0 => (KM, 0),   1 => (KS, 1),   2 => (KS, 2),   3 => (KS, 4),   4 => (KS, 8),
     5 => (KZ, 0),   6 => (KS, 10),  7 => (KS, 20),  8 => (KS, 40),  9 => (KM, 0),
    10 => (KN, 1),  11 => (KN, 2),  12 => (KN, 4),  13 => (KN, 8),  14 => (KZ, 0),
    15 => (KN, 10), 16 => (KN, 20), 17 => (KN, 40), 18 => (KZ, 0),  19 => (KM, 0),
    20 => (KH, 1),  21 => (KH, 2),  22 => (KH, 4),  23 => (KH, 8),  24 => (KZ, 0),
    25 => (KH, 10), 26 => (KH, 20), 27 => (KZ, 0),  28 => (KZ, 0),  29 => (KM, 0),
    30 => (KD, 1),  31 => (KD, 2),  32 => (KD, 4),  33 => (KD, 8),  34 => (KZ, 0),
    35 => (KD, 10), 36 => (KD, 20), 37 => (KD, 40), 38 => (KD, 80), 39 => (KM, 0),
    40 => (KD, 100), 41 => (KD, 200), 42 => (KZ, 0), 43 => (KZ, 0), 44 => (KZ, 0),
    45 => (KT, 1),  46 => (KT, 2),  47 => (KT, 4),  48 => (KT, 8),  49 => (KM, 0),
    50 => (KY, 1),  51 => (KY, 2),  52 => (KY, 4),  53 => (KY, 8),  54 => (KZ, 0),
    55 => (KY, 10), 56 => (KY, 20), 57 => (KY, 40), 58 => (KY, 80), 59 => (KM, 0),
    60 => (KC, 0),  61 => (KC, 1),  62 => (KC, 2),  63 => (KC, 3),  64 => (KC, 4),
    65 => (KC, 5),  66 => (KC, 6),  67 => (KC, 7),  68 => (KC, 8),  69 => (KM, 0),
    70 => (KC, 9),  71 => (KC, 10), 72 => (KC, 11), 73 => (KC, 12), 74 => (KC, 13),
    75 => (KC, 14), 76 => (KC, 15), 77 => (KC, 16), 78 => (KC, 17), 79 => (KM, 0),
    80 => (KB, 0),  81 => (KB, 1),  82 => (KB, 2),  83 => (KB, 3),  84 => (KB, 4),
    85 => (KB, 5),  86 => (KB, 6),  87 => (KB, 7),  88 => (KB, 8),  89 => (KM, 0),
    90 => (KB, 9),  91 => (KB, 10), 92 => (KB, 11), 93 => (KB, 12), 94 => (KB, 13),
    95 => (KB, 14), 96 => (KB, 15), 97 => (KB, 16), 98 => (KZ, 0),  99 => (KM, 0));

  function bcd_bit(v, w : natural) return natural is
    variable dec : natural;
  begin
    if w < 10 then
      dec := 1;
    elsif w < 100 then
      dec := 10;
    else
      dec := 100;
    end if;
    return (((v / dec) mod 10) / (w / dec)) mod 2;
  end function;

  -- expected high time of frame bit i, in ms
  function golden_ms(t : tod_t; i : natural) return natural is
    variable b : natural := 0;
  begin
    case TAB(i).k is
      when KM => return 8;
      when KZ | KT => return 2;
      when KS => b := bcd_bit(t.sec, TAB(i).w);
      when KN => b := bcd_bit(t.min, TAB(i).w);
      when KH => b := bcd_bit(t.hour, TAB(i).w);
      when KD => b := bcd_bit(t.day, TAB(i).w);
      when KY => b := bcd_bit(t.year, TAB(i).w);
      when KC => b := (t.cf / 2**TAB(i).w) mod 2;
      when KB => b := (t.sbs / 2**TAB(i).w) mod 2;
    end case;
    return 2 + 3 * b;
  end function;

  function to_sl(b : boolean) return std_logic is
  begin
    if b then
      return '1';
    end if;
    return '0';
  end function;
  constant INV : std_logic := to_sl(INVERT);

  signal clk    : std_logic := '0';
  signal cyc    : natural := 0;
  signal rst    : std_logic := '1';
  signal pps    : std_logic := '0';

  signal t_sec  : unsigned(5 downto 0);
  signal t_min  : unsigned(5 downto 0);
  signal t_hour : unsigned(4 downto 0);
  signal t_day  : unsigned(8 downto 0);
  signal t_year : unsigned(6 downto 0);
  signal t_cf   : std_logic_vector(17 downto 0);
  signal t_sbs  : unsigned(16 downto 0);

  signal fs, tx_out, line : std_logic;
  signal glitch, drop     : std_logic := '0';

  signal r_pps, r_tv, r_lock, r_err : std_logic;
  signal r_sec  : unsigned(5 downto 0);
  signal r_min  : unsigned(5 downto 0);
  signal r_hour : unsigned(4 downto 0);
  signal r_day  : unsigned(8 downto 0);
  signal r_year : unsigned(6 downto 0);
  signal r_cf   : std_logic_vector(17 downto 0);
  signal r_sbs  : unsigned(16 downto 0);

  procedure drive(n : natural;
                  signal s : out unsigned(5 downto 0); signal m : out unsigned(5 downto 0);
                  signal h : out unsigned(4 downto 0); signal d : out unsigned(8 downto 0);
                  signal y : out unsigned(6 downto 0); signal c : out std_logic_vector(17 downto 0);
                  signal b : out unsigned(16 downto 0)) is
    variable t : tod_t;
  begin
    t := tb_time(n);
    s <= to_unsigned(t.sec, 6);
    m <= to_unsigned(t.min, 6);
    h <= to_unsigned(t.hour, 5);
    d <= to_unsigned(t.day, 9);
    y <= to_unsigned(t.year, 7);
    c <= std_logic_vector(to_unsigned(t.cf, 18));
    b <= to_unsigned(t.sbs, 17);
  end procedure;

begin

  clk <= not clk after 500 ns;

  -- clock counter, reset, PPS
  process (clk)
  begin
    if rising_edge(clk) then
      cyc <= cyc + 1;
      if cyc = 10 then
        rst <= '0';
      end if;
      pps <= '0';
      for n in 0 to NPPS-1 loop
        if cyc = pps_at(n) then
          pps <= '1';
        end if;
      end loop;
    end if;
  end process;

  -- present frame n+1's time once frame n has latched its own
  process (clk)
    variable nf : integer := 0;
  begin
    if cyc = 0 and nf = 0 then
      drive(0, t_sec, t_min, t_hour, t_day, t_year, t_cf, t_sbs);
    end if;
    if rising_edge(clk) and fs = '1' then
      nf := nf + 1;
      drive(nf, t_sec, t_min, t_hour, t_day, t_year, t_cf, t_sbs);
    end if;
  end process;

  -- glitches in frames 2 and 3: FILT-2 clocks, every 37 ms + 7k us
  process
  begin
    for f in 2 to 3 loop
      for k in 0 to 26 loop
        wait until cyc = pps_at(f) + k * 37 * MS + MS + 7 * k;
        glitch <= '1';
        wait until cyc = pps_at(f) + k * 37 * MS + MS + 7 * k + FILT - 2;
        glitch <= '0';
      end loop;
    end loop;
    wait;
  end process;

  -- line held idle 403-445 ms into frame 4
  process
  begin
    wait until cyc = pps_at(4) + 403 * MS;
    drop <= '1';
    wait until cyc = pps_at(4) + 445 * MS;
    drop <= '0';
    wait;
  end process;

  line <= INV when drop = '1' else tx_out xor glitch;

  dut : entity work.irig_b_xcvr
    generic map (
      CLK_HZ    => CLK_HZ,
      EXT_PPS   => true,
      FILT_CLKS => FILT,
      TX_INVERT => INVERT,
      RX_INVERT => INVERT)
    port map (
      CLK                => clk,
      RST                => rst,
      TX_EN              => '1',
      TX_PPS_IN          => pps,
      TX_SEC_IN          => t_sec,
      TX_MIN_IN          => t_min,
      TX_HOUR_IN         => t_hour,
      TX_DAY_IN          => t_day,
      TX_YEAR_IN         => t_year,
      TX_CF_IN           => t_cf,
      TX_SBS_IN          => t_sbs,
      TX_FRAME_START_OUT => fs,
      TX_IRIG_OUT        => tx_out,
      RX_IRIG_IN         => line,
      RX_PPS_OUT         => r_pps,
      RX_TIME_VALID_OUT  => r_tv,
      RX_LOCKED_OUT      => r_lock,
      RX_ERR_OUT         => r_err,
      RX_SEC_OUT         => r_sec,
      RX_MIN_OUT         => r_min,
      RX_HOUR_OUT        => r_hour,
      RX_DAY_OUT         => r_day,
      RX_YEAR_OUT        => r_year,
      RX_CF_OUT          => r_cf,
      RX_SBS_OUT         => r_sbs);

  -- checker
  process (clk)
    variable frame    : integer := -1;   -- TX frame on the line
    variable bitpos   : integer := -1;
    variable lv, plv  : std_logic := '0';
    variable rise_c   : integer := 0;
    variable pps_c    : integer := 0;
    variable fs_c     : integer := 0;
    variable on_c     : integer := 0;    -- cycle of this frame's first rising edge
    variable tx_lag   : integer := -1;
    variable rx_lat   : integer := -1;
    variable tx_ok    : natural := 0;
    variable fails    : natural := 0;
    type bool_arr is array (0 to NPPS-1) of boolean;
    variable dec_seen, pps_seen, err_seen : bool_arr := (others => false);
    variable exp_ms   : natural;
    variable t        : tod_t;
    variable done     : boolean := false;

    procedure fail(msg : string) is
    begin
      report "FAIL: " & msg severity error;
      fails := fails + 1;
    end procedure;

  begin
    if rising_edge(clk) and not done then
      if pps = '1' then
        pps_c := cyc;
      end if;
      if fs = '1' then
        frame  := frame + 1;
        bitpos := -1;
        fs_c   := cyc;
      end if;

      -- 1. TX waveform against TAB
      lv := tx_out xor INV;
      if lv = '1' and plv = '0' and frame >= 0 then
        bitpos := bitpos + 1;
        if bitpos = 0 then
          on_c := cyc;
          if tx_lag < 0 then
            tx_lag := cyc - pps_c;
          elsif cyc - pps_c /= tx_lag then
            fail("frame " & integer'image(frame) & ": TX lag from PPS " &
                 integer'image(cyc - pps_c) & ", expected " & integer'image(tx_lag));
          end if;
        elsif cyc - rise_c /= 10 * MS then
          fail("frame " & integer'image(frame) & " bit " & integer'image(bitpos) &
               ": spacing " & integer'image(cyc - rise_c));
        end if;
        rise_c := cyc;
      end if;
      if lv = '0' and plv = '1' and frame >= 0 and frame < NFR then
        exp_ms := golden_ms(tb_time(frame), bitpos);
        if cyc - rise_c /= exp_ms * MS then
          fail("frame " & integer'image(frame) & " bit " & integer'image(bitpos) &
               ": width " & integer'image(cyc - rise_c) & ", expected " &
               integer'image(exp_ms * MS));
        else
          tx_ok := tx_ok + 1;
        end if;
      end if;
      plv := lv;

      -- 2. RX decode
      if r_tv = '1' then
        t := tb_time(frame);
        if to_integer(r_sec) /= t.sec or to_integer(r_min) /= t.min or
           to_integer(r_hour) /= t.hour or to_integer(r_day) /= t.day or
           to_integer(r_year) /= t.year or to_integer(unsigned(r_cf)) /= t.cf or
           to_integer(r_sbs) /= t.sbs then
          fail("frame " & integer'image(frame) & ": RX decoded " &
               integer'image(to_integer(r_year)) & "/" & integer'image(to_integer(r_day)) & " " &
               integer'image(to_integer(r_hour)) & ":" & integer'image(to_integer(r_min)) & ":" &
               integer'image(to_integer(r_sec)) & " sbs " & integer'image(to_integer(r_sbs)));
        end if;
        report "RX frame " & integer'image(frame) & ": " &
               integer'image(to_integer(r_year)) & "/" & integer'image(to_integer(r_day)) & " " &
               integer'image(to_integer(r_hour)) & ":" & integer'image(to_integer(r_min)) & ":" &
               integer'image(to_integer(r_sec)) & " sbs " & integer'image(to_integer(r_sbs)) &
               " cf 0x" & to_hstring(r_cf);
        dec_seen(frame) := true;
      end if;

      -- 3. RX PPS, measured from the frame's on-time edge on the line
      if r_pps = '1' then
        pps_seen(frame) := true;
        if rx_lat < 0 then
          rx_lat := cyc - on_c;
        elsif cyc - on_c /= rx_lat then
          fail("frame " & integer'image(frame) & ": RX PPS latency " &
               integer'image(cyc - on_c) & ", expected " & integer'image(rx_lat));
        end if;
      end if;

      if r_err = '1' and frame >= 0 then
        err_seen(frame) := true;
      end if;

      -- final checks
      if cyc = pps_at(NPPS-1) + 20 * MS then
        done := true;
        if tx_ok /= NFR * 100 then
          fail("TX pulses checked " & integer'image(tx_ok) & ", expected " & integer'image(NFR * 100));
        end if;
        for f in 0 to NPPS-1 loop
          if dec_seen(f) /= (f = 1 or f = 2 or f = 3 or f = 5 or f = 6 or f = 7) then
            fail("frame " & integer'image(f) & ": decoded = " & boolean'image(dec_seen(f)));
          end if;
          if pps_seen(f) /= (f = 2 or f = 3 or f = 4 or f = 6 or f = 7 or f = 8) then
            fail("frame " & integer'image(f) & ": RX PPS = " & boolean'image(pps_seen(f)));
          end if;
          if err_seen(f) /= (f = 4) then
            fail("frame " & integer'image(f) & ": RX error = " & boolean'image(err_seen(f)));
          end if;
        end loop;
        if r_lock /= '1' then
          fail("RX not locked at the end");
        end if;
        report "TX pulses checked: " & integer'image(tx_ok) &
               "; TX lag from PPS: " & integer'image(tx_lag) &
               " clocks; RX PPS latency from line edge: " & integer'image(rx_lat) & " clocks";
        if fails = 0 then
          report "PASS (INVERT=" & boolean'image(INVERT) & ")";
        else
          report "FAILED: " & integer'image(fails) & " check(s)" severity error;
        end if;
        finish;
      end if;
    end if;
  end process;

end architecture sim;
