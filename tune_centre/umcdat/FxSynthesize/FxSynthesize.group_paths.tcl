######################
# Variables
######################

set ff [all_registers]                                         ;# flip-flops
set ck {}                                                      ;# clock-gaters
append_to_collection ck [get_cells -hier -filter "full_name=~*/*clk_gate*&&is_hierarchical==false"]
append_to_collection -unique ck [get_cells -hier -filter "ref_name=~*_CKGPRELATNX*&&is_hierarchical==false"]
set rr [add_to_collection $ff $ck]                             ;# reg2reg endpoints

set pi [remove_from_collection [all_inputs]     [filter_collection [get_attribute [get_clocks *] sources] "object_class==port&&pin_direction==in"]]
set po [all_outputs]                                           ;# Primary outputs


set fUsePriority 1
set nPriority 0

######################
# Path groups
######################
# More general groups go first
# Most specific groups go last

incr nPriority
group_path -name SYN_I2O -critical_range 200 -weight 0.001 -priority $nPriority -from $pi -to $po
group_path -name SYN_I2R -critical_range 200 -weight 1 -priority $nPriority -from $pi -to $rr
group_path -name SYN_R2O -critical_range 200 -weight 1 -priority $nPriority -from $ff -to $po

group_path -name SYN_R2R_2gclk -critical_range 200 -weight 1 -priority $nPriority -from $ff -to $ck

group_path -name SYN_R2R -critical_range 200 -weight 3 -priority 2 -from $ff -to $ff

group_path -name umc_dat_r2r -critical_range 200 -weight 3 -priority 2 -from [filter_collection $ff "full_name=~*umcdat*"] -to [filter_collection $ff "full_name=~*umcdat*"]
group_path -name umc_sec_r2r -critical_range 200 -weight 15 -priority 10 -from [filter_collection $ff "full_name=~*umcsec*"] -to [filter_collection $ff "full_name=~*umcsec*"]

group_path -name umc_BEQ_r2r -critical_range 200 -weight 10 -priority 5 -from [filter_collection $ff "full_name=~*BEQ/*"] -to $ff
group_path -name umc_BEQ_r2r -critical_range 200 -weight 10 -priority 5 -from $ff -to [filter_collection $ff "full_name=~*BEQ/*"]

group_path -name SYN_DFICLK -critical_range 200 -weight 1 -priority 4 -from [get_clocks DFICLK] -to [get_clocks UCLK]
group_path -name SYN_DFICLK -critical_range 200 -weight 1 -priority 4 -from [get_clocks UCLK] -to [get_clocks DFICLK]
group_path -name SYN_DFICLK -critical_range 200 -weight 1 -priority 4 -from [get_clocks DFICLK] -to [get_clocks DFICLK]
