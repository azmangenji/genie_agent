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

group_path -name SYN_I2O -critical_range 200 -weight 0.001 -priority 1 -from $pi -to $po
group_path -name SYN_I2R -critical_range 200 -weight 1 -priority 1 -from $pi -to $rr
group_path -name SYN_R2O -critical_range 200 -weight 1 -priority 1 -from $ff -to $po

group_path -name SYN_R2R_2gclk -critical_range 200 -weight 1 -priority 2 -from $ff -to $ck

group_path -name SYN_R2R -critical_range 200 -weight 7 -priority 4 -from $ff -to $ff

group_path -name umc_cmd_r2r_from -critical_range 200 -weight 10 -priority 7 -from [filter_collection $ff "full_name=~*umccmd*"] -to [all_registers]
group_path -name umc_cmd_r2r -critical_range 200 -weight 1 -priority 1 -from [filter_collection $ff "full_name=~*umccmd*"] -to [filter_collection $ff "full_name=~*umccmd*"]
group_path -name FEI_r2r -critical_range 100 -weight 1 -priority 2 -from [filter_collection $ff "full_name=~FEI*"] -to [filter_collection $ff "full_name=~FEI*"]
group_path -name FEI_ADDR_r2r -critical_range 200 -weight 8 -priority 6 -from [filter_collection $ff "full_name=~FEI*"] -to [filter_collection $ff "full_name=~ADDR*"]
group_path -name SPAZ_r2r -critical_range 50 -weight 1 -priority 1 -from [filter_collection $ff "full_name=~SPAZ*"] -to [filter_collection $ff "full_name=~SPAZ*"]

group_path -name umc_ARB_r2r_from -critical_range 200 -weight 10 -priority 8 -from [filter_collection $ff "full_name=~*ARB/*"] -to $ff
group_path -name umc_ARB_r2r_to -critical_range 200 -weight 10 -priority 8 -from $ff -to [filter_collection $ff "full_name=~*ARB/*"]

group_path -name umc_DCQARB_r2r_to -critical_range 200 -weight 10 -priority 10 -from $ff  -to [filter_collection $ff "full_name=~*ARB/DCQARB*"]
group_path -name umc_DCQARB_r2r -critical_range 200 -weight 9 -priority 10 -from [filter_collection $ff "full_name=~*ARB/DCQARB*"]  -to [filter_collection $ff "full_name=~*ARB/DCQARB*"]
group_path -name umc_DCQARB_r2r_from -critical_range 200 -weight 9 -priority 9 -from [filter_collection $ff "full_name=~*ARB/DCQARB*"]  -to [filter_collection $ff "full_name=~*ARB/TIM"]

group_path -name SYN_DFICLK -critical_range 200 -weight 1 -priority 1 -from [get_clocks DFICLK] -to [get_clocks UCLK]
group_path -name SYN_DFICLK -critical_range 200 -weight 1 -priority 1 -from [get_clocks UCLK] -to [get_clocks DFICLK]
group_path -name SYN_DFICLK -critical_range 200 -weight 1 -priority 1 -from [get_clocks DFICLK] -to [get_clocks DFICLK]
