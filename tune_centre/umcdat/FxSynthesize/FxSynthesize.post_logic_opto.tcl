echo "Path groups added start"
source -e -v "/proj/rtg_oss_er_feint2/nagjv/mathura/syn/umcdat_05Dec_run1/main/pd/tiles/umcdat_run1_TileBuilder_Dec05_1123_49188_GUI/pathgroups.tcl"
echo "Path groups added end"
if {[string range $sh_product_version 2 12] >= "2021.06-SP3" && [get_product_build_date_in_decimal] < 2022.0413} {
    set_app_options -name compile.flow.effort -value high
}

compile_fusion -from initial_place -to initial_place
save_lib -as /proj/rtg_oss_er_feint2/nagjv/mathura/syn/umcdat_05Dec_run1/main/pd/tiles/run1_initial_opto_incr/data/FxSynthesize_initial_place.nlib

if {[info exists P(SYN_SAVE_SNAPSHOTS)] && ([regexp all $P(SYN_SAVE_SNAPSHOTS)] || [regexp initial_place $P(SYN_SAVE_SNAPSHOTS)])} {
    save_block -as initial_place
    if {[info exists P(SYN_SNAPSHOTS_COPY_TO_LOCAL)] && ($P(SYN_SNAPSHOTS_COPY_TO_LOCAL) == 1)} {
        save_lib -compress
        file delete -force data/Synthesize.nlib
        file copy [get_object_name [current_lib]] data/Synthesize.nlib
    }
}

puts stdout "Sourcing tune/FxSynthesize/FxSynthesize.post_initial_place.tcl..."
tunesource "tune/FxSynthesize/FxSynthesize.post_initial_place.tcl"

compile_fusion -from initial_drc -to initial_drc
save_lib -as /proj/rtg_oss_er_feint2/nagjv/mathura/syn/umcdat_05Dec_run1/main/pd/tiles/run1_initial_opto_incr/data/FxSynthesize_initial_drc.nlib

if {[info exists P(SYN_SAVE_SNAPSHOTS)] && ([regexp all $P(SYN_SAVE_SNAPSHOTS)] || [regexp initial_drc $P(SYN_SAVE_SNAPSHOTS)])} {
    save_block -as initial_drc
    if {[info exists P(SYN_SNAPSHOTS_COPY_TO_LOCAL)] && ($P(SYN_SNAPSHOTS_COPY_TO_LOCAL) == 1)} {
        save_lib -compress
        file delete -force data/Synthesize.nlib
        file copy [get_object_name [current_lib]] data/Synthesize.nlib
    }
}

puts stdout "Sourcing tune/FxSynthesize/FxSynthesize.pre_initial_opto.tcl..."
tunesource "tune/FxSynthesize/FxSynthesize.pre_initial_opto.tcl"

compile_fusion -from initial_opto -to initial_opto
save_lib -as /proj/rtg_oss_er_feint2/nagjv/mathura/syn/umcdat_05Dec_run1/main/pd/tiles/run1_initial_opto_incr/data/FxSynthesize_initial_opto.nlib
#
## Ensure physical-banking is disabled for any potential incremental initial_opto
#set_app_options -name compile.flow.enable_physical_multibit_banking -value false
#
#set unMapped [get_cells -quiet -hierarchical -filter "is_unmapped == true"]
#if {[sizeof_collection $unMapped]} {
#    puts "[join {AMD-Er ror:} {}] tile contains unmapped components. Please review the log logs/FxSynthesize.log for FLW-1241 messages. exiting."
#    puts "[join {AMD-Er ror:} {}] if see any unmapped power cells such as ISO/ELS, please review the rpts/FxSynthesize/analyze_mv_feasibility.rpt."
#    foreach_in_collection uc $unMapped {
#        redirect -append  rpts_uncompressed/FxSynthesize/FxSynthesize.unmapped.rpt {echo [get_object_name $uc]}
#    }
#    save_lib -compress
#    file delete -force data/Synthesize.unmapped.nlib
#    file copy [get_object_name [current_lib]] data/Synthesize.unmapped.nlib
#    exit
#}


