remove_clock_gating_check -setup [get_cells -hier * -filter "ref_name=~CKOR*"]
set_clock_gating_check -setup 50 [get_cells -hier * -filter "ref_name=~CKOR*"]
remove_path_margin -all -scenarios [all_scenarios]
