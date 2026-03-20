#Flatten cells
### Aligned with Tile level run - 9/24
set_attribute [get_ports *] physical_status fixed;
set_attribute [get_terminals -of [get_ports *]] physical_status fixed

remove_clock_gating_check -setup [get_cells -hier * -filter "ref_name=~CKOR*"]
set_clock_gating_check -setup 50 [get_cells -hier * -filter "ref_name=~CKOR*"]


###############################################################################################################
# Synthesis switches merge from MD/SW df_project/
###############################################################################################################

set_app_options -list {compile.flow.propagate_constants_through_size_only_registers false}

# FJ 4-27-15: set duplicate name's format
set_app_options -list {compile.seqmap.register_replication_naming_style "%s_dup%d"}


###############################################################################################################
# General Path Groups
###############################################################################################################

# UMCDAT-specific group paths
set inP [remove_from_collection [all_inputs ] [get_ports [get_attribute [all_clocks] sources] -f "direction==in"]]
set outP [ remove_from_collection [all_output ] [get_ports [get_attribute [all_clocks] sources] -f "direction==out"]]

group_path -name DFICLK_R2R  -from [get_clocks { DFICLK }]  \
              -to [get_clocks { DFICLK }] \
              -critical_range 200 -priority 4 -weight 1

group_path -name UCLK_R2R  -from [get_clocks { UCLK }]  \
              -to [get_clocks { UCLK }] \
              -critical_range 200 -priority 4 -weight 3


group_path -name DFICLK_I2R  -from $inP  \
              -to [get_clocks { DFICLK }] \
              -critical_range 200 -priority 6 -weight 1
group_path -name DFICLK_R2O  -from [get_clocks { DFICLK }]   \
              -to $outP \
              -critical_range 200 -priority 6 -weight 1

group_path -name UCLK_I2R  -from $inP  \
              -to [get_clocks { UCLK }] \
              -critical_range 200 -priority 6 -weight 1
group_path -name UCLK_R2O  -from [get_clocks { UCLK }]   \
              -to $outP \
              -critical_range 200 -priority 6 -weight 1

group_path -name RDAESR2R  -from [all_registers -edge]   \
              -to  [get_cells -hier * -f "full_name=~*/RDPIPE*/RdDatPipe_reg*"] \
              -critical_range 200 -priority 7 -weight 10

group_path -name XTSAESR2R  -from [all_registers -edge]   \
              -to  [get_cells -hier * -f "full_name=~*/XTSPIPE*/XtsDatPipe_reg*"] \
              -critical_range 200 -priority 7 -weight 10

###############################################################################################################
# Synthesis switches
###############################################################################################################
# Do synthesis with 4 cores.
remove_host_options -all
set_host_options -max_cores 64

# BW: We see a noteable improvement in timing with these switches with little added runtime.
#--- tool settings & synthesis settings
set_app_options -list {place.coarse.tns_driven_placement true}
set_app_options -list {compile.flow.high_effort_timing 1}
set_app_options -list {opt.common.advanced_logic_restructuring_wirelength_costing high}

# trying to prevent assign statements on output ports as it breaks scan insertion.
set_fix_multiple_port_nets -all -buffer_constants [get_modules *]

# This propagates constants and removes unloaded logic, which results in a good percentage of the logic being optimized away.
set_app_options -list {compile.seqmap.remove_constant_registers true}
set_app_options -list {compile.seqmap.remove_unloaded_registers true}

set_app_options -list {compile.flow.propagate_constants_through_dont_touch_cells false}
set_app_options -list {compile.flow.propagate_constants_through_size_only_registers false}

set_app_options -list {compile.seqmap.register_replication_naming_style %s_dup%d}

#Specifies the maximum design utilization after congestion driven padding (localized util)
set_app_options -list {place.coarse.congestion_driven_max_util 0.88}
set_app_options -list {place.coarse.max_density 0.8}

# Set the max transition and fanout
set_max_transition [amd_getvarsave DDRSS_FEINT_MAX_TRANSITION 40] [current_design]
set_max_fanout [amd_getvarsave DDRSS_FEINT_MAX_FANOUT 20] [current_design]

# cstites 9/26/17 These lines are duplicates of the ones used in the supra flow
set_congestion_optimization [get_designs] TRUE
if { 0 < [sizeof_collection [get_cells -quiet -hier * -filter "is_hierarchical == true"]] } {
   set_congestion_optimization [get_cells -hier * -filter "is_hierarchical == true"] true
}

set_app_options -list {compile.initial_place.placement_congestion_effort medium}
set_app_options -list {compile.initial_opto.placement_congestion_effort high}
set_app_options -list {compile.flow.layer_aware_optimization true}
set_app_options -list {compile.seqmap.identify_shift_registers false}


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
set colLatArr [get_flat_cells -of [get_cells -hierarchical * -filter "ref_name=~*lat*arr*"] -filter "full_name=~*Array_reg*"]
fif {[sizeof $colLatArr] > 0} {
   set_size_only $colLatArr true
   set_dont_touch $colLatArr true
}


#Required by designer for debug.
save_lib -as data/Synthesize_pre_opt.nlib

#setting clock transition time to 50ps 11/12 after discussion with Umesh
set_clock_transition  50  [get_clocks UCLK]
