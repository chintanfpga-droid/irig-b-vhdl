----------------------------------------------------------------------------------
-- irig_b_pkg: IRIG-B frame layout (IRIG Standard 200, format B, DC level shift)
--
-- One frame per second, 100 bits of 10 ms. Each bit is a high pulse at the
-- start of its 10 ms slot: 2 ms = binary 0, 5 ms = binary 1, 8 ms = marker.
-- Markers sit at bit 0 (Pr, the reference marker) and bits 9, 19, .., 99
-- (P1..P9, P0). Two markers in a row (P0, Pr) mark the frame start, and the
-- leading edge of Pr is the on-time point: the instant the frame's time
-- refers to.
--
-- Bit map (BCD fields LSB first; weights in brackets):
--    1-4   seconds units [1 2 4 8]     6-8  seconds tens [10 20 40]
--   10-13  minutes units               15-17 minutes tens [10 20 40]
--   20-23  hours units                 25-26 hours tens [10 20]
--   30-33  day-of-year units           35-38 day tens [10 20 40 80]
--   40-41  day hundreds [100 200]      45-48 tenths of seconds (sent as 0)
--   50-53  year units                  55-58 year tens [10 20 40 80]
--   60-68  control functions CF 0-8    70-78 CF 9-17
--   80-88  straight binary seconds of day 2^0..2^8
--   90-97  SBS 2^9..2^16
--   5, 14, 18, 24, 27, 28, 34, 42-44, 54, 98: index bits, always 0
-- This is coded expression B004-B007 (BCD time of year + year + CF + SBS); a
-- B000-B003 source simply sends zeros in the fields it does not carry.
--
-- In irig_frame_t, bit i holds the data value of frame bit i. Marker
-- positions read 0; irig_marker_mask says where they are.
--
-- VHDL-93.
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package irig_b_pkg is

  constant IRIG_NBITS : natural := 100;
  subtype irig_frame_t is std_logic_vector(IRIG_NBITS-1 downto 0);

  -- Time carried by one frame, in binary. sec 60 is a leap second.
  type irig_time_t is record
    sec  : unsigned(5 downto 0);           -- 0..60
    min  : unsigned(5 downto 0);           -- 0..59
    hour : unsigned(4 downto 0);           -- 0..23
    day  : unsigned(8 downto 0);           -- 1..366
    year : unsigned(6 downto 0);           -- 0..99
    cf   : std_logic_vector(17 downto 0);  -- control functions, raw
    sbs  : unsigned(16 downto 0);          -- seconds of day, 0..86400
  end record;

  constant IRIG_TIME_ZERO : irig_time_t := (
    sec  => (others => '0'),
    min  => (others => '0'),
    hour => (others => '0'),
    day  => (others => '0'),
    year => (others => '0'),
    cf   => (others => '0'),
    sbs  => (others => '0'));

  -- '1' at the 11 marker positions (0, 9, 19, .., 99).
  function irig_marker_mask return irig_frame_t;

  -- Data bits of a frame. Out-of-range fields are truncated to their width.
  function irig_encode(t : irig_time_t) return irig_frame_t;

  -- Binary fields from a frame's data bits. Only meaningful when irig_valid.
  function irig_decode(f : irig_frame_t) return irig_time_t;

  -- Every BCD digit is a digit and every field is in range.
  function irig_valid(f : irig_frame_t) return boolean;

end package irig_b_pkg;

