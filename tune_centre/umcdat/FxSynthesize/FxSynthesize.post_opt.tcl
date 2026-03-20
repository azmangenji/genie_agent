
source tune/$TARGET_NAME/FxSynthesize.userprocs2.tcl

# Ensure CLOCK_PERIOD(UCLK) is defined
if {![info exists CLOCK_PERIOD(UCLK)]} {
    set uclk_clocks [get_clocks -quiet UCLK]
    if {[sizeof_collection $uclk_clocks] > 0} {
        set CLOCK_PERIOD(UCLK) [get_attribute [get_clocks UCLK] period]
        puts "INFO: Set CLOCK_PERIOD(UCLK) = $CLOCK_PERIOD(UCLK) from clock"
    } else {
        set CLOCK_PERIOD(UCLK) 274.6
        puts "WARNING: Using default CLOCK_PERIOD(UCLK) = 274.6"
    }
}

# disable incremental compile in Full run (enable scan insertion)

####################################
# Compile 2
####################################
#compile_fusion -from initial_opto -to initial_opto
#update_timing -full
#save_lib  -compress -as data/Synthesize.pass2.nlib
#df_feint_report_timing $TARGET_NAME 2

####################################
# More incremental Compile if required
####################################
# Find the worst negative slack in the register-to-register paths
set AllRegs [filter_collection [all_registers -edge] "is_integrated_clock_gating_cell == false"]
set wnsr2r [get_attr [get_timing_paths -max_paths 1  -from $AllRegs -to  [all_registers]] slack]

# Set the maximum number of compiles. This value needs to provide a balance between incremental QoR improvement and runtime. 
set MaxCompiles $P(DDRSS_FEINT_NUM_COMPILES)

# Run multiple compiles if the WNS doesn't meet the target threshold
if {$wnsr2r < [expr -0.025*$CLOCK_PERIOD(UCLK)] } {

# Report Timing for the first compile
    update_timing -ful
    sh rm -rf data/Synthesize.pass*.nlib
    save_lib  -compress -as data/Synthesize.pass1.nlib
    df_umc_feint_report_timing $TARGET_NAME 1

    set CurrentCompile 2
    puts "Incremental Compile $CurrentCompile"
    compile_fusion -from initial_opto -to initial_opto

    # Save the nlib and qor report for the initial compile
    update_timing -full
    save_lib -compress -as data/Synthesize.pass$CurrentCompile.nlib
    df_umc_feint_report_timing $TARGET_NAME $CurrentCompile
    
    set wnsr2r [get_attr [get_timing_paths -max_paths 1  -from $AllRegs -to  [all_registers]] slack]

    # Keep doing compiles until the WNS target or the max number of compiles is hit
    while {[expr {$wnsr2r < [expr -0.025*$CLOCK_PERIOD(UCLK)]}] && [expr {$CurrentCompile < $MaxCompiles}]} {

        incr CurrentCompile
        puts "Incremental Compile $CurrentCompile"
        compile_fusion -from initial_opto -to initial_opto

        update_timing -full
        save_lib -compress -as data/Synthesize.pass$CurrentCompile.nlib
        df_umc_feint_report_timing $TARGET_NAME $CurrentCompile
        
        # Find the worst negative slack in the register-to-register paths
        set wnsr2r [get_attr [get_timing_paths -max_paths 1  -from $AllRegs -to  [all_registers]] slack]
    } 
}

set NumCompiles [amd_getvarsave DF_FEINT_NUM_COMPILES 5]
   set NumCompDone 4
   set PreCompDone $NumCompDone

   # compile 5 to NumCompiles-1
   for {set c 5} {$c < [expr $NumCompiles]} {incr c} {
      # output delays on the clock gater enables to account for the buffering
      #df_feint_clkgate_enable_delay   

      redirect -file logs/FxSynthesizeComp${c}.log {
         fif { ![regexp {^umc} $P(TOP_MODULE)] } {
            dynPathGroup
         }

         fif {$c ==5} {
            #FIXME : Umesh : we will be doing debanking here
         }
         #if {$c ==4} {
         #   set N6ffCells ""
         #   set fp [open "./tune/project/FxSynthesize/df_umc/all_flops_names.tcl" r]
         #   while { [gets $fp data] >= 0 } {
         #      regsub -all {ULT08_} $data LVT08_ sub1
         #      append_to_collection N6ffCells [get_lib_cells -quiet */$sub1]
         #   }
         #   close $fp
         #   set_attribute -quiet [get_lib_cells $N6ffCells] dont_use false
         #}

         update_timing -full
         compile_fusion -from initial_opto -to initial_opto
         update_timing -full
         sh rm -rf data/Synthesize.pass*.nlib
         save_lib  -compress -as data/Synthesize.pass${c}.nlib
         df_feint_report_timing $TARGET_NAME $c
      }
      incr NumCompDone
   }

