################################################################################################
# 		         Variables
################################################################################################

   
   ################################################################################################
   # 		         Timing Exceptions
   ################################################################################################
   create_clock -name "DFICLK" -period 224.75 -waveform "0 [expr {224.75 * 0.5}]" [get_ports "DFICLK_ungated" -filter "@port_direction == in || @port_direction == inout"] -add
#set_clock_uncertainty 25 [get_clocks {DFICLK}]
set_clock_jitter -clock [get_clocks {DFICLK}] -duty_cycle 47
set_clock_transition -rise -max 29.322 [get_clocks {DFICLK}]
set_clock_transition -rise -min 29.322 [get_clocks {DFICLK}]
set_clock_transition -fall -max 29.322 [get_clocks {DFICLK}]
set_clock_transition -fall -min 29.322 [get_clocks {DFICLK}]

create_clock -name "UCLK" -period 274.6 -waveform "0 [expr {274.6 * 0.5}]" [get_ports "UCLK" -filter "@port_direction == in || @port_direction == inout"] -add
#set_clock_uncertainty 36 [get_clocks {UCLK}]
set_clock_jitter -clock [get_clocks {UCLK}] -duty_cycle 47
set_clock_transition -rise -max 29.322 [get_clocks {UCLK}]
set_clock_transition -rise -min 29.322 [get_clocks {UCLK}]
set_clock_transition -fall -max 29.322 [get_clocks {UCLK}]
set_clock_transition -fall -min 29.322 [get_clocks {UCLK}]

foreach_in_collection pin [get_cells -hierarchical -filter "ref_name == trfpss2pslvt64x72m1n"] {   
    set_case_analysis 0 [get_pins [get_object_name $pin]/LV]                                                                                      
 }



set CLOCK_PERIOD(UCLK) 274.6

   set colFunctionalClocks [get_clocks -quiet [list FCLK UCLK DFICLK ] ]
   set colRefclkClocks         [get_clocks -quiet {REFCLK REFCLK_SYN ACP_REFCG_24MHZ_CLK REFCLK_100 REF_BYPCLK_100 Cpl_VDDCR_SOC_REFCLK}]
   set colScanClocks       [get_clocks -quiet {CHIP_SC2_CLK MTAP_Wrck CHIP_TCLK DFX_SCAN_SHIFT_CLK UMC_WRCK_UMC UMC_WRCK_UMC_SYN}]
   fif { [amd_getvarsave DDRSS_FEINT_IS_TILE_RTL 1] } {
     set colSmnClock         [get_clocks -quiet {SMNCLK}]
   }
   
   # ------------------------------- Cross Clock ------------------------------
   
   #
   set period [get_attribute [get_clock UCLK] period]
   set_max_delay [expr 20*$period] -from $colFunctionalClocks -to $colRefclkClocks
   set_max_delay [expr 20*$period] -from $colRefclkClocks -to $colFunctionalClocks
   catch { set_max_delay 4000 -from $colFunctionalClocks -to $colRefClock }
   catch { set_max_delay 4000 -from $colRefClock -to $colFunctionalClocks }
   catch { set_max_delay 6000 -from $colFunctionalClocks -to $colScanClocks }
   catch { set_max_delay 6000 -from $colScanClocks -to $colFunctionalClocks }
   fif { [amd_getvarsave DDRSS_FEINT_IS_TILE_RTL 1] } {
     catch { set_max_delay 6000 -from $colFunctionalClocks -to $colScanClocks }
     catch { set_max_delay 4000 -from $colFunctionalClocks -to $colSmnClock }
     catch { set_max_delay 4000 -from $colRefClock -to $colScanClocks }
     catch { set_max_delay 4000 -from $colRefClock -to $colSmnClock }
     catch { set_max_delay 6000 -from $colScanClocks -to $colFunctionalClocks }
     catch { set_max_delay 4000 -from $colScanClocks -to $colRefClock }
     catch { set_max_delay 4000 -from $colScanClocks -to $colSmnClock }
     catch { set_max_delay 4000 -from $colSmnClock -to $colFunctionalClocks }
     catch { set_max_delay 4000 -from $colSmnClock -to $colScanClocks }
     catch { set_max_delay 4000 -from $colSmnClock -to $colRefClock }
   }
   
      #to ensure that the tool works on these paths as well
      set_max_delay 100 -from [get_ports {Cpl_MCLK Cpl_FCLK}] -to [get_ports preUCLK]
      set_max_delay 100 -from [get_ports {Cpl_FCLK}] -to [get_ports preFCLK]
      set_max_delay 100 -from [get_ports {Cpl_MCLK Cpl_FCLK}] -to [get_ports preDFICLK]
      set_max_delay 100 -from [get_ports {Cpl_FCLK Cpl_MCLK}] -to [get_ports preAPBCLK]

   
   source  tune/$TARGET_NAME/Syn.ClockSkew.tcl

   set lstUclk {UCLK}
   set CLOCK_PERIOD(UCLK) [get_at [index [get_clocks -quiet $lstUclk] 0] period]
   set_input_delay  -clock [get_clocks -quiet $lstUclk]   [expr 0.40*$CLOCK_PERIOD(UCLK)]   [get_ports [all_inputs]]
   set_output_delay  -clock [get_clocks -quiet $lstUclk]   [expr 0.40*$CLOCK_PERIOD(UCLK)]   [get_ports [all_outputs]]

   set all_inputs_but_clocks [remove_from_collection [all_inputs] [get_attribute [all_clocks] sources]]
   group_path -name reg2out -to [all_outputs] -critical_range 200 -weight 1 -priority 2
   group_path -name in2reg -from $all_inputs_but_clocks -critical_range 200 -weight 1 -priority 2
   group_path -name in2out -from $all_inputs_but_clocks -to [all_outputs] -critical_range 200 -weight 1 -priority 2

