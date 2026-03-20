#Flatten cells
### Aligned with Tile level run - 9/24
#ungroup [get_cells -hier * -filter @ref_name=~"*umcdcq*_index64*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcdcq*_mux64*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcdcq*_ptr64*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcarbctrlsw*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*sdpchn*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*sdpintf*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*fei*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*cmdarb*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*addrdec_dimm*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umc_par*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcdcqarb_therm*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcbeq_rvsdqmap*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcbeq_dqmap*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umceccx4cor*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcbeq_tx*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcbeq_dec*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*aessubbyte*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*aesshiftrows*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*aesmixcolumns*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*aesinvmixcols*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcarb*"] -flat
#ungroup [get_cells -hier * -filter @ref_name=~"*umcctrl_rrw"] -flat
set_attribute [get_ports *] physical_status fixed;
set_attribute [get_terminals -of [get_ports *]] physical_status fixed

#set retention_names {MB2SRLRZSDFKRPQD1AMDBWP840H6P51CNODULVTLL MB2SRLRZSDFKRPQD2AMDBWP840H6P51CNODULVTLL  MB2SRLRZSDFQD1AMDBWP420H6P51CNODULVTLL  MB2SRLRZSDFQD2AMDBWP420H6P51CNODULVTLL MB2SRLRZSDFRPQD1AMDBWP420H6P51CNODULVTLL MB2SRLRZSDFRPQD2AMDBWP420H6P51CNODULVTLL MB4SRLRZSDFKRPQD1AMDBWP840H6P51CNODULVTLL MB4SRLRZSDFQD1AMDBWP840H6P51CNODULVTLL MB4SRLRZSDFQD2AMDBWP840H6P51CNODULVTLL MB4SRLRZSDFRPQD1AMDBWP840H6P51CNODULVTLL MB4SRLRZSDFRPQD2AMDBWP840H6P51CNODULVTLL  MB6SRLRZSDFQD1AMDBWP630H6P51CNODULVTLL MB6SRLRZSDFQD2AMDBWP630H6P51CNODULVTLL MB8SRLRZSDFQD1AMDBWP840H6P51CNODULVTLL MB8SRLRZSDFQD2AMDBWP840H6P51CNODULVTLL RZSDFKRPQD1AMDBWP210H6P51CNODULVTLL RZSDFKRPQD2AMDBWP210H6P51CNODULVTLL RZSDFQD1AMDBWP210H6P51CNODULVTLL RZSDFQD2AMDBWP210H6P51CNODULVTLL RZSDFRPQD1AMDBWP420H6P51CNODULVTLL RZSDFRPQD2AMDBWP420H6P51CNODULVTLL RZSDFSNQD1AMDBWP210H6P51CNODULVTLL}
remove_clock_gating_check -setup [get_cells -hier * -filter "ref_name=~CKOR*"]
set_clock_gating_check -setup 50 [get_cells -hier * -filter "ref_name=~CKOR*"]


# fix snps_* issue
#set_app_options -name compile.flow.enhanced_timing_opto -value false

###############################################################################################################
# Synthesis switches merge from MD/SW df_project/
###############################################################################################################

set_app_options -list {compile.flow.propagate_constants_through_size_only_registers false}

# FJ 4-27-15: set duplicate name's format
set_app_options -list {compile.seqmap.register_replication_naming_style "%s_dup%d"}

# Set the max transition and fanout
# BOZO cstites 9/14/17 - These can be pushed into the flow
#set_max_transition [amd_getvarsave DDRSS_FEINT_MAX_TRANSITION 50] [current_design]


###############################################################################################################
# General Path Groups
###############################################################################################################

# Source all user group paths
tunesource tune/$TARGET_NAME/$TARGET_NAME.group_paths.tcl

###############################################################################################################
# Synthesis switches
###############################################################################################################
# Do synthesis with 4 cores.
remove_host_options -all
set_host_options -max_cores 64

