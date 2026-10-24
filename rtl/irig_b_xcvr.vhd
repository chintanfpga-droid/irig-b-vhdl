----------------------------------------------------------------------------------
-- irig_b_xcvr: IRIG-B DC level shift transceiver (irig_b_tx + irig_b_rx)
--
-- The two halves are independent: the generator sends the time on TX_*_IN
-- each second, and the receiver decodes whatever arrives on RX_IRIG_IN. See
-- irig_b_tx and irig_b_rx for timing and behaviour, irig_b_pkg for the frame.
--
-- VHDL-93.
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity irig_b_xcvr is
  generic (
    CLK_HZ    : positive := 100000000;
    EXT_PPS   : boolean  := true;
    FILT_CLKS : positive := 16;
    TX_INVERT : boolean  := false;
    RX_INVERT : boolean  := false
  );
  port (
    CLK                : in  std_logic;
    RST                : in  std_logic;
    -- generator
    TX_EN              : in  std_logic;
    TX_PPS_IN          : in  std_logic;
    TX_SEC_IN          : in  unsigned(5 downto 0);
    TX_MIN_IN          : in  unsigned(5 downto 0);
    TX_HOUR_IN         : in  unsigned(4 downto 0);
    TX_DAY_IN          : in  unsigned(8 downto 0);
    TX_YEAR_IN         : in  unsigned(6 downto 0);
    TX_CF_IN           : in  std_logic_vector(17 downto 0);
    TX_SBS_IN          : in  unsigned(16 downto 0);
    TX_FRAME_START_OUT : out std_logic;
    TX_IRIG_OUT        : out std_logic;
    -- receiver
    RX_IRIG_IN         : in  std_logic;
    RX_PPS_OUT         : out std_logic;
    RX_TIME_VALID_OUT  : out std_logic;
    RX_LOCKED_OUT      : out std_logic;
    RX_ERR_OUT         : out std_logic;
    RX_SEC_OUT         : out unsigned(5 downto 0);
    RX_MIN_OUT         : out unsigned(5 downto 0);
    RX_HOUR_OUT        : out unsigned(4 downto 0);
    RX_DAY_OUT         : out unsigned(8 downto 0);
    RX_YEAR_OUT        : out unsigned(6 downto 0);
    RX_CF_OUT          : out std_logic_vector(17 downto 0);
    RX_SBS_OUT         : out unsigned(16 downto 0)
  );
end entity irig_b_xcvr;

architecture rtl of irig_b_xcvr is
begin

  u_tx : entity work.irig_b_tx
    generic map (
      CLK_HZ  => CLK_HZ,
      EXT_PPS => EXT_PPS,
      INVERT  => TX_INVERT)
    port map (
      CLK             => CLK,
      RST             => RST,
      EN              => TX_EN,
      PPS_IN          => TX_PPS_IN,
      SEC_IN          => TX_SEC_IN,
      MIN_IN          => TX_MIN_IN,
      HOUR_IN         => TX_HOUR_IN,
      DAY_IN          => TX_DAY_IN,
      YEAR_IN         => TX_YEAR_IN,
      CF_IN           => TX_CF_IN,
      SBS_IN          => TX_SBS_IN,
      FRAME_START_OUT => TX_FRAME_START_OUT,
      IRIG_OUT        => TX_IRIG_OUT);

  u_rx : entity work.irig_b_rx
    generic map (
      CLK_HZ    => CLK_HZ,
      FILT_CLKS => FILT_CLKS,
      INVERT    => RX_INVERT)
    port map (
      CLK            => CLK,
      RST            => RST,
      IRIG_IN        => RX_IRIG_IN,
      PPS_OUT        => RX_PPS_OUT,
      TIME_VALID_OUT => RX_TIME_VALID_OUT,
      LOCKED_OUT     => RX_LOCKED_OUT,
      ERR_OUT        => RX_ERR_OUT,
      SEC_OUT        => RX_SEC_OUT,
      MIN_OUT        => RX_MIN_OUT,
      HOUR_OUT       => RX_HOUR_OUT,
      DAY_OUT        => RX_DAY_OUT,
      YEAR_OUT       => RX_YEAR_OUT,
      CF_OUT         => RX_CF_OUT,
      SBS_OUT        => RX_SBS_OUT);

end architecture rtl;