package body irig_b_pkg is

  function irig_marker_mask return irig_frame_t is
    variable m : irig_frame_t := (others => '0');
  begin
    for i in 0 to IRIG_NBITS-1 loop
      if i = 0 or (i mod 10) = 9 then
        m(i) := '1';
      end if;
    end loop;
    return m;
  end function;

  -- Write the n low bits of v at frame bits lo .. lo+n-1, LSB first.
  procedure put(f : inout irig_frame_t; lo : in natural; n : in natural; v : in natural) is
    variable u : unsigned(8 downto 0);
  begin
    u := to_unsigned(v mod 512, 9);
    for k in 0 to n-1 loop
      f(lo + k) := u(k);
    end loop;
  end procedure;

  -- Read frame bits lo .. lo+n-1 (LSB first) as a number.
  function get(f : irig_frame_t; lo : natural; n : natural) return natural is
    variable u : unsigned(8 downto 0) := (others => '0');
  begin
    for k in 0 to n-1 loop
      u(k) := f(lo + k);
    end loop;
    return to_integer(u);
  end function;

  function irig_encode(t : irig_time_t) return irig_frame_t is
    variable f : irig_frame_t := (others => '0');
    variable s, m, h, d, y : natural;
  begin
    s := to_integer(t.sec);
    m := to_integer(t.min);
    h := to_integer(t.hour);
    d := to_integer(t.day);
    y := to_integer(t.year);
    put(f,  1, 4, s mod 10);  put(f,  6, 3, s / 10);
    put(f, 10, 4, m mod 10);  put(f, 15, 3, m / 10);
    put(f, 20, 4, h mod 10);  put(f, 25, 2, h / 10);
    put(f, 30, 4, d mod 10);  put(f, 35, 4, (d / 10) mod 10);  put(f, 40, 2, d / 100);
    put(f, 50, 4, y mod 10);  put(f, 55, 4, y / 10);
    f(68 downto 60) := t.cf(8 downto 0);
    f(78 downto 70) := t.cf(17 downto 9);
    f(88 downto 80) := std_logic_vector(t.sbs(8 downto 0));
    f(97 downto 90) := std_logic_vector(t.sbs(16 downto 9));
    return f;
  end function;

  function irig_decode(f : irig_frame_t) return irig_time_t is
    variable t : irig_time_t;
    variable s, m, h, d, y : natural;
  begin
    s := get(f,  1, 4) + 10 * get(f,  6, 3);
    m := get(f, 10, 4) + 10 * get(f, 15, 3);
    h := get(f, 20, 4) + 10 * get(f, 25, 2);
    d := get(f, 30, 4) + 10 * get(f, 35, 4) + 100 * get(f, 40, 2);
    y := get(f, 50, 4) + 10 * get(f, 55, 4);
    t.sec  := to_unsigned(s mod 64, 6);
    t.min  := to_unsigned(m mod 64, 6);
    t.hour := to_unsigned(h mod 32, 5);
    t.day  := to_unsigned(d mod 512, 9);
    t.year := to_unsigned(y mod 128, 7);
    t.cf   := f(78 downto 70) & f(68 downto 60);
    t.sbs  := unsigned(f(97 downto 90) & f(88 downto 80));
    return t;
  end function;

  function irig_valid(f : irig_frame_t) return boolean is
    variable su, st, mu, mt, hu, ht, du, dt, dh, yu, yt : natural;
  begin
    su := get(f,  1, 4);  st := get(f,  6, 3);
    mu := get(f, 10, 4);  mt := get(f, 15, 3);
    hu := get(f, 20, 4);  ht := get(f, 25, 2);
    du := get(f, 30, 4);  dt := get(f, 35, 4);  dh := get(f, 40, 2);
    yu := get(f, 50, 4);  yt := get(f, 55, 4);
    if su > 9 or 10 * st + su > 60 then
      return false;
    end if;
    if mu > 9 or mt > 5 then
      return false;
    end if;
    if hu > 9 or 10 * ht + hu > 23 then
      return false;
    end if;
    if du > 9 or dt > 9 or 100 * dh + 10 * dt + du = 0 or 100 * dh + 10 * dt + du > 366 then
      return false;
    end if;
    if yu > 9 or yt > 9 then
      return false;
    end if;
    if to_integer(unsigned(f(97 downto 90) & f(88 downto 80))) > 86400 then
      return false;
    end if;
    return true;
  end function;

end package body irig_b_pkg;