# BW: We see a noteable improvement in timing with these switches with little added runtime.
#--- tool settings & synthesis settings
#set psynopt_tns_high_effort true
set_app_options -list {place.coarse.tns_driven_placement true}
#set_cost_priority -delay
set_app_options -list {compile.flow.high_effort_timing 1}
#FIXME : need to find eq in FC
#set_dp_smartgen_options -optimize_for speed
#set_structure true -timing true
#^ always enabled in FC
#set_app_options -list {time.use_pt_delay true}
set_app_options -list {opt.common.advanced_logic_restructuring_wirelength_costing high}

# trying to prevent assign statements on output ports as it breaks scan insertion.
set_fix_multiple_port_nets -all -buffer_constants [get_modules *]

# This propagates constants and removes unloaded logic, which results in a good percentage of the logic being optimized away.
set_app_options -list {compile.seqmap.remove_constant_registers true}
# FIXME : need to check the below app options
#set_app_options -list {compile.seqmap.remove_constant_registers_stuck_in_reset_state true}
set_app_options -list {compile.seqmap.remove_unloaded_registers true}

set_app_options -list {compile.flow.propagate_constants_through_dont_touch_cells false}
set_app_options -list {compile.flow.propagate_constants_through_size_only_registers false}

set_app_options -list {compile.seqmap.register_replication_naming_style %s_dup%d}

#Specifies the maximum design utilization after congestion driven padding (localized util)
set_app_options -list {place.coarse.congestion_driven_max_util 0.88}
#FIXME : try with 0.7 as well and see QOR impact in critical tiles
set_app_options -list {place.coarse.max_density 0.8}

# Set the max transition and fanout
set_max_transition [amd_getvarsave DDRSS_FEINT_MAX_TRANSITION 40] [current_design]
set_max_fanout [amd_getvarsave DDRSS_FEINT_MAX_FANOUT 20] [current_design]

# cstites 9/26/17 These lines are duplicates of the ones used in the supra flow
set_congestion_optimization [get_designs] TRUE
if { 0 < [sizeof_collection [get_cells -quiet -hier * -filter "is_hierarchical == true"]] } {
   set_congestion_optimization [get_cells -hier * -filter "is_hierarchical == true"] true
}

# cstites 9/26/17 This settings is only for topo mode.
# Synopsys doc: "Enable Zroute-based congestion-driven placement to perform more accurate, congestion-aware
# placement."
# FIXME : need to find the eq in FC
#?set placer_enable_enhanced_router true

set_app_options -list {compile.initial_place.placement_congestion_effort medium}
set_app_options -list {compile.initial_opto.placement_congestion_effort high}
set_app_options -list {compile.flow.layer_aware_optimization true}
set_app_options -list {compile.seqmap.identify_shift_registers false}


###############################################################################################################
# Cell/Vt types
###############################################################################################################
#set_app_options -name shell.dc_compatibility.remove_libcell_attribute -value true


###############################################################################################################
# Remove path margin
###############################################################################################################

set_app_options -list {compile.flow.propagate_constants_through_size_only_registers true}
set_app_options -list {compile.flow.propagate_constants_through_dont_touch_cells true}

set_multibit_options -slack_threshold 0
set_app_option -name compile.flow.enable_rtl_multibit_debanking -value true
set_app_option -name compile.flow.enable_physical_multibit_banking -value true
set_app_option -name compile.flow.enable_multibit_debanking -value true
set_app_option -name compile.flow.enable_rtl_multibit_banking -value true

set_size_only [get_cells -hier * -f "full_name=~*/Array_reg_*"] true

###############################################################################################################
# Size Only on data latches
###############################################################################################################
#In NV31 mcd, as the lat arr were being banked and unbanked - going it leave it here for now
set colLatArr [get_flat_cells -of [get_cells -hierarchical * -filter "ref_name=~*lat*arr*"] -filter "full_name=~*Array_reg*"]
fif {[sizeof $colLatArr] > 0} {
   set_size_only $colLatArr true
   set_dont_touch $colLatArr true
}



#Required by designer for debug.
save_lib -as data/Synthesize_pre_opt.nlib

#setting clock transition time to 50ps 11/12 after discussion with Umesh
set_clock_transition  50  [get_clocks UCLK]
