# IRIG-B transceiver in VHDL

An IRIG-B time-code generator and receiver for FPGAs: IRIG Standard 200,
format B, DC level shift (B00x). Synthesizable VHDL-93, with no vendor
primitives, and a self-checking testbench.

## Files

| File | What it is |
|---|---|
| `rtl/irig_b_pkg.vhd` | Frame layout, encode/decode, BCD range checks |
| `rtl/irig_b_tx.vhd` | Generator: one frame per second, started by an external PPS or an internal 1 s counter |
| `rtl/irig_b_rx.vhd` | Receiver: synchronizer, glitch filter, symbol decode, frame lock, decoded time, PPS out |
| `rtl/irig_b_xcvr.vhd` | Generator and receiver in one wrapper |
| `sim/tb_irig_b.vhd` | Self-checking bench (VHDL-2008) |
| `sim/run.sh` | Runs the bench in Vivado xsim |

Compile order: `irig_b_pkg`, `irig_b_tx`, `irig_b_rx`, `irig_b_xcvr`.

## Frame

100 bits of 10 ms each, one frame per second. Each bit is a high pulse at the
start of its slot: 2 ms for a 0, 5 ms for a 1, 8 ms for a marker. The leading
edge of the reference marker (bit 0) is the on-time point.

The frame carries BCD seconds, minutes, hours, day of year (1-366) and year
(0-99), 18 control-function bits and straight binary seconds of day. That is
coded expression B004-B007. A source that sends fewer fields sends zeros in
the others.

## Generator (`irig_b_tx`)

- **Frame start:** the rising edge of `PPS_IN` when `EXT_PPS = true`, or every
  `CLK_HZ` clocks from enable otherwise.
- **Time:** the `*_IN` fields are sampled on the start clock and must already
  hold the time of that on-time point. `FRAME_START_OUT` pulses one clock
  later; that is the moment to present the next second's time.
- **Timing:** `IRIG_OUT` rises 2 clocks after `PPS_IN` is first sampled high.
  Every bit lasts exactly `CLK_HZ/100` clocks.
- **Early and late PPS:** a PPS that arrives early restarts the frame at once.
  Without a PPS, the line goes idle after bit 99.
- **Clock domain:** `PPS_IN` must be synchronous to `CLK`.

## Receiver (`irig_b_rx`)

- **Input:** `IRIG_IN` may be asynchronous. It passes through a two-flop
  synchronizer, then a glitch filter: a level passes only after it has held
  for `FILT_CLKS` clocks.
- **Symbols:** the high time picks the symbol. 1.0-3.5 ms is a 0, 3.5-6.5 ms
  a 1, and 6.5-9.5 ms a marker; anything else is an error.
- **Line checks:** rising edges must be 9-11 ms apart. A gap of 12 ms with no
  rising edge means the signal is lost.
- **Alignment:** two markers in a row (P0, then Pr) align the receiver. After
  that, markers must appear exactly where the format puts them.
- **`TIME_VALID_OUT`:** pulses after a complete, error-free frame whose BCD
  fields are all in range. The `*_OUT` fields then hold the time of that
  frame's on-time point. `LOCKED_OUT` goes high.
- **`PPS_OUT`:** pulses on the next frame's on-time edge while locked. Its time
  is the last decoded time plus one second. It lags the edge at `IRIG_IN` by a
  fixed `FILT_CLKS + 3` clocks.
- **`ERR_OUT`:** pulses on any error: bad width, bad spacing, a marker out of
  place, a lost signal or bad BCD. The receiver then drops lock and realigns
  on the next P0, Pr pair.

## Generics

| Generic | Default | Meaning |
|---|---|---|
| `CLK_HZ` | 100000000 | Clock frequency; must be a multiple of 1000 |
| `EXT_PPS` | true | Generator frames start on `PPS_IN` (otherwise an internal 1 s counter) |
| `FILT_CLKS` | 16 | Receiver glitch filter length, in clocks |
| `INVERT` / `TX_INVERT` / `RX_INVERT` | false | Inverted line (idle high) |

## Testbench

`sim/run.sh` (Vivado xsim; put the tools on `PATH` or set `VIVADO_BIN`) runs
the generator into the receiver at 1 MHz for 9 frames. The time starts at
2026 day 365 23:59:58, so the frames roll over the minute, hour, day and year.
The bench runs twice, with `INVERT` false and true. It checks:

- **Every generator pulse** against a separate, hand-written copy of the
  IRIG 200 bit table (not the package): exact width, exact 10 ms spacing and
  a fixed lag from PPS (800 pulses per run).
- **Every decoded frame** against the time that was sent.
- **Which frames decode and which get a PPS**, exactly.
- **Glitches:** spikes and dropouts shorter than the filter in two frames must
  not cost a frame.
- **Dropout:** a 42 ms dropout must raise an error in that frame only, then
  relock on the next frame.
- **PPS jitter** of a few clocks between frames, early and late.

## Not covered

AM-modulated IRIG-B (B12x, 1 kHz carrier) needs an ADC and a DAC. Leap-second
and time-zone handling are left to the user (the control-function bits pass
through raw).
