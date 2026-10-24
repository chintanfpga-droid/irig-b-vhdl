#!/bin/bash
# Self-checking IRIG-B bench (Vivado xsim): RTL as VHDL-93, bench as VHDL-2008.
# Runs the bench twice, with INVERT false and true. Needs xvhdl/xelab/xsim on
# PATH, or VIVADO_BIN set to Vivado's bin directory.
set -e
B=${VIVADO_BIN:+$VIVADO_BIN/}
cd "$(dirname "$0")"
R=../rtl
rm -rf xsim.dir work_*.log
${B}xvhdl $R/irig_b_pkg.vhd $R/irig_b_tx.vhd $R/irig_b_rx.vhd $R/irig_b_xcvr.vhd > work_rtl.log
${B}xvhdl --2008 tb_irig_b.vhd > work_tb.log
rc=0
for inv in false true; do
  ${B}xelab -debug off tb_irig_b -generic_top "INVERT=$inv" -s tb_$inv > work_elab_$inv.log
  ${B}xsim tb_$inv -R > work_sim_$inv.log 2>&1 || true
  grep -E "Note: (RX frame|TX pulses|PASS)|FAIL|Error:" work_sim_$inv.log | sed 's/^Note: //'
  grep -q "PASS (INVERT" work_sim_$inv.log || rc=1
done
exit $rc
