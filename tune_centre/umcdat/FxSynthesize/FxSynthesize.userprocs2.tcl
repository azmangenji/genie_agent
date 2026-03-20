
#################################################
#Author Narendra Akilla
#Applications Consultant
#Company Synopsys Inc.
#Not for Distribution without Consent of Synopsys
#################################################

#Version 1.4
#added -scenario support
#outputs report_qor messages
#issues messages about crpr and freq

proc proc_qor {args} {

  echo "\nVersion 1.4\n"
  parse_proc_arguments -args $args results
  set skew_flag [info exists results(-skew)]
  set scenario_flag [info exists results(-scenarios)]
  set pba_flag  [info exists results(-pba)]
  set file_flag [info exists results(-existing_qor_file)]
  set unit_flag [info exists results(-units)]
  if {[info exists results(-csv_file)]} {set csv_file $results(-csv_file)} else { set csv_file "qor.csv" }
  if {$file_flag&&$skew_flag} { echo "Warning!! -existing_qor_file is ignored when -skew is given" }
  if {$file_flag} { set qor_file  $results(-existing_qor_file) } else { set qor_file "" }
  if {[info exists results(-units)]} {set unit $results(-units)}

  set ::collection_deletion_effort low

  # run update_timing to ensure that the format is proper for parsing.
  update_timing

  if {(!$skew_flag)&&[file exists $qor_file]} { 
    set tmp [open $qor_file "r"]
    set x [read $tmp]
    close $tmp
  } else {
    if {$::synopsys_program_name != "pt_shell"} {
      if {$scenario_flag} {
        echo -n "Running report_qor -nosplit -scenarios $results(-scenarios) ... "
        redirect -tee -var x { report_qor -nosplit -scenarios $results(-scenarios) }
        echo "Done"
      } else {
        echo -n "Running report_qor -nosplit ...\n "
        redirect -tee -var x { report_qor -nosplit }
        echo "Done"
      }
    }
  }
  
  if {(!$unit_flag)} {
    catch {redirect -var y {report_units}}
    #regexp {Second\((\S+)\)\n} $y match unit
    regexp {time\s*:\s*\S+(.)s} $y match unit
    regexp {(\S+)\s+Second} $y match unit
  }
  if {[info exists unit]} {
    if {[regexp {p|e-12} $unit]} { set unit 1000000 } else { set unit 1000 }
  } else { set unit 1000 }
  
  set drc 0
  set cella 0
  set buf 0
  set leaf 0
  set tnets 0
  set cbuf 0
  set seqc 0
  set tran 0
  set cap 0
  set fan 0
  set combc 0
  set macroc 0
  set comba 0
  set seqa 0
  set desa 0
  set neta 0
  set netl 0
  set netx 0
  set nety 0
  set hierc 0
  set csv [open $csv_file "w"]

  if {$::synopsys_program_name != "pt_shell"} {
  #in dc or icc, process qor file lines
  set i 0
  set loop 0
  foreach line [split $x "\n"] {
  
    incr i
    #echo "Processing $i : $line"
    if {[regexp {^\s*Scenario\s+\'(\S+)\'} $line match scenario]} {
    } elseif {[regexp {^\s*Timing Path Group\s+[\'\(](\S+)[\'\)]} $line match group]} {
      regsub -all {\*} $group {} group
      #if {[info exists scenario]} { set group ${group}_$scenario }
      set group_data [list $group]
      unset -nocomplain lol cpl wns cp tns nvp wnsh tnsh nvph fr
    } elseif {[regexp {^\s*Levels of Logic\s*:\s*(\S+)} $line match lol]} {
      lappend group_data $lol
    } elseif {[regexp {^\s*Critical Path Length\s*:\s*(\S+)} $line match cpl]} {
      lappend group_data $cpl
    } elseif {[regexp {^\s*Critical Path Slack\s*:\s*(\S+)} $line match wns]} { 
      if {$wns == "uninit"} {
        set wns 0
      } else {
        set wns [expr {double($wns)}]
      }
      lappend group_data $wns
    } elseif {[regexp {^\s*Critical Path Clk Period\s*:\s*(\S+)} $line match cp]} { 
      if { $cp == "n/a"} { set cp 0 }
      #Added by Umesh
      if { $cp == "--"} { set cp 0 }
      if { ![regexp {^\d} $cp]} { set cp 0 }  
      set cp [expr {double($cp)}]
      lappend group_data $cp
    } elseif {[regexp {^\s*Total Negative Slack\s*:\s*(\S+)} $line match tns]} {
      lappend group_data $tns
    } elseif {[regexp {^\s*No\. of Violating Paths\s*:\s*(\S+)} $line match nvp]} {
      lappend group_data $nvp
      set loop 1
      #puts "$all_group_data"
    } elseif {[regexp {^\s*Worst Hold Violation\s*:\s*(\S+)} $line match wnsh]} {
      lappend group_data $wnsh
    } elseif {[regexp {^\s*Total Hold Violation\s*:\s*(\S+)} $line match tnsh]} {
      lappend group_data $tnsh
    } elseif {[regexp {^\s*No\. of Hold Violations\s*:\s*(\S+)} $line match nvph]} {
      lappend group_data $nvph
      set loop 2
    } elseif {[regexp {^\s*Hierarchical Cell Count\s*:\s*(\S+)} $line match hierc]} {
    } elseif {[regexp {^\s*Hierarchical Port Count\s*:\s*(\S+)} $line match hierp]} {
    } elseif {[regexp {^\s*Leaf Cell Count\s*:\s*(\S+)} $line match leaf]} {
      set leaf [expr {$leaf/1000}]
    } elseif {[regexp {^\s*Buf/Inv Cell Count\s*:\s*(\S+)} $line match buf]} {
      set buf [expr {$buf/1000}]
    } elseif {[regexp {^\s*CT Buf/Inv Cell Count\s*:\s*(\S+)} $line match cbuf]} {
    } elseif {[regexp {^\s*Combinational Cell Count\s*:\s*(\S+)} $line match combc]} {
      set combc [expr $combc/1000]
    } elseif {[regexp {^\s*Sequential Cell Count\s*:\s*(\S+)} $line match seqc]} {
    } elseif {[regexp {^\s*Macro Count\s*:\s*(\S+)} $line match macroc]} {
 
    } elseif {[regexp {^\s*Combinational Area\s*:\s*(\S+)} $line match comba]} {
      set comba [expr {int($comba)}]
    } elseif {[regexp {^\s*Noncombinational Area\s*:\s*(\S+)} $line match seqa]} {
      set seqa [expr {int($seqa)}]
    } elseif {[regexp {^\s*Net Area\s*:\s*(\S+)} $line match neta]} {
      set neta [expr {int($neta)}]
    } elseif {[regexp {^\s*Net XLength\s*:\s*(\S+)} $line match netx]} {
    } elseif {[regexp {^\s*Net YLength\s*:\s*(\S+)} $line match nety]} {
    } elseif {[regexp {^\s*Cell Area.*:\s*(\S+)} $line match cella]} {
      set cella [expr {int($cella)}]
    } elseif {[regexp {^\s*Design Area\s*:\s*(\S+)} $line match desa]} {
      set desa [expr {int($desa)}]
    } elseif {[regexp {^\s*Net Length\s*:\s*(\S+)} $line match netl]} {
      set netl [expr {int($netl)}]

    } elseif {[regexp {^\s*Total Number of Nets\s*:\s*(\S+)} $line match tnets]} {
      set tnets [expr {$tnets/1000}]
    } elseif {[regexp -nocase {^\s*Nets With Violations\s*:\s*(\S+)} $line match drc]} {
    } elseif {[regexp {^\s*Max Trans Violations\s*:\s*(\S+)} $line match tran]} {
    } elseif {[regexp {^\s*Max Cap Violations\s*:\s*(\S+)} $line match cap]} {
    } elseif {[regexp {^-*$} $line]} {
        if {$loop==1 || $loop ==2} {
            if {$loop == 1} {
                lappend group_data 0.0 
                lappend group_data 0.0
                lappend group_data 0
            }
            lappend all_group_data $group_data
        }
        set loop 0
    } elseif {[regexp {^\s*Max Fanout Violations\s*:\s*(\S+)} $line match fan]} {
    } elseif {[regexp {^\s*Error} $line]} {
      echo "Error in report_qor. Exiting ..."
      return
    }

  }
  #all lines of qor file read
  } else {
    #in pt shell need to get qor data thru get_timing commands
    set uncons $::timing_report_unconstrained_paths
    set ::timing_report_unconstrained_paths false
    if {$pba_flag} {
      echo "In PBA mode only failing paths upto 1000 are reported"
      set elimit $::pba_exhaustive_endpoint_path_limit
      echo "Setting pba_exhaustive_endpoint_path_limit to 10"
      set ::pba_exhaustive_endpoint_path_limit 10
    } else {
      echo "In PrimeTime only 25000 paths per path group are analyzed for TNS and NVP"
    }
    set grps [get_attribute [get_path_groups] full_name]
    foreach group $grps {
      #if {[string match $group **default**]} { echo "Skipping path group $group" ; continue }
      echo -n "\nProcessing Path Group $group"
      set group_coll [get_path_group $group]
      set group_coll [index_coll $group_coll [expr [sizeof $group_coll]-1]]
      redirect /dev/null { set wpath [get_timing_paths -group $group_coll] }
      redirect /dev/null { set whpath [get_timing_paths -delay min -group $group_coll] }
      if {[sizeof $wpath]>0&&[sizeof $whpath]>0} {
        #append group data only if setup and hold paths exists for that group
        unset -nocomplain wns cp tns nvp wnsh tnsh nvph
        #wns
        set wns [get_attribute $wpath slack]
        if {[string is alpha $wns]} { echo -n " : No real paths in group $group" ; continue }  
        set wns [expr {double($wns)}]
        #cp
        set cp [get_attribute [get_attribute $wpath endpoint_clock] period]
        if {$cp<=0} {set cp 0 }
        set cp [expr {double($cp)}]
        #tns and nvp
        set tns 0
        set nvp 0
        if {$wns<0} {
          if {$pba_flag} {
            redirect /dev/null { set vpaths [get_timing_paths -pba_mode exhaustive -group $group_coll -slack_less 0 -max_paths 1000] }
            append_to_coll tvpaths $vpaths
          } else {
            redirect /dev/null { set vpaths [get_timing_paths -group $group_coll -slack_less 0 -max_paths 25000] }
            append_to_coll tvpaths $vpaths
          }
          if {[sizeof $vpaths]>0} { 
            set wns [get_attribute [index_coll $vpaths 0] slack]
          } else { set wns 0.0 }
          set wns [expr {double($wns)}]
          set nvp [sizeof $vpaths]
          set slacks [get_attribute $vpaths slack]
          foreach s $slacks {set tns [expr {$tns+$s}] }
        }
        #wnsh
        set wnsh [get_attribute $whpath slack]
        set wnsh [expr {double($wnsh)}]
        lappend group_data $wnsh
        #tnsh and nvph
        set tnsh 0
        set nvph 0
        if {$wnsh<0} {
          if {$pba_flag} {
            redirect /dev/null { set vhpaths [get_timing_paths -pba_mode exhaustive -delay min -group $group_coll -slack_less 0 -max_paths 1000] }
            append_to_coll tvhpaths $vhpaths
          } else {
            redirect /dev/null { set vhpaths [get_timing_paths -delay min -group $group_coll -slack_less 0 -max_paths 25000] }
            append_to_coll tvhpaths $vhpaths
          }
          if {[sizeof $vhpaths]>0} {
            set wnsh [get_attribute [index_coll $vhpaths 0] slack]
          } else { set wnsh 0.0 }
          set wnsh [expr {double($wnsh)}]
          set nvph [sizeof $vhpaths]
          set slacks [get_attribute $vhpaths slack]
          foreach s $slacks {set tnsh [expr {$tnsh+$s}] }
        }
        #designs stats
        set all  [get_cells -hi * -f "is_hierarchical==false"]
        set seqc [sizeof [all_registers]]
        set leaf [expr {[sizeof $all]/1000}]
        #set tnets [sizeof [get_nets -hi *]]
        #foreach area [get_attr $all area] { set cella [expr {$cella+$area}] }
        #group
        set group_data [list $group]
        #for lol and cpl
        lappend group_data 0
        lappend group_data 0
        lappend group_data $wns
        lappend group_data $cp
        lappend group_data $tns
        lappend group_data $nvp
        lappend group_data $wnsh
        lappend group_data $tnsh
        lappend group_data $nvph
        lappend all_group_data $group_data
      }
    }
    echo "\n"
  }

  if {![info exists all_group_data]} {
    echo "Error!! no QoR data found to reformat"
    return
  }
  set maxl 0
  foreach g [lsort -real -index 3 $all_group_data] {
    set l [string length [lindex $g 0]]
    if {$maxl < $l} { set maxl $l }
  }
  set maxl [expr {$maxl+2}]
  if {$maxl < 20} { set maxl 20 }
  set drccol [expr {$maxl-13}]

  for {set i 0} {$i<$maxl} {incr i} { append bar - }

  if {$skew_flag} {
    if {$::timing_remove_clock_reconvergence_pessimism=="false"} {
      echo "WARNING!! crpr is not turned on, skew values reported could be pessimistic"
    }
    echo "Skews numbers reported include any ocv derates, crpr value is close, but may not match report_timing UITE-468"
    if {$::synopsys_program_name != "pt_shell"} {
      echo "Getting setup timing paths for skew analysis"
      redirect /dev/null {set paths [get_timing_paths -slack_less 0 -max_paths 100000] } 
      #workaround to populate crpr values, pre 12.06 ICC
      #set junk [index_collection $paths 0]
      #redirect /dev/null {report_crpr -from [get_attr $junk startpoint] -to [get_attr $junk endpoint]}
    } else { set paths $tvpaths }

    foreach_in_collection p $paths {

      set g [get_attribute [get_attribute -quiet $p path_group] full_name]
      set scenario [get_attribute -quiet $p scenario]
      if {$scenario !=""} { set g ${g}_$scenario }
      set e [get_attribute -quiet $p endpoint_clock_latency]
      set s [get_attribute -quiet $p startpoint_clock_latency]
      set crpr [get_attribute -quiet $p crpr_value]
      if {$::synopsys_program_name == "pt_shell"} { set crpr [get_attribute -quiet $p common_path_pessimism] }

      set skew [expr {$e-$s}]

      if {$skew<0}       { set skew [expr {$skew+$crpr}]
      } elseif {$skew>0} { set skew [expr {$skew-$crpr}]
      } elseif {$skew==0} {}

      if {![info exists g_wns($g)]} { set g_wns($g) $skew }
      if {![info exists g_tns($g)]} { set g_tns($g) $skew } else { set g_tns($g) [expr {$g_tns($g)+$skew}] }
    }

    if {$::synopsys_program_name != "pt_shell"} {
      echo "Getting hold  timing paths for skew analysis"
      redirect /dev/null { set paths [get_timing_paths -slack_less 0 -max_paths 100000 -delay min] }
    } else { set paths $tvhpaths }

    foreach_in_collection p $paths {

      set g [get_attribute [get_attribute -quiet $p path_group] full_name]
      set scenario [get_attribute -quiet $p scenario]
      if {$scenario !=""} { set g ${g}_$scenario }
      set e [get_attribute -quiet $p endpoint_clock_latency]
      set s [get_attribute -quiet $p startpoint_clock_latency]
      set crpr [get_attribute -quiet $p crpr_value]
      if {$::synopsys_program_name == "pt_shell"} { set crpr [get_attribute -quiet $p common_path_pessimism] }

      set skew [expr {$e-$s}]

      if {$skew<0}       { set skew [expr {$skew+$crpr}]
      } elseif {$skew>0} { set skew [expr {$skew-$crpr}]
      } elseif {$skew==0} {}

      if {![info exists g_wnsh($g)]} { set g_wnsh($g) $skew }
      if {![info exists g_tnsh($g)]} { set g_tnsh($g) $skew } else { set g_tnsh($g) [expr {$g_tnsh($g)+$skew}] }
    }

    set tns  0.0
    set nvp  0
    set tnsh 0.0
    set nvph 0

    echo ""
    echo "SKEW      - Skew on WNS Path"
    echo "AVGSKW    - Average Skew on TNS Paths"
    echo "NVP       - No. of Violating Paths"
    echo "FREQ      - Estimated Frequency, not accurate in some cases, multi/half-cycle, etc" 
    echo "WNS(H)    - Hold WNS"
    echo "SKEW(H)   - Skew on Hold WNS Path"
    echo "TNS(H)    - Hold TNS"
    echo "AVGSKW(H) - Average Skew on Hold TNS Paths"
    echo "NVP(H)    - Hold NVP"
    echo ""
    puts $csv "Path Group, WNS, SKEW, TNS, AVGSKW, NVP, FREQ, WNS(H), SKEW(H), TNS(H), AVGSKW(H), NVP(H)"
    echo [format "%-${maxl}s % 10s % 10s % 10s % 10s % 7s % 9s    % 8s % 10s % 10s % 10s % 7s" \
    "Path Group" "WNS" "SKEW" "TNS" "AVGSKW" "NVP" "FREQ" "WNS(H)" "SKEW(H)" "TNS(H)" "AVGSKW(H)" "NVP(H)"]
    echo "${bar}-------------------------------------------------------------------------------------------------------------------"

    foreach g [lsort -real -index 3 $all_group_data] {

      set wns  [expr {double([lindex $g 3])}]
      set per  [expr {double([lindex $g 4])}]
      if {$wns >= $per} { set freq 0.0
      } else { set freq [expr {1.0/($per-$wns)*$unit}] }
      if {![info exists wfreq]} { set wfreq $freq }

      if {![info exists g_wns([lindex $g 0])]} { 
        set g_wns([lindex $g 0]) 0.0
        set g_tns([lindex $g 0]) 0.0
      } else {
        set g_tns([lindex $g 0]) [expr {$g_tns([lindex $g 0])/[lindex $g 6]}]
        if {![info exists maxskew]} { set maxskew $g_wns([lindex $g 0]) }
        if {![info exists maxavg]} { set maxavg $g_tns([lindex $g 0]) }
        if {$maxskew>$g_wns([lindex $g 0])} { set maxskew $g_wns([lindex $g 0]) }
        if {$maxavg>$g_tns([lindex $g 0])} { set maxavg $g_tns([lindex $g 0]) }
      }

      if {![info exists g_wnsh([lindex $g 0])]} { 
        set g_wnsh([lindex $g 0]) 0.0
        set g_tnsh([lindex $g 0]) 0.0
      } else {
        set g_tnsh([lindex $g 0]) [expr {$g_tnsh([lindex $g 0])/[lindex $g 9]}]
        if {![info exists maxskewh]} { set maxskewh $g_wnsh([lindex $g 0]) }
        if {![info exists maxavgh]} { set maxavgh $g_tnsh([lindex $g 0]) }
        if {$maxskewh<$g_wnsh([lindex $g 0])} { set maxskewh $g_wnsh([lindex $g 0]) }
        if {$maxavgh<$g_tnsh([lindex $g 0])} { set maxavgh $g_tnsh([lindex $g 0]) }
      }

      puts $csv "[lindex $g 0], \
[lindex $g 3], \
$g_wns([lindex $g 0]), \
[format "%.1f" [lindex $g 5]], \
$g_tns([lindex $g 0]), \
[lindex $g 6], \
[format "%.0fMHz" $freq], \
[lindex $g 7], \
$g_wnsh([lindex $g 0]), \
[format "%.1f" [lindex $g 8]], \
$g_tnsh([lindex $g 0]), \
[lindex $g 9] \
"

      echo [format "%-${maxl}s % 10.3f % 10.3f % 10.1f % 10.3f % 7.0f % 7.0fMHz % 10.3f % 10.3f % 10.1f % 10.3f % 7.0f" \
      [lindex $g 0] \
      [lindex $g 3] \
      $g_wns([lindex $g 0]) \
      [lindex $g 5] \
      $g_tns([lindex $g 0]) \
      [lindex $g 6] \
      $freq         \
      [lindex $g 7] \
      $g_wnsh([lindex $g 0]) \
      [lindex $g 8] \
      $g_tnsh([lindex $g 0]) \
      [lindex $g 9] \
      ]

      set tns  [expr {$tns+[lindex $g 5]}]
      set nvp  [expr {$nvp+[lindex $g 6]}]
      set tnsh [expr {$tnsh+[lindex $g 8]}]
      set nvph [expr {$nvph+[lindex $g 9]}]

    }
    if {![info exists maxskew]} { set maxskew 0.0 }
    if {![info exists maxavg]} { set maxavg 0.0 }
    if {![info exists maxskewh]} { set maxskewh 0.0 }
    if {![info exists maxavgh]} { set maxavgh 0.0 }
    echo "${bar}-------------------------------------------------------------------------------------------------------------------"

    set wwns  [lindex [lindex [lsort -real -index 3 $all_group_data] 0] 3]
    set wwnsh [lindex [lindex [lsort -real -index 7 $all_group_data] 0] 7]
  
    puts $csv "Summary, $wwns, $maxskew, [format "%.1f" $tns], $maxavg, $nvp, [format "%.0fMHz" $wfreq], $wwnsh, $maxskewh, [format "%.1f" $tnsh], $maxavgh, $nvph"

    echo [format "%-${maxl}s % 10.3f % 10.3f % 10.1f % 10.3f % 7.0f % 7.0fMHz % 10.3f % 10.3f % 10.1f % 10.3f % 7.0f" \
    "Summary" "$wwns" "$maxskew" "$tns" "$maxavg" "$nvp" "$wfreq" "$wwnsh" "$maxskewh" "$tnsh" "$maxavgh" "$nvph"]
    echo "${bar}-------------------------------------------------------------------------------------------------------------------"

    puts $csv "CAP, FANOUT, TRAN, TDRC, CELLA, BUFS, LEAFS, TNETS, CTBUF, REGS"

    echo [format "% 7s % 7s % 7s % ${drccol}s % 10s % 10s % 10s % 7s % 10s % 10s" \
     "CAP" "FANOUT" "TRAN" "TDRC" "CELLA" "BUFS" "LEAFS" "TNETS" "CTBUF" "REGS"]
    echo "${bar}-------------------------------------------------------------------------------------------------------------------"

    puts $csv "$cap, $fan, $tran, $drc, $cella, ${buf}K, ${leaf}K, ${tnets}K, $cbuf, $seqc"

    echo [format "% 7s % 7s % 7s % ${drccol}s % 10s % 9sK % 9sK % 6sK % 10s % 10s" \
     $cap $fan $tran $drc $cella $buf $leaf $tnets $cbuf $seqc]
    echo "${bar}-------------------------------------------------------------------------------------------------------------------"

  } else {

    set tns  0.0
    set nvp  0
    set tnsh 0.0
    set nvph 0
    set wwns  [lindex [lindex [lsort -real -index 3 $all_group_data] 0] 3]
    set wwnsh [lindex [lindex [lsort -real -index 7 $all_group_data] 0] 7]
    set wwnsd $wwns
    set wwnshd $wwnsh
    #regsub -all {\-} $wwns {} wwnsd
    #regsub -all {\-} $wwnsh {} wwnshd

    foreach g [lsort -real -index 3 $all_group_data] {
      set tns  [expr {$tns+[lindex $g 5]}]
      set nvp  [expr {$nvp+[lindex $g 6]}]
      set tnsh [expr {$tnsh+[lindex $g 8]}]
      set nvph [expr {$nvph+[lindex $g 9]}]
      set tnsd $tns
      #regsub -all {\-} $tns {} tnsd
      regsub -all {\-} $nvp {} nvpd
      set tnshd $tnsh
      #regsub -all {\-} $tnsh {} tnshd
      regsub -all {\-} $nvph {} nvphd
    }
     echo "  --------------------------------------------------------------------\n"
     echo "  Design  WNS: $wwnsd  TNS: $tnsd  Number of Violating Paths: $nvpd\n"
     echo "  Design (Hold)  WNS: $wwnshd  TNS: $tnshd  Number of Violating Paths: $nvphd\n"
     echo "  --------------------------------------------------------------------\n"

     echo ""
     echo "NVP    - No. of Violating Paths"
     echo "FREQ   - Estimated Frequency, not accurate in some cases, multi/half-cycle, etc"
     echo "WNS(H) - Hold WNS"
     echo "TNS(H) - Hold TNS"
     echo "NVP(H) - Hold NVP"
     echo ""
     puts $csv "Path Group, WNS, TNS, NVP, FREQ, WNS(H), TNS(H), NVP(H)"
     echo [format "%-${maxl}s % 10s % 10s % 7s % 9s    % 8s % 10s % 7s" \
    "Path Group" "WNS" "TNS" "NVP" "FREQ" "WNS(H)" "TNS(H)" "NVP(H)"]
    echo "${bar}-----------------------------------------------------------------------"
  
    foreach g [lsort -real -index 3 $all_group_data] {
  
      set wns  [expr {double([lindex $g 3])}]
      set per  [expr {double([lindex $g 4])}]
      if {$wns >= $per} { set freq 0.0
      } else { set freq [expr {1.0/($per-$wns)*$unit}] }
      if {![info exists wfreq]} { set wfreq $freq }
      

      puts $csv "[lindex $g 0], \
[lindex $g 3], \
[format "%.1f" [lindex $g 5]], \
[lindex $g 6], \
[format "%.0fMHz" $freq], \
[lindex $g 7], \
[format "%.1f" [lindex $g 8]], \
[lindex $g 9] \
"

      echo [format "%-${maxl}s % 10.3f % 10.1f % 7.0f % 7.0fMHz % 10.3f % 10.1f % 7.0f" \
      [lindex $g 0] \
      [lindex $g 3] \
      [lindex $g 5] \
      [lindex $g 6] \
      $freq         \
      [lindex $g 7] \
      [lindex $g 8] \
      [lindex $g 9] \
      ]
  
  
    }
    echo "${bar}-----------------------------------------------------------------------"

  
    puts $csv "Summary, $wwns, [format "%.1f" $tns], $nvp, [format "%.0fMHz" $wfreq], $wwnsh, [format "%.1f" $tnsh], $nvph"

    echo [format "%-${maxl}s % 10.3f % 10.1f % 7.0f % 7.0fMHz % 10.3f % 10.1f % 7.0f" \
    "Summary" "$wwns" "$tns" "$nvp" "$wfreq" "$wwnsh" "$tnsh" "$nvph"]
    echo "${bar}-----------------------------------------------------------------------"

    puts $csv "CAP, FANOUT, TRAN, TDRC, CELLA, BUFS, LEAFS, TNETS, CTBUF, REGS"

    echo [format "% 7s % 7s % 7s % ${drccol}s % 10s % 7s % 9s % 11s % 10s % 7s" \
     "CAP" "FANOUT" "TRAN" "TDRC" "CELLA" "BUFS" "LEAFS" "TNETS" "CTBUF" "REGS"]
    echo "${bar}-----------------------------------------------------------------------"

    puts $csv "$cap, $fan, $tran, $drc, $cella, ${buf}K, ${leaf}K, ${tnets}K, $cbuf, $seqc"

    echo [format "% 7s % 7s % 7s % ${drccol}s % 10s % 6sK % 8sK % 10sK % 10s % 7s" \
     $cap $fan $tran $drc $cella $buf $leaf $tnets $cbuf $seqc]
    echo "${bar}-----------------------------------------------------------------------"

  }
  close $csv
  if {$::synopsys_program_name == "pt_shell"} { set ::timing_report_unconstrained_paths $uncons ; if {$pba_flag} { set ::pba_exhaustive_endpoint_path_limit $elimit } }
  echo "Written $csv_file"
}

define_proc_attributes proc_qor -info "USER PROC: reformats report_qor" \
          -define_args {
          {-existing_qor_file "Optional - Existing report_qor file to reformat" "<report_qor file>" string optional}
          {-scenarios "Optional - report qor on specified set of scenarios, skip on inactive scenarios" "{ scenario_name1 scenario_name2 ... }" string optional}
          {-skew     "Optional - reports skew and avg skew on failing path groups" "" boolean optional}
          {-csv_file "Optional - Output csv file name, default is qor.csv" "<output csv file>" string optional}
          {-units    "Optional - override the automatic units calculation" "<ps or ns>" string optional}
          {-pba      "Optional - to run exhaustive pba when in PrimeTime" "" boolean optional}
          }

#################################################
#Author Narendra Akilla
#Applications Consultant
#Company Synopsys Inc.
#Not for Distribution without Consent of Synopsys
#################################################

#Version 1.0
######Umesh 8/1/2023
#### This is multiple procs encapsulated (i.e. hierarchical definition), little messy to read but it end at the comment 'proc_compare_qor' ENDs

proc proc_compare_qor {args} { 

#######################
#SUB PROC
#######################

proc proc_myformat {file} {

  set tmp [open $file "r"]
  set x [read $tmp]
  close $tmp
  set start_flag 0

  foreach line [split $x "\n"] {
 
    #skip lines until the table
    if {!$start_flag} { if {![regexp {^\s*Path Group\s+WNS\s+} $line match]} { continue } }

    if {[regexp {^\s*Path Group\s+WNS\s+} $line match]} {
      set start_flag 1
    } elseif {[regexp {^\s*CAP\s+FANOUT\s+TRAN\s+} $line match]} {
    } elseif {[regexp {^\s*Summary\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line match wwns ttns tnvp wfreq wwnsh ttnsh tnvph]} {
      set summary [list total $wwns $ttns $tnvp $wfreq $wwnsh $ttnsh $tnvph]
    } elseif {[regexp {^\s*\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line match drc cella buf leaf tnets cbuf seqc]} {
      set stat [list $drc $cella $buf $leaf $cbuf $seqc $tnets]
    } elseif {[regexp {^\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line match group wns tns nvp freq wnsh tnsh nvph]} {
      lappend all_group_data [list $group $wns $tns $nvp $freq $wnsh $tnsh $nvph]
    }

  }

  return [list $all_group_data $summary $stat]

}

proc proc_myskewformat {file} {

  set tmp [open $file "r"]
  set x [read $tmp]
  close $tmp
  set start_flag 0

  foreach line [split $x "\n"] {

    #skip lines until the table
    if {!$start_flag} { if {![regexp {^\s*Path Group\s+WNS\s+} $line match]} { continue } }

    if {[regexp {^\s*Path Group\s+WNS\s+} $line match]} {
      set start_flag 1
    } elseif {[regexp {^\s*CAP\s+FANOUT\s+TRAN\s+} $line match]} {
    } elseif {[regexp {^\s*Summary\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line match wwns maxskew ttns maxavgskew tnvp wfreq wwnsh maxskewh ttnsh maxavgskewh tnvph]} {
      set summary [list total $wwns $maxskew $ttns $maxavgskew $tnvp $wfreq $wwnsh $maxskewh $ttnsh $maxavgskewh $tnvph]
    } elseif {[regexp {^\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line match group wns skew tns avgskew nvp freq wnsh skewh tnsh avgskewh nvph]} {
      lappend all_group_data [list $group $wns $skew $tns $avgskew $nvp $freq $wnsh $skewh $tnsh $avgskewh $nvph]
    } elseif {[regexp {^\s*\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line match drc cella buf leaf tnets cbuf seqc]} {
      set stat [list $drc $cella $buf $leaf $cbuf $seqc $tnets]
    }

  }

  return [list $all_group_data $summary $stat]

}

#######################
#END OF SUB PROC
#######################

parse_proc_arguments -args $args results

set unit_flag [info exists results(-units)]
if {[info exists results(-units)]} {set unit $results(-units)}
if {[info exists results(-csv_file)]} {set csv_file $results(-csv_file)} else { set csv_file "compare_qor.csv" }

if {(!$unit_flag)} {
  catch {redirect -var y {report_units}}
  regexp {Second\((\S+)\)\n} $y match unit
}

if {[info exists unit]} {
  if {[string match $unit ps]} { set unit ps } else { set unit ns }
} else { set unit ns }

set file_list $results(-qor_file_list)
if {[info exists results(-tag_list)]} { 
  set tag_list  $results(-tag_list) 
} else {
  set i 0 
  foreach file $file_list { lappend tag_list "qor_$i" ; incr i }
}

if {[llength $file_list] != [llength $tag_list]} { return "-tag_list and -qor_file_list should have same number of elements" }

if {[llength $file_list] <2} { return "Need atleast 2 files" }
if {[llength $file_list] >6} { return "Supports only upto 6 files" }

foreach file $file_list { if {![file exists $file]} { return "Given file $file does not exist" } }


set i 0
set skew_flag 0
foreach file $file_list {

  if {![catch {exec grep "Path Group.*AVGSKW" $file}]} {
    set skew_flag 1
    set qor_data($i) [proc_myskewformat $file]
  } elseif {![catch {exec grep "Path Group.*WNS" $file}]} {
    set qor_data($i) [proc_myformat $file]
  } else {
    proc_qor -qor_file $file -units $unit > .junk
    set qor_data($i) [proc_myformat .junk]
    file delete .junk
    file delete qor.csv
  }
  if {[llength $qor_data($i)] !=3} { return "Unable to process $file. Aborting ...." }
  incr i

}

set csv [open $csv_file "w"]

foreach ref_grps [lindex $qor_data(0) 0] {
  foreach e [list $ref_grps] { lappend ref_grp_list [lindex $e 0] }
}

foreach f [lsort -integer [array names qor_data]] {
  foreach grps_of_f [lindex $qor_data($f) 0] {
    foreach grp [list $grps_of_f]  {
      lappend all_grp_list [lindex $grp 0]
      set entry ${f}_[lindex $grp 0]
      if {$skew_flag} {
        if {[llength $grp]==8} {
          set all_data($entry) "[lindex $grp 1] 0.0 [lindex $grp 2] 0.0 [lindex $grp 3] [lindex $grp 4] [lindex $grp 5] 0.0 [lindex $grp 6] 0.0 [lindex $grp 7]"
        } else {
          set all_data($entry) "[lindex $grp 1] [lindex $grp 2] [lindex $grp 3] [lindex $grp 4] [lindex $grp 5] [lindex $grp 6] [lindex $grp 7] [lindex $grp 8] [lindex $grp 9] [lindex $grp 10] [lindex $grp 11]"
        }
      } else {
        set all_data($entry) "[lindex $grp 1] [lindex $grp 2] [lindex $grp 3] [lindex $grp 4] [lindex $grp 5] [lindex $grp 6] [lindex $grp 7]"
      }
    }
  }
}

set extra_grp_list [lminus [lsort -unique $all_grp_list] $ref_grp_list]

foreach extra $extra_grp_list { lappend ref_grp_list $extra }

set maxl 0
foreach g $ref_grp_list {
  set l [string length [lindex $g 0]]
  if {$maxl < $l} { set maxl $l }
}
set maxl [expr {$maxl+2}]
if {$maxl < 20} { set maxl 20 }
set drccol [expr {$maxl-13}]
for {set i 0} {$i<$maxl} {incr i} { append bar - }

puts -nonewline $csv ","
echo -n [format "%-${maxl}s " ""]

foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 8s " "$tag"] }

if {$skew_flag} {
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 8s " "$tag"] }
} 

foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 12s " "$tag"] }

if {$skew_flag} {
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 8s " "$tag"] }
}

foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 7s " "$tag"] }

foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 7s " "$tag"] }

foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 8s " "$tag"] }

if {$skew_flag} {
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 8s " "$tag"] }
}

foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 12s " "$tag"] }

if {$skew_flag} {
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 8s " "$tag"] }
}

foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 7s " "$tag"] }
puts $csv ""
echo ""

puts -nonewline $csv "Path Group,"

echo -n [format "%-${maxl}s " "Path Group"]
append line "$bar"

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "WNS,"
  echo -n [format "% 8s " "WNS"]
  append line "---------"
}

if {$skew_flag} {
  foreach f [lsort -integer [array names qor_data]] {
    puts -nonewline $csv "SKEW,"
    echo -n [format "% 8s " "SKEW"]
    append line "---------"
  }
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "TNS,"
  echo -n [format "% 12s " "TNS"]
  append line "-------------"
}

if {$skew_flag} {
  foreach f [lsort -integer [array names qor_data]] {
    puts -nonewline $csv "AVGSKEW,"
    echo -n [format "% 8s " "AVGSKEW"]
    append line "---------"
  }
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "NVP,"
  echo -n [format "% 7s " "NVP"]
  append line "--------"
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "FREQ,"
  echo -n [format "% 7s " "FREQ"]
  append line "--------"
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "WNSH,"
  echo -n [format "% 8s " "WNSH"]
  append line "---------"
}

if {$skew_flag} {
  foreach f [lsort -integer [array names qor_data]] {
    puts -nonewline $csv "SKEWH,"
    echo -n [format "% 8s " "SKEWH"]
    append line "---------"
  }
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "TNSH,"
  echo -n [format "% 12s " "TNSH"]
  append line "-------------"
}

if {$skew_flag} {
  foreach f [lsort -integer [array names qor_data]] {
    puts -nonewline $csv "AVGSKEWH,"
    echo -n [format "% 8s " "AVGSKEWH"]
    append line "---------"
  }
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "NVPH,"
  echo -n [format "% 7s " "NVPH"]
  append line "--------"
}

#unindented if
if {$skew_flag} {

puts -nonewline $csv "\n"
echo -n "\n$line"

foreach ref_grp $ref_grp_list {

  #name
  puts -nonewline $csv "\n$ref_grp,"
  echo -n [format "\n%-${maxl}s " $ref_grp]

  #wns
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 8.3f " [lindex $all_data($entry) 0]] } else { set value [format "% 8s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #skew 
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 8.3f " [lindex $all_data($entry) 1]] } else { set value [format "% 8s " NA] }
    puts -nonewline $csv "$value," 
    echo -n $value
  }

  #tns
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 12.1f " [lindex $all_data($entry) 2]] } else { set value [format "% 12s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #avgskew
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 8.3f " [lindex $all_data($entry) 3]] } else { set value [format "% 8s " NA] }
    puts -nonewline $csv "$value," 
    echo -n $value
  } 

  #nvp
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 7.0f " [lindex $all_data($entry) 4]] } else { set value [format "% 7s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #freq
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 7s " [lindex $all_data($entry) 5]] } else { set value [format "% 7s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #wnsh
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 8.3f " [lindex $all_data($entry) 6]] } else { set value [format "% 8s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #skewh
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 8.3f " [lindex $all_data($entry) 7]] } else { set value [format "% 8s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #tnsh
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 12.1f " [lindex $all_data($entry) 8]] } else { set value [format "% 12s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #avgskewh
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 8.3f " [lindex $all_data($entry) 9]] } else { set value [format "% 8s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #nvph
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 7.0f " [lindex $all_data($entry) 10]] } else { set value [format "% 7s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

}
puts $csv ""
echo "\n$line" 
puts -nonewline $csv "Summary,"
echo -n [format "%-${maxl}s " "Summary"]

foreach f [lsort -integer [array names qor_data]] {
    set qor_total($f) [lindex $qor_data($f) 1]
  if {[llength $qor_total($f)]<12} {
    set qor_total($f) "[lindex $qor_total($f) 0] [lindex $qor_total($f) 1] 0.0 [lindex $qor_total($f) 2] 0.0 [lindex $qor_total($f) 3] [lindex $qor_total($f) 4] [lindex $qor_total($f) 5] 0.0 [lindex $qor_total($f) 6] 0.0 [lindex $qor_total($f) 7]"
  }
}

#twns
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.3f " [lindex $qor_total($f) 1]] ; puts -nonewline $csv "[lindex $qor_total($f) 1]," }

#maxskew
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.3f " [lindex $qor_total($f) 2]] ; puts -nonewline $csv "[lindex $qor_total($f) 2]," }

#ttns
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 12.1f " [lindex $qor_total($f) 3]] ; puts -nonewline $csv "[lindex $qor_total($f) 3]," }

#maxavgskew
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.3f " [lindex $qor_total($f) 4]] ; puts -nonewline $csv "[lindex $qor_total($f) 4]," }

#tnvp
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7.0f " [lindex $qor_total($f) 5]] ; puts -nonewline $csv "[lindex $qor_total($f) 5]," }

#tfreq
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7s " [lindex $qor_total($f) 6]] ; puts -nonewline $csv "[lindex $qor_total($f) 6]," }

#twnsh
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.3f " [lindex $qor_total($f) 7]] ; puts -nonewline $csv "[lindex $qor_total($f) 7]," }

#maxskewh
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.3f " [lindex $qor_total($f) 8]] ; puts -nonewline $csv "[lindex $qor_total($f) 8]," }

#ttnsh
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 12.1f " [lindex $qor_total($f) 9]] ; puts -nonewline $csv "[lindex $qor_total($f) 9]," }

#maxavgskewh
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.3f " [lindex $qor_total($f) 10]] ; puts -nonewline $csv "[lindex $qor_total($f) 10]," }

#tnvph
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7.0f " [lindex $qor_total($f) 11]] ; puts -nonewline $csv "[lindex $qor_total($f) 11]," }

puts $csv ""
echo "\n$line"

#unindented else
} else {
#if no skew flag

puts -nonewline $csv "\n"
echo -n "\n$line"

foreach ref_grp $ref_grp_list {

  #name
  puts -nonewline $csv "\n$ref_grp,"
  echo -n [format "\n%-${maxl}s " $ref_grp]

  #wns
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 8.3f " [lindex $all_data($entry) 0]] } else { set value [format "% 8s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #tns
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 12.1f " [lindex $all_data($entry) 1]] } else { set value [format "% 12s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #nvp
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 7.0f " [lindex $all_data($entry) 2]] } else { set value [format "% 7s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #freq
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 7s " [lindex $all_data($entry) 3]] } else { set value [format "% 7s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #wnsh
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 8.3f " [lindex $all_data($entry) 4]] } else { set value [format "% 8s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #tnsh
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 12.1f " [lindex $all_data($entry) 5]] } else { set value [format "% 12s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

  #nvph
  foreach f [lsort -integer [array names qor_data]] {
    set entry ${f}_$ref_grp
    if {[info exists all_data($entry)]} { set value [format "% 7.0f " [lindex $all_data($entry) 6]] } else { set value [format "% 7s " NA] }
    puts -nonewline $csv "$value,"
    echo -n $value
  }

}
puts $csv ""
echo "\n$line" 
puts -nonewline $csv "Summary,"
echo -n [format "%-${maxl}s " "Summary"]

foreach f [lsort -integer [array names qor_data]] {
  set qor_total($f) [lindex $qor_data($f) 1]
}

#twns
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.3f " [lindex $qor_total($f) 1]] ; puts -nonewline $csv "[lindex $qor_total($f) 1]," }

#ttns
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 12.1f " [lindex $qor_total($f) 2]] ; puts -nonewline $csv "[lindex $qor_total($f) 2],"}

#tnvp
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7.0f " [lindex $qor_total($f) 3]] ; puts -nonewline $csv "[lindex $qor_total($f) 3]," }

#tfreq
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7s " [lindex $qor_total($f) 4]] ; puts -nonewline $csv "[lindex $qor_total($f) 4]," }

#twnsh
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.3f " [lindex $qor_total($f) 5]] ; puts -nonewline $csv "[lindex $qor_total($f) 5]," }

#ttnsh
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 12.1f " [lindex $qor_total($f) 6]] ; puts -nonewline $csv "[lindex $qor_total($f) 6]," }

#tnvph
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7.0f " [lindex $qor_total($f) 7]] ; puts -nonewline $csv "[lindex $qor_total($f) 7]," }

puts $csv ""
echo "\n$line"

}
#end unindented no skew flag

puts -nonewline $csv " ,"
echo -n [format "%-${maxl}s " " "]
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 8s " "$tag"] }
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 12s " "$tag"] }
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 7s " "$tag"] }
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 7s " "$tag"] }
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 8s " "$tag"] }
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 12s " "$tag"] }
foreach tag $tag_list { puts -nonewline $csv "$tag,";  echo -n [format "% 7s " "$tag"] }
puts $csv ""
echo ""

puts -nonewline $csv " ,"
echo -n [format "%-${maxl}s " " "]

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "DRC,"
  echo -n [format "% 8s " "DRC"]
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "CELLA,"
  echo -n [format "% 12s " "CELLA"]
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "BUF,"
  echo -n [format "% 7s " "BUF"]
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "LEAF,"
  echo -n [format "% 7s " "LEAF"]
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "CBUFS,"
  echo -n [format "% 8s " "CBUFS"]
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "REGS,"
  echo -n [format "% 12s " "REGS"]
}

foreach f [lsort -integer [array names qor_data]] {
  puts -nonewline $csv "NETS,"
  echo -n [format "% 7s " "NETS"]
}

puts $csv ""
echo "\n$line" 

puts -nonewline $csv ","
echo -n [format "%-${maxl}s " " "]

foreach f [lsort -integer [array names qor_data]] {
  set qor_stat($f) [lindex $qor_data($f) 2]
}

#drc
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8.0f " [lindex $qor_stat($f) 0]] ; puts -nonewline $csv " [lindex $qor_stat($f) 0]," }

#cella
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 12.0f " [lindex $qor_stat($f) 1]] ; puts -nonewline $csv " [lindex $qor_stat($f) 1]," }

#buf
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7s " [lindex $qor_stat($f) 2]] ; puts -nonewline $csv " [lindex $qor_stat($f) 2]," }

#leaf
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7s " [lindex $qor_stat($f) 3]] ; puts -nonewline $csv " [lindex $qor_stat($f) 3]," }

#cbuf
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 8s " [lindex $qor_stat($f) 4]] ; puts -nonewline $csv " [lindex $qor_stat($f) 4]," }

#seqc
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 12s " [lindex $qor_stat($f) 5]] ; puts -nonewline $csv " [lindex $qor_stat($f) 5]," }

#tnets
foreach f [lsort -integer [array names qor_data]] { echo -n [format "% 7s " [lindex $qor_stat($f) 6]] ; puts -nonewline $csv " [lindex $qor_stat($f) 6]," }

puts $csv ""
echo "\n$line"

close $csv
echo "Written $csv_file\n"
}
#####'proc_compare_qor' ENDs, above culry braces closes the proc.
#8/1/2023

define_proc_attributes proc_compare_qor -info "USER PROC: Compares upto 6 report_qor reports" \
	-define_args { 
        {-qor_file_list "Required - List of report_qor files to compare" "<report_qor file list>" string required} 
        {-tag_list "Optional - Tag each QoR report with a name" "<qor file tag list" string optional} 
        {-csv_file "Optional - Output csv file name, default is compare_qor.csv" "<output csv file>" string optional}
        {-units    "Optional - specify ps to override the default, default uses report_unit or ns" "<units >" string optional}
        }

##############################################
####### Port Bounds for flopped I/O ##########
### Umesh (07/12/2020)           #############
##############################################
proc boundOneReg2Port {PortColl hardBnd radius bndPrefix {otherDir 0}} {
 set RegColl ""
 set CellCnt 0
 set numPorts 0
 set edgeV 0
 set edgeH 0
 set llX 9999999999.0 
 set urX -9999999999.0
 set llY 9999999999.0
 set urY -9999999999.0
 if {[info exists portRegColl]} {unset portRegColl}

 append_to_collection -unique mPortColl [get_ports $PortColl]
 foreach_in_collection EachPort $mPortColl {
    set EachPortName [get_object_name $EachPort]
    #echo "$EachPortName"
    set Dir [get_att $EachPort direction]
    if {$Dir=="in"}  {set RegColl [get_cells [all_fanout -flat -from $EachPort -only_cells -endpoints_only] -f "is_integrated_clock_gating_cell!=true"]}
    if {$Dir=="out"} {set RegColl [get_cells [all_fanin -flat -to $EachPort -only_cells -startp] -f "is_integrated_clock_gating_cell!=true"]}
    set RegColl [remove_from_collection $RegColl $EachPort]
    if {[sizeof_collection $RegColl]<1} {
      puts "##Warning: Port $EachPortName doesn't have any cells in it's driving/receiving cone"
    } else {
      dict set portRegColl $EachPortName  $RegColl
      append_to_collection -unique RegCellColl $RegColl
      append_to_collection -unique fPortColl $EachPort
      incr numPorts
      set sXll [lindex [lindex [get_attribute $EachPort bbox] 0] 0]
      set sYll [lindex [lindex [get_attribute $EachPort bbox] 0] 1]
      set sXur [lindex [lindex [get_attribute $EachPort bbox] 1] 0]
      set sYur [lindex [lindex [get_attribute $EachPort bbox] 1] 1]
      if {$sXll!=""&&$sYll!=""} {
        if { $sXll<$llX } {set llX $sXll}
        if { $sXur>$urX } {set urX $sXur}
        if { $sYll<$llY } {set llY $sYll}
        if { $sYur>$urY } {set urY $sYur}
      }
    }
    set RegColl ""
  }

  if {[expr abs($llX-$urX)]<1.0 && [expr abs($llY-$urY)]>1.0} {
      set llX [expr $llX-$radius]
      set urX [expr $urX+$radius]
      set llY [expr $llY-$otherDir]
      set urY [expr $urY+$otherDir]
      set edgeV 1
  } elseif {[expr abs($llX-$urX)]>1.0 && [expr abs($llY-$urY)]<1.0} {
      set llX [expr $llX-$otherDir]
      set urX [expr $urX+$otherDir]
      set llY [expr $llY-$radius]
      set urY [expr $urY+$radius]
      set edgeH 1
  } elseif {[expr abs($llX-$urX)]<1.1 && [expr abs($llY-$urY)]<1.1} {
      set llX [expr $llX-$radius]
      set urX [expr $urX+$radius]
      set llY [expr $llY-$radius]
      set urY [expr $urY+$radius]
  } else {
      puts "ERROR: Edge is NOT corrcet or suitable for ports bounds"
      #exit
  }

  set nBnds 1
  set bllX $llX
  set burX $urX
  set bllY $llY
  set burY $urY

  puts "Port placement range: { $llX, $llY } { $urX, $urY }\n"

  #Create multiple bounds with square radius
  set portsBndDone ""
  set bRegCellColl ""
  if {$edgeV==1} {
      set nRadius [expr  $radius-10.0]
      if {$radius<20} { set nRadius $radius}
      set nDist [expr  abs($llY-$urY)]
      set nBnds [expr  round($nDist/$nRadius)]
      if {$otherDir > 0} { set nBnds 0 }
      if {$nDist < 10} {
          set bllY [expr $llY-((10-$nDist)/2)]
          set burY [expr $urY+((10-$nDist)/2)]
      }
      if {$nBnds==0} {
           if {$hardBnd==1} {
              create_bound -name $bndPrefix -boundary [list [list $llX $bllY] [list $urX $burY]] -type hard $RegCellColl
           } else {
              create_bound -name $bndPrefix -boundary [list [list $llX $bllY] [list $urX $burY]] -type soft $RegCellColl
           }
      }

      for {set i 1} {$i<= $nBnds} {incr i} {
          set tllY [expr $llY+(($i-1)*$nRadius)]
          set turY [expr $tllY+$nRadius]
          if {$i == $nBnds} {set turY $urY }
          set tPorts [get_ports -touching [list [list $llX $tllY] [list $urX $turY]]]
          set tPorts [remove_from_collection  -inter $fPortColl $tPorts]
          if {[sizeof $portsBndDone] > 0} {
             set tPorts [remove_from_collection $tPorts $portsBndDone]
          }
          if {[sizeof $tPorts] < 1} {continue}
          #echo "Area: $llX $tllY  $urX $turY\n"
          foreach_in_collection tPort $tPorts {
             set tPortName [get_object_name $tPort]
             #echo "Port here: $tPortName\n"
             set tRegColl [dict get $portRegColl $tPortName]
             append_to_collection -unique tRegCellColl $tRegColl
          }

          if {![info exists tRegCellColl]} {continue}
          set bllY [expr $tllY-5]
          set burY [expr $turY+5]

          if {$hardBnd==1} {
             create_bound -name ${bndPrefix}_${i} -boundary [list [list $llX $bllY] [list $urX $burY]] -type hard $tRegCellColl
          } else {
             create_bound -name ${bndPrefix}_${i} -boundary [list [list $llX $bllY] [list $urX $burY]] -type soft $tRegCellColl
          }

          append_to_collection -unique portsBndDone $tPorts
          append_to_collection -unique bRegCellColl $tRegCellColl
          if {[info exists tRegCellColl]} {unset tRegCellColl}
      }
  } elseif {$edgeH==1} {
      set nRadius [expr  $radius-10.0]
      if {$radius<20} { set nRadius $radius}
      set nDist [expr  abs($llX-$urX)]
      set nBnds [expr  round($nDist/$nRadius)]
      if {$otherDir > 0} { set nBnds 0 }
      if {$nDist < 10} {
          set bllX [expr $llX-((10-$nDist)/2)]
          set burX [expr $urX+((10-$nDist)/2)]
      }
      if {$nBnds==0} {
           if {$hardBnd==1} {
              create_bound -name $bndPrefix -boundary [list [list $bllX $llY] [list $burX $urY]] -type hard $RegCellColl
           } else {
              create_bound -name $bndPrefix -boundary [list [list $bllX $llY] [list $burX $urY]] -type soft $RegCellColl
           }
      }

      for {set i 1} {$i<= $nBnds} {incr i} {
          set tllX [expr $llX+(($i-1)*$nRadius)]
          set turX [expr $tllX+$nRadius]
          if {$i == $nBnds} {set turX $urX }
          set tPorts [get_ports -touching [list [list $tllX $llY] [list $turX $urY]]]
          set tPorts [remove_from_collection  -inter $fPortColl $tPorts]
          if {[sizeof $portsBndDone] > 0} {
             set tPorts [remove_from_collection $tPorts $portsBndDone]
          }
          if {[sizeof $tPorts] < 1} {continue}
          foreach_in_collection tPort $tPorts {
             set tPortName [get_object_name $tPort]
             set tRegColl [dict get $portRegColl $tPortName]
             append_to_collection -unique tRegCellColl $tRegColl
          }
          if {![info exists tRegCellColl]} {continue}
          set bllX [expr $tllX-5]
          set burX [expr $turX+5]

          if {$hardBnd==1} {
             create_bound -name ${bndPrefix}_${i} -boundary [list [list $bllX $llY] [list $burX $urY]] -type hard $tRegCellColl
          } else {
             create_bound -name ${bndPrefix}_${i} -boundary [list [list $bllX $llY] [list $burX $urY]] -type soft $tRegCellColl
          }

          append_to_collection -unique portsBndDone $tPorts
          append_to_collection -unique bRegCellColl $tRegCellColl
          if {[info exists tRegCellColl]} {unset tRegCellColl}
      }
  } elseif {$hardBnd==1} {
      create_bound -name $bndPrefix -boundary [list [list $llX $llY] [list $urX $urY]] -type hard $RegCellColl
  } else {
      create_bound -name $bndPrefix -boundary [list [list $llX $llY] [list $urX $urY]] -type soft $RegCellColl
  }
    
  ##set_multibit_options -exclude $RegCellColl
  set CellCnt [sizeof_collection $RegCellColl]
  set bCellCnt 0
  if {[info exists bRegCellColl]} {
    set bCellCnt [sizeof_collection $bRegCellColl]
  }
  
  if {$nBnds==0} {set nBnds 1}
  puts "\nNum of bounds $nBnds\n"
  puts "NoOfPorts: $numPorts \nNoOfCells: $CellCnt\n"
  if { $CellCnt!=$bCellCnt && $bCellCnt!=0 } {
    set mCells [remove_from_collection $RegCellColl $bRegCellColl]
    puts "WARNING: Split bound not accurate. Expected cell count $CellCnt but only bounded $bCellCnt\nTime to debug bound proc\n"
    foreach_in_collection mCell $mCells {
      puts [get_object_name $mCell]
      puts "\n"
    }
  }
}

###################################
### Helper proc in moving hier  ###
###################################
proc parse_hier {strFullName} {
    
    # Variables
    set strBaseHier ""
    set strName ""

    if { [regexp -lineanchor {^(.*)/([^/]*)$} $strFullName strMatch strBaseHier strName] } {
        # Do nothing (values set in regexp proc)
    } elseif { [regexp -lineanchor {^([^/]*)$} $strFullName strMatch strName] } {
        # Do nothing (values set in regexp proc)
    } else {
        error "Could not parse '$strFullName'"
    }

    return [list $strBaseHier $strName]
}

proc combine_hier {strBaseHier strName} {
    if { $strBaseHier == "" } {
        return $strName
    } else {
        return "$strBaseHier/$strName"
    }
}

##############################################
### Fixed placement for boundary flops #######
### Umesh (09/12/2020)           #############
##############################################

proc fixReg2Port {PortColl xOffSet yOffSet } {
 set RegColl ""
 set RegFixedCellColl ""
 set CellCnt 0
 set numPorts 0
 append_to_collection -unique mPortColl [get_ports $PortColl]
 foreach_in_collection EachPort $mPortColl {
    set EachPortName [get_object_name $EachPort]
    echo "$EachPortName"
    set Dir [get_att $EachPort direction]
    if {$Dir=="in"}  {set RegColl [get_cells [all_fanout -flat -from $EachPort -only_cells -endpoints_only] -f "is_integrated_clock_gating_cell!=true"]}
    if {$Dir=="out"} {set RegColl [get_cells [all_fanin -flat -to $EachPort -only_cells -startp] -f "is_integrated_clock_gating_cell!=true"]}
    remove_from_collection $RegColl $EachPort
    if {[sizeof_collection $RegColl]<1} {
      puts "##Warning: Port $EachPortName doesn't have any cells in it's driving/receiving cone"
    } elseif {[sizeof [get_cells $RegColl -f "is_mapped==true"]] > 0} {
      set mCells [get_cells $RegColl -f "is_mapped==true"]
      append_to_collection -unique RegFixedCellColl $mCells
      incr numPorts
      set sX [lindex [lindex [get_attribute $EachPort bbox] 0] 0]
      set sY [lindex [lindex [get_attribute $EachPort bbox] 0] 1]
      set pX [expr $sX+$xOffSet]
      set pY [expr $sY+$yOffSet]
      set_attribute  $mCells is_fixed false
      foreach_in_collection mCell $mCells {
        set_cell_location -coord [list $pX $pY] -orient N -fixed $mCell
      }
    } else {
      puts "Warning: The driving/receiving cell is NOT mapped thus not placed close to the port"
    }
    set RegColl ""
  }

  ##remove_attribute  $RegFixedCellColl  dont_touch
  set CellCnt [sizeof_collection $RegFixedCellColl]
  puts "NoOfPorts: $numPorts \nNoOfCells: $CellCnt\n"
  return $RegFixedCellColl
}

##############################################
### Reports for timing status and debug ###### 
### Umesh 9/11/2023                     ######
##############################################
proc rptRegSlackData { TARGET_NAME passnum } {
  if {$passnum!=""} {
    set regSlackFile "regSlack.pass_${passnum}.rpt"
    set dSlackFile "dSlack.pass_${passnum}.csv"    
  } else {
    set regSlackFile "regSlack.rpt"
    set dSlackFile "dSlack.csv"    
  }
  set allRegs [all_registers]
  echo "Register Name, Pin:Slack, (X Y)" > rpts/$TARGET_NAME/$regSlackFile
  foreach_in_collection mReg $allRegs {
    set mPins [get_pins -of $mReg -f "name!=CK&&name!=CLK&&name!~S*&&name!~V*&&name!=TE*"]
    set regName [get_object_name $mReg]
    set WrStr $regName
    foreach_in_collection mPin $mPins {
      set pinName [get_attribute $mPin name]
      set slack [get_attribute $mPin max_slack]
      set WrStr "$WrStr,$pinName:$slack"
    }
    set mX [lindex [lindex [get_attribute $mReg bbox] 0] 0]
    set mY [lindex [lindex [get_attribute $mReg bbox] 0] 1]
    set WrStr "$WrStr, ($mX $mY)"
    redirect -append rpts/$TARGET_NAME/$regSlackFile {puts $WrStr}
  }

  ##DSlack graph
  set RString "Slack, #of Paths, ,"
  set tDistList [list 0 -5 -10 -15 -20 -25 -30 -35 -40 -50 -60 -70 -80 -90 -100 -120 ]

  foreach tSlack  [lsort -real $tDistList] {
     set tPath [get_timing_paths -max_paths 100000 -slack_lesser_than $tSlack -groups [get_path_groups -quiet {*clock_gating* *R2R* *reg2reg* *r2r*}]]
     set tPathCnt [sizeof_collection $tPath]
     set RString  "${RString}\n${tSlack}, $tPathCnt, ,"
  }
  redirect -append rpts/$TARGET_NAME/$dSlackFile {puts $RString}

}


#Ports - External delay and Slack 
proc rptPortSlackData { TARGET_NAME passnum } {
     if {$passnum!=""} {
         set portSlackFile "portSlack.pass_${passnum}.rpt"
    } else {
         set portSlackFile "portSlack.rpt"
    }
    echo "Port_Name,Port_Direction,External_Delay,Slack" > rpts/$TARGET_NAME/$portSlackFile 

    set ports [get_ports * -filter defined(net)&&port_type!="power"&&port_type!="ground"]
    set ports_list [get_object_name $ports]
    
    # redirect -append rpts/FxSynthesizeputs $fp "PORT \t \t \t \t \t \t Direction \t Input External Delay \t \t Slack"
    foreach port $ports_list {
        set direc [get_attribute $port direction]
        if {$direc == "in"} {
            redirect /dev/null { set delay [get_attribute [get_timing_paths -from $port] input_delay] }
            set slack [get_attribute -quiet $port max_slack]
            redirect -append rpts/$TARGET_NAME/$portSlackFile {puts "$port,INPUT,$delay,$slack"}
        }
        if {$direc == "out"} {
            redirect /dev/null { set external_delay [get_attribute [get_timing_paths -to $port] check_value] }
            set slack [get_attribute -quiet $port max_slack]
            redirect -append rpts/$TARGET_NAME/$portSlackFile {puts "$port,OUTPUT,$external_delay,$slack"}
        }
    }
    unset ports_list 
    sh gzip -f rpts/$TARGET_NAME/$portSlackFile
}

### Area calc by shrkumar: Calculate area for seq cells, hard macros, latch arrays and clock gaters
proc area_calc {} {

    set lat_arr [filter_collection [filter_collection [get_cells  [all_registers -level] -filter "name=~*Array_reg*"] -regexp {is_hard_macro == false}]  -regexp {is_integrated_clock_gating_cell == false}] 
    set lib_cells [get_lib_cells -of $lat_arr ]
    
    
    set area_larr 0
    
    foreach_in_collection itr $lib_cells {
    
        set lib_cell_name [get_attribute $itr -name "full_name"]
        #set matched_lib_cells [sizeof [filter_collection $lat_arr "lib_cell.full_name=~$lib_cell_name"]]
        set matched_lib_cells [sizeof [get_cells -of_obj $itr]]
        #puts $lib_cell_name
        #puts $matched_lib_cells
        
        set area_larr [expr $area_larr + [expr $matched_lib_cells*[get_attribute $itr -name "area"]]]
    }
    #puts "Area of Latch array	$area_larr	"
    
    ##################################
    set registers [filter_collection [filter_collection [all_registers -edge_triggered] -regexp {is_hard_macro == false}] -regexp {is_integrated_clock_gating_cell == false}]
    set lib_cells [get_lib_cells -of $registers]
    
    set area_reg 0
    
    foreach_in_collection itr $lib_cells {
    
        set lib_cell_name [get_attribute $itr -name "full_name"]
        #set matched_lib_cells [sizeof [filter_collection $registers "lib_cell.full_name=~$lib_cell_name"]]
        set matched_lib_cells [sizeof [get_cells -of_obj $itr]]
        #puts $lib_cell_name
        #puts $matched_lib_cells
        
        set area_reg [expr $area_reg + [expr $matched_lib_cells*[get_attribute $itr -name "area"]]]
    }
    #puts "Area of Edge triggered sequential cells	$area_reg "
    ##################################
    set clk_gaters [filter_collection [filter_collection [all_registers] -regexp {is_hard_macro == false}] -regexp {is_integrated_clock_gating_cell == true}] 
    
    set lib_cells [get_lib_cells -of $clk_gaters]
    
    set area_clk_gater 0
    
    foreach_in_collection itr $lib_cells {
    
        set lib_cell_name [get_attribute $itr -name "full_name"]
        #set matched_lib_cells [sizeof [filter_collection $clk_gaters "lib_cell.full_name=~$lib_cell_name"]]
        set matched_lib_cells [sizeof [get_cells -of_obj $itr]]
        #puts $lib_cell_name
        #puts $matched_lib_cells
        
        set area_clk_gater [expr $area_clk_gater + [expr $matched_lib_cells*[get_attribute $itr -name "area"]]]
    }
    #puts "Area of Clock gaters	$area_clk_gater"
    
    #####################################
    
    set hard_macros [filter_collection [get_cells -quiet * -hier] "is_hard_macro == true"]
    set area_hard_macro 0
    #CN: Skip when no macros are present
    if [sizeof_col $hard_macros] {
       set lib_cells [get_lib_cells -of $hard_macros]
       foreach_in_collection itr $lib_cells {
           set lib_cell_name [get_attribute $itr -name "full_name"]
           #set matched_lib_cells [sizeof [filter_collection $hard_macros "lib_cell.full_name=~$lib_cell_name"]]
           set matched_lib_cells [sizeof [get_cells -of_obj $itr]]
           #puts $lib_cell_name
           #puts $matched_lib_cells
           set area_hard_macro [expr $area_hard_macro + [expr $matched_lib_cells*[get_attribute $itr -name "area"]]]
       }
       #puts "Area of hard macro 	$area_hard_macro"
    } 
    
    ####################################
    set combo_cells [filter_collection [get_cells * -hier] "is_combinational == true"]
    
    set lib_cells [get_lib_cells -of $combo_cells]
    
    set area_combo 0
    
    foreach_in_collection itr $lib_cells {
    
        set lib_cell_name [get_attribute $itr -name "full_name"]
        #set matched_lib_cells [sizeof [filter_collection $combo_cells "lib_cell.full_name=~$lib_cell_name"]]
        set matched_lib_cells [sizeof [get_cells -of_obj $itr]]
        #puts $lib_cell_name
        #puts $matched_lib_cells
    
        set area_combo [expr $area_combo + [expr $matched_lib_cells*[get_attribute $itr -name "area"]]]
    }
    #set area_combo 0
    #foreach_in_collection itr [filter_collection [get_cells * -hier] "is_combinational == true"] {set area_combo [expr $area_combo + [get_attribute $itr area]]}
    #puts "Area of combinational logic	$area_combo"
    
    
    ##################################
    set tot 0
    eval report_area > tmp.txt
    set file1 [open "tmp.txt" r]
    set lines [split [read $file1] "\n"]
    foreach line $lines { 
        regexp {^Total cell area:\s+(\d+)} $line a tot
    }
    
    set per_larr [expr {(double($area_larr)/$tot)*100}]
    puts "Area of Latch array	$area_larr	$per_larr%"
    
    set per_reg [expr {(double($area_reg)/$tot)*100}]
    puts "Area of Edge triggered sequential cells	$area_reg 	$per_reg%"
    
    set per_clk_gater [expr {(double($area_clk_gater)/$tot)*100}]
    puts "Area of Clock gaters	$area_clk_gater 	$per_clk_gater%"
    
    set per_hard_macro [expr {(double($area_hard_macro)/$tot)*100}]
    puts "Area of hard macro 	$area_hard_macro 	$per_hard_macro%"
    
    set per_combo [expr {(double($area_combo)/$tot)*100}]
    puts "Area of combinational logic	$area_combo 	$per_combo%"

}


proc df_umc_feint_report_timing { TARGET_NAME {passnum ""}} {
  # Print Vt usage information
  set strRpt ""
  if {$passnum != ""} { set strRpt ".pass_${passnum}" }
  update_timing -full
  redirect -tee -file rpts/$TARGET_NAME/multi_vt${strRpt}.rpt { report_threshold_voltage_group }
   
  # Print gating levels
  redirect -tee -file rpts/$TARGET_NAME/clock_gating${strRpt}.rpt { df_feint_count_gater_levels }

  redirect -tee rpts/$TARGET_NAME/${TARGET_NAME}${strRpt}.proc_qor.rpt {proc_qor}
   
  redirect rpts/$TARGET_NAME/report_timing${strRpt}.rpt { \
#CN "-sort_by slack" algorithm is missing some paths; it become obsolete and replaced by "-report_by ..."
#CN                     [eval report_timing -include_hierarchical_pins -net -nosp -trans -cap -derate -slack_lesser_than 0 -max_paths 100000 -sort_by slack -path_type full_clock_expanded -attributes -significant_digits 3 -inp -physical]
                        [eval report_timing -include_hierarchical_pins -net -nosp -trans -cap -derate -slack_lesser_than 0 -max_paths 100000 \
                        -report_by group -path_type full_clock_expanded -attributes -significant_digits 3 -inp -physical]
  }

  echo "Debug: 0" 

  # Summarize Timing
  unset -nocomplain plPath
  if [file exists ./tune/FxSynthesize/summarize_timing_report_all_groups.pl] {     
  set plPath ./tune/FxSynthesize
  echo "Debug: 01" 
  } elseif [file exists /proj/unb_snap_4/fl/scripts/perl/summarize_timing_report_all_groups.pl] { 
  set plPath /proj/unb_snap_4/fl/scripts/perl 
  echo "Debug: 02" 
  }
  if [info exists plPath] {
     sh perl $plPath/summarize_timing_report_all_groups.pl \
                             --in rpts/$TARGET_NAME/report_timing${strRpt}.rpt \
                             --period [amd_getvarsave DF_FEINT_CLOCK_PERIOD 1]
     if [file exists rpts/$TARGET_NAME/report_timing${strRpt}.rpt.sum.sort_slack.startpts] {
        sh gzip -f rpts/$TARGET_NAME/report_timing${strRpt}.rpt.sum.sort_slack.startpts }
     if [file exists rpts/$TARGET_NAME/report_timing${strRpt}.rpt.sum.sort_slack.endpts] {
        sh gzip -f rpts/$TARGET_NAME/report_timing${strRpt}.rpt.sum.sort_slack.endpts }
     echo "Debug: 03" 
  }

  echo "Debug: 1" 

  report_transformed_registers -summary > rpts/$TARGET_NAME/report_transformed_registers_summary${strRpt}.rpt
  report_transformed_registers -constants -unloaded > rpts/$TARGET_NAME/report_transformed_registers_constants_unloaded${strRpt}.rpt
  report_transformed_registers -replicated -merged > rpts/$TARGET_NAME/report_transformed_registers_replicated_merged${strRpt}.rpt
  sh gzip -f rpts/$TARGET_NAME/report_transformed_registers*${strRpt}.rpt
  
  echo "Debug: 2" 

  rptRegSlackData $TARGET_NAME $passnum
  rptPortSlackData $TARGET_NAME $passnum

  redirect -tee -append rpts/$TARGET_NAME/${TARGET_NAME}${strRpt}.proc_qor.rpt {
     df_feint_rptMBB
     puts "\n"
     global P
     if [regexp -nocase {N3} $P(TECHNO_NAME)] { df_feint_rptUtilizationN3 ; puts "\n"}
     set asyncPins [get_pins -quiet -f is_async_pin -of [get_cells -quiet -phys -filter is_sequential&&!is_integrated_clock_gating_cell]]
     if [sizeof_col $asyncPins] {
        append_to_col -u asrFFs [sort_col [get_cells -of $asyncPins] full_name]
        puts "Asynchronous S/R flip-flops([sizeof_col $asrFFs]):"
        foreach_in_col c $asrFFs { puts "[get_att $c full_name]([get_att $c ref_name])" }
     } else { puts "No asynchronous S/R flip-flops." }
  }

  sh gzip -f rpts/$TARGET_NAME/multi_vt${strRpt}.rpt
  sh gzip -f rpts/$TARGET_NAME/clock_gating${strRpt}.rpt
  sh gzip -f rpts/$TARGET_NAME/${TARGET_NAME}*${strRpt}.proc_qor.rpt
  sh gzip -f rpts/$TARGET_NAME/report_timing${strRpt}.rpt

  report_power -hierarchy -leaf -net_power -cell_power > rpts/$TARGET_NAME/report_power${strRpt}.rpt
  sh gzip -f rpts/$TARGET_NAME/report_power${strRpt}.rpt
}


###########
#Catalin.Nechita@amd.com
### Report multibit banking info - used in df_feint_report_timing
proc df_feint_rptMBB { } {
  # Reporting actual no. of bits:
  # FFs:
  set ffBitsNo  0 ; set mbffBitsNo  0 ; set mb8ff 0  ; set mb6ff 0  ; set mb4ff 0  ; set mb3ff 0 ; set mb2ff 0
  set exclFFmbb [sizeof_col [get_cells -hier -quiet -filter is_sequential&&!is_integrated_clock_gating_cell&&!is_positive_level_sensitive&&!is_negative_level_sensitive&&exclude_multibit=="true"]]
  append dupK *
  append dupK [string trim [get_app_option -name compile.seqmap.register_replication_naming_style] "%s|%d"]
  append dupK *
  set dupFFs [sizeof_col [get_cells -hier -quiet -filter is_sequential&&!is_integrated_clock_gating_cell&&!is_positive_level_sensitive&&!is_negative_level_sensitive&&full_name=~$dupK]]
  foreach_in_col c [get_cells -hier -filter is_sequential&&!is_integrated_clock_gating_cell&&!is_positive_level_sensitive&&!is_negative_level_sensitive] {
     if { [get_att -quiet $c multibit_width] != "" } {
        set mb [get_att -quiet $c multibit_width]
        if { $mb==0 } {
           # Some N3/N5(4) lib_cells have wrong multibit_with attribute(0) (e.g. MB4SRLSDFQNMCA4444D1AMDBWP143M572)
           if [regexp {MB4SRLSDFQ} [get_att $c ref_name]] {    incr ffBitsNo 4 ; incr mbffBitsNo 4 ; incr mb4ff 4
           } else {                                            incr ffBitsNo }
        } else {                                               incr ffBitsNo $mb ; incr mbffBitsNo $mb
                                                               if { $mb==8 } {       incr mb8ff $mb
                                                               } elseif { $mb==6 } { incr mb6ff $mb
                                                               } elseif { $mb==4 } { incr mb4ff $mb
                                                               } elseif { $mb==3 } { incr mb3ff $mb
                                                               } elseif { $mb==2 } { incr mb2ff $mb }
        }
     } else {                                                  incr ffBitsNo }
  }
  # Latches:
  set latBitsNo 0 ; set mblatBitsNo 0 ; set mb8lat 0 ; set mb6lat 0 ; set mb4lat 0 ; set mb2lat 0
  set exclLATmbb [sizeof_col [get_cells -hier -quiet -filter is_sequential&&!is_integrated_clock_gating_cell&&(is_positive_level_sensitive||is_negative_level_sensitive)&&exclude_multibit=="true"]]
  foreach_in_col c [get_cells -hier -filter is_sequential&&!is_integrated_clock_gating_cell&&(is_positive_level_sensitive||is_negative_level_sensitive)] {
     if { [get_att -quiet $c multibit_width] != "" } {
        set mb [get_att -quiet $c multibit_width]
        if { $mb==0 } {
           # Some N7(6) lib_cells have wrong multibit_with attribute(0)
           if [regexp {LDPQM8AOI22} [get_att $c ref_name]] {   incr latBitsNo 8 ; incr mblatBitsNo 8 ; incr mb8lat 8
           # Some N3/N5(4) lib_cells have wrong multibit_with attribute(0)
           } elseif [regexp {MB8LHQ} [get_att $c ref_name]] {  incr latBitsNo 8 ; incr mblatBitsNo 8 ; incr mb8lat 8
           } else {                                            incr latBitsNo }
        } else {                                               incr latBitsNo $mb ; incr mblatBitsNo $mb
                                                               if { $mb==8 } {       incr mb8lat $mb
                                                               } elseif { $mb==6 } { incr mb6lat $mb
                                                               } elseif { $mb==4 } { incr mb4lat $mb
                                                               } elseif { $mb==2 } { incr mb2lat $mb }
        }
     } else {                                                  incr latBitsNo }
  }
  # Report FFs/LATs' CK-pin capacitance
  set allckP [get_pins -phys -filter is_clock_pin -of [get_cells -phys -filter is_sequential&&!is_integrated_clock_gating_cell]] ; list
  set ckCap 0
  foreach_in_col p $allckP { set ckCap [expr $ckCap+[get_att $p late_rise_input_cap]] }

  puts "\n\nBits no in FFs:  $ffBitsNo"
  puts "Bits no in latches: $latBitsNo"
  puts "Bits no in MBFF only:  $mbffBitsNo - MB8FF:$mb8ff  MB6FF:$mb6ff  MB4FF:$mb4ff  MB3FF:$mb3ff  MB2FF:$mb2ff"
  puts "Bits no in MBLAT only: $mblatBitsNo - MB8LAT:$mb8lat  MB6LAT:$mb6lat  MB4LAT:$mb4lat  MB2LAT:$mb2lat"
  puts "Bits no in replicated FFs:      $dupFFs" 
  puts "Bits no w/ excludedMBB in FFs:  $exclFFmbb" 
  puts "Bits no w/ excludedMBB in LATs: $exclLATmbb"
  puts "MB banking: [format %.2f [expr ($mbffBitsNo+$mblatBitsNo)*100.000/($ffBitsNo+$latBitsNo)]]%"
  puts "CK-pins cap(except ICG's CK-pins): $ckCap"
  ### Area calc by shrkumar: Calculate area for seq cells, hard macros, latch arrays and clock gaters
  area_calc
  puts "Floating output of MbSeq: [sizeof_col [get_pins -filter direction=="out"&&(net.number_of_flat_loads==0||!defined(net)) -of_objects [get_cells -hier -filter multibit_width>1||ref_name=~"*LDPQM8AOI22*"||ref_name=~"*MB8LHQ*"||ref_name=~"*MB4SRLSDFQ*"]]]"
  set wrongMBattCells [get_cells -quiet -hier -filter is_sequential&&!is_integrated_clock_gating_cell&&(!defined(multibit_width)||multibit_width<2)&&ref_name=~"*MB*"]
  #N5 filter FFs:
  set wrongMBattCells [get_cells -quiet $wrongMBattCells -filter ref_name!~"*MB4SRLSDFQ*"&&ref_name!~"*MB4AOI22*"&&ref_name!~"*MB4ND2*"]
  #N5 filter latches:
  set wrongMBattCells [get_cells -quiet $wrongMBattCells -filter ref_name!~"*MB8LHQ2AOI22*"&&ref_name!~"*MB8LHQAOI22*"]

  if [sizeof_col $wrongMBattCells] {
     puts "Posible wrong multibit_width for some cells(they are counted as 1 bit):"
     foreach_in_col c [get_cells $wrongMBattCells] { puts "[get_att $c name] - [get_att $c ref_name] multibit_width:[get_att $c multibit_width]" }
  }
}


###Forward Tracer ##########
############################
proc forwardTrace {db tClkNet tDepth tDrName} {
 upvar $db mSinkDb
 set tDrCell [get_cells -quiet $tDrName]
 if {[sizeof $tDrCell]<1} {
   set cDepth [expr $tDepth+1]
 } else {
   set tDrLibCellName [get_object_name [get_lib_cells -of_objects [get_cells $tDrName]]]
   if {[regexp {.*INV.*} $tDrLibCellName]||[regexp {.*NR2.*} $tDrLibCellName]||[regexp {.*ND2.*} $tDrLibCellName]} {
      set cDepth [expr $tDepth+1]
   } else {
     set cDepth [expr $tDepth+2]
   }
 }
 set tLoads [get_pins -quiet -of_objects $tClkNet -leaf -f "direction==in&&name!=CLK1&&name!=CLK2"]
 if {[sizeof $tLoads] < 1} {
    dict set mSinkDb $tDrName mdepth -1
    return -1
  }
  set tClkGaterPins [get_pins -quiet $tLoads -f @is_clock_gating_clock==true]
  set tClkGaterCells [get_cells -quiet -of_objects $tClkGaterPins -f @full_name!~"*tile_dfx*"]
  set tCells [get_cells -quiet -of_objects $tLoads -f @full_name!~"*tile_dfx*"&&@ref_name!~"*MUX2*"]
  set allSeq [all_registers ]
  #set tCells [get_cells -of_objects $tLoads -f @full_name!~"*tile_dfx*"&&@is_hard_macro!=true]
  set tSeqSinks [remove_from_collection -inter $allSeq [remove_from_collection [get_cells -quiet $tCells -f @is_sequential==true] $tClkGaterCells]]
  foreach_in_collection mSeqSink $tSeqSinks {
    set mName [get_object_name $mSeqSink]
    #puts $mName
    dict set mSinkDb $mName dr $tDrName
    dict set mSinkDb $mName depth $cDepth
    dict set mSinkDb $mName seq 1
    dict set mSinkDb $mName mdepth $cDepth
  }

  set tNonSeqSinks [remove_from_collection $tCells $tSeqSinks]
  if {[sizeof $tNonSeqSinks] < 1} {
    dict set mSinkDb $tDrName mdepth $cDepth
    return $cDepth
  }

  set maxdepth -1
  foreach_in_collection mNonSeqSink $tNonSeqSinks {
    set mClkNet [get_nets -quiet -of_objects [get_pins -quiet -of_objects $mNonSeqSink -f "(name==X||name==Z||name==Q||name==ZN)&&(direction==out)"]]
    set mDrName [get_object_name $mNonSeqSink]
    #puts $mDrName
    dict set mSinkDb $mDrName dr $tDrName
    dict set mSinkDb $mDrName depth $cDepth
    dict set mSinkDb $mDrName seq 0
    if {[sizeof $mClkNet]>0} {
      set nDepth [forwardTrace mSinkDb $mClkNet $cDepth $mDrName]
      dict set mSinkDb $mDrName mdepth $nDepth
      if { $maxdepth < $nDepth } {
        set maxdepth $nDepth
      }
    } else {
      dict set mSinkDb $mDrName mdepth -1
    }
  }

  dict set mSinkDb $tDrName mdepth $maxdepth
  return $maxdepth
}

proc fixClkPath4I2CG { aClkNets fixSinkCnt} {
   global P
   if [regexp -nocase {N3} $P(TECHNO_NAME)] {
      set CkAN2LibCell [get_lib_cells */CKAN2D4AMDBWP143M169H3P48CPDLVT]
      set ICGLibCell [get_lib_cells */CKOR2LNQAN2D4AMDBWP143M169H3P48CPDLVT]
      #set ClkInvLibCell [get_lib_cells */CKINVD2P5AMDBWP143M169H3P48CPDLVT]
      set ClkInvLibCell [get_lib_cells */CKND4BWP143M169H3P48CPDLVT]
      set Tie1Cell [get_lib_cells */TIEHNTGD2BWP143M169H3P48CPDLVT]
      set Tie0Cell [get_lib_cells */TIELNTGD2BWP143M169H3P48CPDLVT]
   }
#  if [regexp -nocase {N5} $P(TECHNO_NAME)] {
#     set CkAN2LibCell [get_lib_cells */CKAN2D4AMDBWP143M169H3P48CPDLVT]
#     set ICGLibCell [get_lib_cells */CKOR2LNQAN2D4AMDBWP143M169H3P48CPDLVT]
#     #set ClkInvLibCell [get_lib_cells */CKINVD2P5AMDBWP143M169H3P48CPDLVT]
#     set ClkInvLibCell [get_lib_cells */CKND4BWP143M169H3P48CPDLVT]
#     set Tie1Cell [get_lib_cells */TIEHNTGD2BWP143M169H3P48CPDLVT]
#     set Tie0Cell [get_lib_cells */TIELNTGD2BWP143M169H3P48CPDLVT]
#  }
   if [regexp -nocase {N6} $P(TECHNO_NAME)] {
      set CkAN2LibCell [get_lib_cells */HDN6BLVT08_AN2_CK_4]
      set ICGLibCell [get_lib_cells */HDN6BLVT08_CKGTPLT_V7Y2_4]
      set ClkInvLibCell [get_lib_cells */HDN6BLVT08_INV_CK_4]
      set Tie1Cell [get_lib_cells ts06ncpllogl08udl057f/HDN6BLVT08_TIE1_1]
      set Tie0Cell [get_lib_cells ts06ncpllogl08udl057f/HDN6BLVT08_TIE0_1]
   }

  set allEdgeLevelSeq [all_registers ]

  #set aClkNets [get_nets -quiet {Cpl_FCLK UCLK DFICLK CLK}]
  echo "INFO: Clock Sink Report" > rpts/FxSynthesize/clockDepth.b4SinkFix.rpt
  echo "INFO: Clock Sink Report" > rpts/FxSynthesize/clockDepth.afterSinkFix.rpt
  foreach_in_collection ClkNet $aClkNets {
    set allClkLoads [get_pins -quiet -leaf -of_objects [get_nets $ClkNet -segments] -filter "pin_direction==in&&is_hierarchical!=true"]
    set ClkName [get_object_name $ClkNet]
    if {[sizeof $allClkLoads] < 1} {
      echo "INFO: No clock loads for $ClkName" >> rpts/FxSynthesize/clockDepth.b4SinkFix.rpt
      continue
    }

    if {[info exists SinkDb]} {unset SinkDb}
    if {[info exists SinkCnt]} {unset SinkCnt}
    dict set SinkDb $ClkName dr 0
    dict set SinkDb $ClkName depth 0
    dict set SinkDb $ClkName seq 0
    #dict set SinkDb $ClkName mdepth 0
    set MaxClkDepth [forwardTrace SinkDb $ClkNet 0 $ClkName]
    echo "INFO: $ClkName, Max Clock Sink Depth b4 fix is $MaxClkDepth\nMaxDepth  CurrentDepth  Sink" >> rpts/FxSynthesize/clockDepth.b4SinkFix.rpt
    if {$MaxClkDepth > 7} {
      echo "ERROR: $ClkName, Max Clock Sink Depth is $MaxClkDepth and that will break I2CG. Max depth should be 6 or less. Buffer and clockgater is counted as depth of 2." >> rpts/FxSynthesize/clockDepth.b4SinkFix.rpt
    }
    redirect -append rpts/FxSynthesize/clockDepth.b4SinkFix.rpt {
      foreach tkey [dict keys $SinkDb] {
        set tdepth [dict get $SinkDb $tkey depth]
        set mdepth [dict get $SinkDb $tkey mdepth]
        if {[info exists SinkCnt($tdepth)]} {
          set SinkCnt($tdepth) [incr SinkCnt($tdepth)]
        } else {
          set SinkCnt($tdepth) 1
        }
        puts "$mdepth  $tdepth  $tkey"
      }
    }


    #Check for S1 loads
    if {[info exists d1Sinks]} {unset d1Sinks}
    if {[info exists d2Sinks]} {unset d2Sinks}
    if {[info exists d3Sinks]} {unset d3Sinks}
    if {[info exists d4Sinks]} {unset d4Sinks}
    if {[info exists d5Sinks]} {unset d5Sinks}
    set fS1Loads 0


    foreach tkey [dict keys $SinkDb] {
      set tdepth [dict get $SinkDb $tkey depth]
      set mdepth [dict get $SinkDb $tkey mdepth]
      if {$mdepth==1 && $tdepth==1} {
        append_to_collection d1Sinks [get_cells $tkey]
      } 
      if {$mdepth==2 && $tdepth==1} {
        append_to_collection d2Sinks [get_cells $tkey]
      }
      if {$mdepth==3 && $tdepth==1} {
        append_to_collection d3Sinks [get_cells $tkey]
      }
      if {$mdepth==4 && $tdepth==1} {
        append_to_collection d4Sinks [get_cells $tkey]
      }
      if {$mdepth==5 && $tdepth==1} {
        append_to_collection d5Sinks [get_cells $tkey]
      }
      if {$mdepth>0 && $tdepth==1} {
        incr fS1Loads 
      }
    }

    echo "INFO: $ClkName, Total S1 loads: $fS1Loads" >> rpts/FxSynthesize/clockDepth.b4SinkFix.rpt

    #if {$fixSinkCnt==0} {
    #  return
    #}

    ####Netlist modification
    if {$fixSinkCnt==1} {
       #Fix S1 loads
       if {[info exists d1Sinks] && [sizeof $d1Sinks] > 1} {
         set d1SinkPins [remove_from_collection -intersect $allClkLoads [get_pins -quiet -of_objects $d1Sinks -f @direction==in]]
         if {[sizeof [get_cells -quiet UmeshICGDummyD1$ClkName]] < 1} {
           create_cell UmeshLogic1D1$ClkName $Tie1Cell
           create_cell UmeshLogic0D1$ClkName $Tie0Cell
           create_cell UmeshICGDummyD1$ClkName $ICGLibCell
           if [regexp -nocase {N3} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD1$ClkName/CP }
           #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD1$ClkName/CP }
           if [regexp -nocase {N6} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD1$ClkName/CLK }
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic1D1$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD1$ClkName/E]        
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic0D1$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD1$ClkName/TE]
         }
         if [regexp -nocase {N3} $P(TECHNO_NAME)] { set d1Driver [get_pins UmeshICGDummyD1$ClkName/Q] }
         #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { set d1Driver [get_pins UmeshICGDummyD1$ClkName/Q] }
         if [regexp -nocase {N6} $P(TECHNO_NAME)] { set d1Driver [get_pins UmeshICGDummyD1$ClkName/Z] }
         foreach_in_collection mPin $d1SinkPins {
           disconnect_net [get_nets -of_objects $mPin] $mPin
         }
         connect_pin -driver $d1Driver $d1SinkPins -port_name fixClockD1
       }
  
       #Fix S2 loads
       if {[info exists d2Sinks] && [sizeof $d2Sinks] > 1} {
         set d2SinkPins [remove_from_collection -intersect $allClkLoads [get_pins -of_objects $d2Sinks -f @direction==in]]
         if {[sizeof [get_cells -quiet UmeshICGDummyD2$ClkName]] < 1} {
           create_cell UmeshLogic1D2$ClkName $Tie1Cell
           create_cell UmeshLogic0D2$ClkName $Tie0Cell
           create_cell UmeshICGDummyD2$ClkName $ICGLibCell
           if [regexp -nocase {N3} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD2$ClkName/CP }
           #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD2$ClkName/CP }
           if [regexp -nocase {N6} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD2$ClkName/CLK }
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic1D2$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD2$ClkName/E]        
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic0D2$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD2$ClkName/TE]
         }
         if [regexp -nocase {N3} $P(TECHNO_NAME)] { set d2Driver [get_pins UmeshICGDummyD2$ClkName/Q] }
         #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { set d2Driver [get_pins UmeshICGDummyD2$ClkName/Q] }
         if [regexp -nocase {N6} $P(TECHNO_NAME)] { set d2Driver [get_pins UmeshICGDummyD2$ClkName/Z] }
         foreach_in_collection mPin $d2SinkPins {
           disconnect_net [get_nets -of_objects $mPin] $mPin
         }
         connect_pin -driver $d2Driver $d2SinkPins -port_name fixClockD2      
       }

       #Fix S3 loads
       if {[info exists d3Sinks] && [sizeof $d3Sinks] > 1} {
         set d3SinkPins [remove_from_collection -intersect $allClkLoads [get_pins -of_objects $d3Sinks -f @direction==in]]
         if {[sizeof [get_cells -quiet UmeshICGDummyD3$ClkName]] < 1} {
           create_cell UmeshLogic1D3$ClkName $Tie1Cell
           create_cell UmeshLogic0D3$ClkName $Tie0Cell
           create_cell UmeshICGDummyD3$ClkName $ICGLibCell
           if [regexp -nocase {N3} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD3$ClkName/CP }
           #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD3$ClkName/CP }
           if [regexp -nocase {N6} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD3$ClkName/CLK }
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic1D3$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD3$ClkName/E]        
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic0D3$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD3$ClkName/TE]
         }
         if [regexp -nocase {N3} $P(TECHNO_NAME)] { set d3Driver [get_pins UmeshICGDummyD3$ClkName/Q] }
         #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { set d3Driver [get_pins UmeshICGDummyD3$ClkName/Q] }
         if [regexp -nocase {N6} $P(TECHNO_NAME)] { set d3Driver [get_pins UmeshICGDummyD3$ClkName/Z] }
         foreach_in_collection mPin $d3SinkPins {
           disconnect_net [get_nets -of_objects $mPin] $mPin
         }
         connect_pin -driver $d3Driver $d3SinkPins -port_name fixClockD3      
       }

       #Fix S4 loads
       if {[info exists d4Sinks] && [sizeof $d4Sinks] > 1} {
         set d4SinkPins [remove_from_collection -intersect $allClkLoads [get_pins -of_objects $d4Sinks -f @direction==in]]
         if {[sizeof [get_cells -quiet UmeshICGDummyD4$ClkName]] < 1} {
           create_cell UmeshLogic1D4$ClkName $Tie1Cell
           create_cell UmeshLogic0D4$ClkName $Tie0Cell
           create_cell UmeshICGDummyD4$ClkName $ICGLibCell
           if [regexp -nocase {N3} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD4$ClkName/CP }
           #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD4$ClkName/CP }
           if [regexp -nocase {N6} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD4$ClkName/CLK }
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic1D4$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD4$ClkName/E]        
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic0D4$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD4$ClkName/TE]
         }
         if [regexp -nocase {N3} $P(TECHNO_NAME)] { set d4Driver [get_pins UmeshICGDummyD4$ClkName/Q] }
         #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { set d4Driver [get_pins UmeshICGDummyD4$ClkName/Q] }
         if [regexp -nocase {N6} $P(TECHNO_NAME)] { set d4Driver [get_pins UmeshICGDummyD4$ClkName/Z] }
         foreach_in_collection mPin $d4SinkPins {
           disconnect_net [get_nets -of_objects $mPin] $mPin
         }
         connect_pin -driver $d4Driver $d4SinkPins -port_name fixClockD4      
       }

       #Fix S5 loads
       if {[info exists d5Sinks] && [sizeof $d5Sinks] > 1} {
         set d5SinkPins [remove_from_collection -intersect $allClkLoads [get_pins -quiet -of_objects $d5Sinks -f @direction==in]]
         if {[sizeof [get_cells -quiet UmeshICGDummyD5$ClkName]] < 1} {
           create_cell UmeshLogic1D5$ClkName $Tie1Cell
           create_cell UmeshLogic0D5$ClkName $Tie0Cell
           create_cell UmeshICGDummyD5$ClkName $ICGLibCell
           if [regexp -nocase {N3} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD5$ClkName/CP }
           #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD5$ClkName/CP }
           if [regexp -nocase {N6} $P(TECHNO_NAME)] { connect_net $ClkNet UmeshICGDummyD5$ClkName/CLK }
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic1D5$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD5$ClkName/E]        
           connect_pins -driver [get_pins -of_objects [get_cells UmeshLogic0D5$ClkName] -filter "pin_direction==out"] [get_pins UmeshICGDummyD5$ClkName/TE]
         }
         if [regexp -nocase {N3} $P(TECHNO_NAME)] { set d5Driver [get_pins UmeshICGDummyD5$ClkName/Q] }
         #CN if [regexp -nocase {N5} $P(TECHNO_NAME)] { set d5Driver [get_pins UmeshICGDummyD5$ClkName/Q] }
         if [regexp -nocase {N6} $P(TECHNO_NAME)] { set d5Driver [get_pins UmeshICGDummyD5$ClkName/Z] }
         foreach_in_collection mPin $d5SinkPins {
           disconnect_net [get_nets -of_objects $mPin] $mPin
         }
         connect_pin -driver $d5Driver $d5SinkPins -port_name fixClockD5      
       }


       #Report after fixing S1 loads
       set MaxClkDepth [forwardTrace SinkDb $ClkNet 0 $ClkName]
       echo "INFO: $ClkName, Max Clock Sink Depth after fix is $MaxClkDepth\nMaxDepth  CurrentDepth  Sink" >> rpts/FxSynthesize/clockDepth.afterSinkFix.rpt
       if {$MaxClkDepth > 7} {
         echo "ERROR: $ClkName, Max Clock Sink Depth is $MaxClkDepth and that will break I2CG. Max depth should be 6 or less. Buffer and clockgater is counted as depth of 2." >> rpts/FxSynthesize/clockDepth.afterSinkFix.rpt
       }
       set fS1Loads 0
       redirect -append rpts/FxSynthesize/clockDepth.afterSinkFix.rpt {
         foreach tkey [dict keys $SinkDb] {
           set tdepth [dict get $SinkDb $tkey depth]
           set mdepth [dict get $SinkDb $tkey mdepth]
           if {$mdepth>0 && $tdepth==1} {
             incr fS1Loads 
           }
           puts "$mdepth  $tdepth  $tkey"
         }
         if {$fS1Loads < 26} {
           puts "INFO: $ClkName, Total S1 loads: $fS1Loads"
         } else {
           puts "ERROR:$ClkName, Total S1 loads $fS1Loads is higher than 25 that may break I2CG"
         }
       }

    }  
  }

  #dont touch on dummy gaters
  set cellsICGDummy [get_cells -hier * -f "full_name=~*Umesh*Dummy*"]
  if { [sizeof $cellsICGDummy] > 0 } {
     set_dont_touch $cellsICGDummy true
  }
  sh gzip -f rpts/FxSynthesize/clockDepth.afterSinkFix.rpt rpts/FxSynthesize/clockDepth.b4SinkFix.rpt

}


#######################################
### Helper procs - Disha            ###
#######################################
proc lequal {x y} {
   if {[llength $x] != [llength $y]} { return 0 }
   for {set i 0} {$i <[llength $x]} {incr i} {
      if {[lindex $x $i] != [lindex $y $i]} { return 0 }
   } 
   return 1
}

proc pdict {dict {pattern *}} {
   set longest 0
   set keys [dict keys $dict $pattern] 
   foreach key $keys {
      set l [string length $key]
      if {$l > $longest} {set longest $l}
   }
   foreach key $keys {
      puts [format "%-${longest}s = %s" $key [dict get $dict $key]]
   }
}

#######################################
## clock gate enable delays - Disha ###
#######################################
proc df_feint_clkgate_enable_delay {args} {

   # Get all the arguments out else set defaults
   parse_proc_arguments -args $args results
   if {![info exists results(-distanceList)]} {set results(-distanceList) {25 50 75 100 150 200} }
   set lDist $results(-distanceList)
   if {![info exists results(-fanoutList)]} {set results(-fanoutList) {8 16 32 64} }
   set lFO $results(-fanoutList)
   if {![info exists results(-FanOutxDistMatrix)]} {set results(-FanOutxDistMatrix) {{30 35 45 50 55 60 80} {35 40 50 55 60 70 80} {40 45 55 60 60 70 80} {50 55 65 70 70 80 90} {65 70 80 85 85 95 100}} }
   #FanOut\Distance	<=25	>25 && <=50	>50 && <=75	>75 && <=100	>100 && <=150	>150 && <=200	>200
   #<=8	            30    	35	         45	         50	            55	            60	         80
   #> 8 && <=16	   35	      40	         50	         55	            60	            70	         80
   #>16 && <=32	   40	      45	         55	         60	            60	            70	         80
   #>32 && <=64	   50	      55	         65	         70	            70	            80	         90
   #>64	            65	      70	         80	         85	            85	            95	         100

   set lMatrix $results(-FanOutxDistMatrix)
   if {![info exists results(-target)]} {set results(-target) FxSynthesize }
   set TARGET_NAME $results(-target)

   #Do sanity checking on the matrix
   set error 0;
   if {![lequal $lDist [lsort -integer $lDist]]} {set error 1; echo "Check the lDist, Order isnt correct"}
   if {![lequal $lFO [lsort -integer $lFO]]} {set error 1; echo "Check the lFO, Order isnt correct"}
   if {[llength $lMatrix] != [expr [llength $lFO] + 1 ]} {set error 1 ; echo "Check the matrix, FanOut doesnt match"}
   foreach mFO $lMatrix {
      if {[llength $mFO] != [expr [llength $lDist] + 1 ]} {set error 1; echo "Check the matrix, Dist doesnt match"}
      if {![lequal $mFO [lsort -integer $mFO]]} {set error 1; echo "Check the matrix, Order isnt correct"}
   }
   if {$error} {echo "Error: Matrix error in df_feint_clkgate_enable_delay proc in user_procs.tcl" ; return}

   echo "Clock-Gater-Name: FanOut, MaxDistance" > rpts/$TARGET_NAME/clkGating.FO.Dist.rpt
   foreach_in_collection MyClk [all_clocks] {
      #Initialize var to avoid redoing the loop for virtual clocks
      set cgCells "" ; set latFreeICGen ""
      foreach_in_collection ClkSrc [get_attribute $MyClk sources -quiet] {
         #CN Missing: CKOR2LNQ* and CKNR2*, CKLH*, GCK*, PTCK*
#N3:     #CN set cgCells [filter_col [all_fanout -from $ClkSrc -only_cells -flat] @ref_name=~"CKLNQ*"&&@full_name!~"tile_dfx*"] 
#N6:     #CN set cgCells [filter_col [all_fanout -from $ClkSrc -only_cells -flat] @ref_name=~"HDN6B*_CKGTPLT_V7Y2_*"&&@full_name!~"tile_dfx*"]
         set cgCells [get_cells -hier -quiet [all_fanout -from $ClkSrc -only_cells -flat] -filter clock_gating_integrated_cell=~"latch_*edge*"&&full_name!~"tile_dfx*"]
         #CN Missing: CKAN2D*, CKOR2D*, MRKCKAN*
#N3:     #CN set ckndCells [filter_col [all_fanout -from $ClkSrc -only_cells -flat] @ref_name=~"CKND2*"&&@full_name!~"tile_dfx*"]
#N3:     #CN set ckorCells [filter_col [all_fanout -from $ClkSrc -only_cells -flat] @ref_name=~"CKNR2*"&&@full_name!~"tile_dfx*"]
#N6:     #CN set ckndCells [filter_col [all_fanout -from $ClkSrc -only_cells -flat] @ref_name=~"HDN6B*_ND2_CK_*"&&@full_name!~"tile_dfx*"] 
#N6:     #CN set ckorCells [filter_col [all_fanout -from $ClkSrc -only_cells -flat] @ref_name=~"HDN6B*_NR2_CK_*"&&@full_name!~"tile_dfx*"] 
         set latFreeICG   [get_cells -hier -quiet [all_fanout -from $ClkSrc -only_cells -flat] -filter full_name!~"tile_dfx*"&&clock_gating_integrated_cell=~"none_*edge*"]
         set latFreeICGen [get_pins -quiet -filter is_clock_gating_enable -of $latFreeICG]
      }
      #Finding the FanOut and Dist of each Clock gater and bucketizing them
      set dCGbuckets [dict create]
      if { [info exists cgCells] && [sizeof $cgCells] } {
         foreach_in_collection cgCell $cgCells {
            set allFanoutPins [filter_col [get_pins -of_objects [get_nets -quiet -of_objects [get_pins -of_objects $cgCell -filter "direction==out"]] -leaf -filter "direction==in"] "full_name!~*clk_gate*"]
            set sizeAllFanout [sizeof_col $allFanoutPins ]
            set manhatAllFanout 0
            set cgX [lindex [lindex [get_attribute [get_pins -of_objects $cgCell -filter "direction==out"] bbox] 0] 0]
            set cgY [lindex [lindex [get_attribute [get_pins -of_objects $cgCell -filter "direction==out"] bbox] 0] 1]
            foreach_in_collection FOpin $allFanoutPins {
               set pinX [lindex [lindex [get_attribute [get_pins $FOpin] bbox] 0] 0]
               set pinY [lindex [lindex [get_attribute [get_pins $FOpin] bbox] 0] 1]
               set manhatPin [expr abs($pinX - $cgX) + abs($pinY - $cgY) ]
               if {$manhatPin > $manhatAllFanout} { set manhatAllFanout $manhatPin }
               #echo "Test : [get_object_name $FOpin] $manhatPin"
            }
            echo "[get_object_name $cgCell]: $sizeAllFanout, $manhatAllFanout" >> rpts/$TARGET_NAME/clkGating.FO.Dist.rpt
            set Dist $manhatAllFanout
            set FO $sizeAllFanout
            set mtrxFO [llength $lFO]
            for {set i 0} {$i <[llength $lFO]} {incr i} {
               if {$FO <= [lindex $lFO $i]} { set mtrxFO $i ; break }
            }
            set mtrxDist [llength $lDist]
            for {set i 0} {$i <[llength $lDist]} {incr i} {
               if {$Dist <= [lindex $lDist $i]} { set mtrxDist $i ; break }
            }
            set str "FO_${mtrxFO}_Dist_${mtrxDist}"
            if {[dict exists $dCGbuckets $str]} {
               dict lappend dCGbuckets $str [get_object_name $cgCell]
            } else {
               dict set dCGbuckets $str [list [get_object_name $cgCell]]
            }
            #echo "Test : [get_object_name $cgCell] $sizeAllFanout $manhatAllFanout"
         }
      }
 
      #All cgCells Dist and Fanout are bucketized. Now, apply constraints
      foreach key [dict keys $dCGbuckets] {
         #echo "$key"
         set FO ""
         set Dist ""
         if {[regexp {FO_(.*)_Dist_(.*)} $key matched FO Dist]} {
            set cells [dict get $dCGbuckets $key]
            set value [lindex [lindex $lMatrix $FO] $Dist]
            #CN echo "setting output delay of $value on [get_object_name [get_pins -of_objects [get_cells $cells] -filter @name==E]]" >> rpts/$TARGET_NAME/clkGating.FO.Dist.rpt
            if { [sizeof_col [get_pins -quiet -of [get_cells $cells] -filter is_clock_gating_enable]] == 0 } { continue }
            echo "setting output delay of $value on [get_object_name [get_pins -of [get_cells $cells] -filter is_clock_gating_enable]]" >> rpts/$TARGET_NAME/clkGating.FO.Dist.rpt
            #CN set_output_delay $value -clock [get_object_name $MyClk] [get_pins -of [get_cells $cells] -filter @name==E]
            set_output_delay $value -clock [get_object_name $MyClk] [get_pins -of [get_cells $cells] -filter is_clock_gating_enable]
         } else {
            echo "Something went wrong with $key"
         }
      }

#CN   if { [info exists ckndCells] && [sizeof $ckndCells] } {
#CN      set_output_delay 40 -clock [get_object_name $MyClk] -clock_fall [get_pins -of_objects $ckndCells -filter @name==EN]
#CN   }
#CN   if { [info exists ckorCells] && [sizeof $ckorCells] } {
#CN      set_output_delay 40 -clock [get_object_name $MyClk] -clock_fall [get_pins -of_objects $ckorCells -filter @name==EN]
#CN   }
      if [sizeof_col $latFreeICGen] {
         set_output_delay 40 -clock [get_object_name $MyClk] $latFreeICGen
         set_output_delay 40 -clock [get_object_name $MyClk] -add_delay -clock_fall $latFreeICGen
      }
   }
   sh gzip -f rpts/$TARGET_NAME/clkGating.FO.Dist.rpt
}

##############################################
#### Port Magnet Placement for flopped I/O ###
##############################################
proc pullReg2Port {PortColl} {
   set RegColl ""
   set CellCnt 0
   if {[sizeof [get_ports $PortColl -filter "direction==in"]] > 0} {
      remove_buffer_trees -from [get_ports $PortColl -filter "direction==in"]
   }
   if {[sizeof [get_ports $PortColl -filter "direction==out"]] > 0} {
      remove_buffer_trees -source_of [get_ports $PortColl -filter "direction==out"]
   }
   link
   foreach_in_collection EachPort $PortColl {
      set EachPortName [get_object_name $EachPort]
      echo "$EachPortName"
      set Dir [get_attr $EachPort direction]
      if {$Dir=="in"}  {set EachPort2Reg [all_fanout -flat -from $EachPort -only_cells ] }
      if {$Dir=="out"} {set EachPort2Reg [all_fanin -flat -to $EachPort -only_cells ] }
      if {[sizeof_collection $EachPort2Reg]<1} {
         echo "Warning: Doesn't have any driving/receiving cells in the path" 
      } elseif {[sizeof [get_cells $EachPort2Reg -f "is_mapped==true"]] > 0} {
         append_to_collection -unique RegColl [get_cells $EachPort2Reg -f "is_mapped==true"]
      } else {
         echo "Warning: The driving/receiving cell is NOT mapped thus not magnet placed"
      }
   }
   
   set RegColl [remove_from_collection $RegColl [get_cells -hier * -f "full_name=~*dff__PreCDC*||full_name=~*d0nt_MCPM*||full_name=~*d0nt_CDC*"]]
   set CellCnt [sizeof_collection $RegColl]
   echo "NoOfPorts: [sizeof_collection $PortColl]\nNoOfCells: $CellCnt\n"
   
   if {$CellCnt<1} {
      echo "##Warning: There are no cells to be pulled close the ports"
   } else {
      magnet_placement -mark_fixed -cells $RegColl $PortColl  > rpts/FxSynthesize/MagPulledCells.rpt
      sh gzip -f rpts/FxSynthesize/MagPulledCells.rpt
   }
}



##############################################
####### Port Bounds for flopped I/O ##########
### Umesh (07/12/2020)           #############
##############################################
proc boundReg2Port {PortColl hardBnd radius bndPrefix} {
 set RegColl ""
 set CellCnt 0
 set numPorts 0
 if {[info exists portCellDb]} {unset portCellDb}
 foreach_in_collection EachPort $PortColl {
    set EachPortName [get_object_name $EachPort]
    echo "$EachPortName"
    set Dir [get_att $EachPort direction]
    if {$Dir=="in"}  {set RegColl [get_cells [all_fanout -flat -from $EachPort -only_cells -endpoints_only] -f "is_integrated_clock_gating_cell!=true"]}
    if {$Dir=="out"} {set RegColl [get_cells [all_fanin -flat -to $EachPort -only_cells -startp] -f "is_integrated_clock_gating_cell!=true"]}
    remove_from_collection $RegColl $EachPort
    if {[sizeof_collection $RegColl]<1} {
      puts "##Warning: Port $EachPortName doesn't have any cells in it's driving/receiving cone"
    } else {
      dict set portCellDb $EachPortName $RegColl
      set CellCnt [expr $CellCnt+[sizeof_collection $RegColl]]
    }
    set RegColl ""
  }

  foreach pName [dict keys $portCellDb] {
    set pPort [get_ports $pName]

    if {$hardBnd==1} {
      set sX [lindex [lindex [get_attribute $pPort bbox] 0] 0]
      set sY [lindex [lindex [get_attribute $pPort bbox] 0] 1]
      set llX [expr $sX-$radius]
      set urX [expr $sX+$radius]
      set llY [expr $sY-$radius]
      set urY [expr $sY+$radius]
      create_bound -name $bndPrefix${pName} -boundary [list [list $llX $llY] [list $urX $urY]] -type hard [dict get $portCellDb $pName]      
    } else {  
      create_bound -name $bndPrefix${pName} -diamond $pPort -dimensions $radius [dict get $portCellDb $pName]              
    } 
    
    incr numPorts     
  }
  puts "NoOfPorts: $numPorts \nNoOfCells: $CellCnt\n"
  
}

##############################################
### Remove fixed attribute from cells after ##
### Port Magnet Placement for flopped I/O ####
##############################################
proc removeFixedAttrMagCells {magPorts} {
   #set RegColl [get_cells -hier * -filter "magnet_cell==true"]
   set RegColl [get_cells -of_objects  [get_pins -of_objects [get_nets -of_objects  [get_ports $magPorts] -segments] -filter "is_hierarchical!=true"]]
   set CellCnt [sizeof_collection $RegColl]
   puts "NoOfCellsMagnetPlaced: $CellCnt\n"
   
   if {$CellCnt<1} {
      puts "##Warning: There are no cells to be pulled close the ports"
   } else {
      remove_attribute  [get_cells $RegColl ] is_fixed
      remove_attribute  [get_cells $RegColl ] dont_touch
   }
}

##############################################
### Start: Dynamic group paths for reg2reg ###
##############################################
proc dynPathGroup {{WeightR2RT 4} {WeightR2RM 3} {WeightR2RL 2} {Tth 0.9} {Mth 0.75} {Lth 0.45}} {

  # Avoiding multiple all_registers queries to speed-up
  set allRegisters [all_registers]
  if { ![amd_getvarsave DF_FEINT_IS_TILE_RTL 0] } {
    #CN: Clock-gaters are never start-points - collect only FFs & latches
    #set DFRegs [all_registers]
    set DFRegs [get_cells * -hier -filter is_sequential&&!is_integrated_clock_gating_cell]
    #CN: Attribute-based selection instead of name-based - collect ICGs
#N3:set DFckCells [get_cells * -hier -filter ref_name=~"CK*AMDBWP*3P48CPD*"||ref_name=~"MRKCK*AMDBWP*3P48CPD*"]                  ;# missing: CKLNQD1BWP143M169H3P48CPDLVT ; CKINV are never end-points
#N3:set DFckCells [get_cells * -hier -filter is_sequential&&(ref_name=~"CK*AMDBWP*3P48CPD*"||ref_name=~"MRKCK*AMDBWP*3P48CPD*")] ;# missing: CKLNQD1BWP143M169H3P48CPDLVT (2226)
#N6:set DFckCells [get_cells * -hier -filter @ref_name=~"HDN*B*VT08_CK*"]
    set DFckCells [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell]
  } else {
    set DFandFCFPRegs [get_cells $allRegisters -filter @full_name!~"tile_dfx/*"&&@full_name!~"scf_*/*"&&@full_name!~"*AVFS*"&&@full_name!~"*avfs*"&&@full_name!~"*_dft*/*"&&@full_name!~"*_smu_*/*"]
    set FCFPRegs [get_cells $allRegisters -filter @full_name=~"*FCFP*"&&@full_name!~"*Dat0Tgt*"&&@full_name!~"*Dat0Src*"&&@full_name!~"*ReqTgt*"&&@full_name!~"*ReqSrc*"&&@full_name!~"*ReqNdTgt*"&&@full_name!~"*ReqNdSrc*"&&@full_name!~"*RspTgt*"&&@full_name!~"*RspSrc*"&&@full_name!~"*RspNdTgt*"&&@full_name!~"*RspNdSrc*"&&@full_name!~"*Prb?Tgt*"&&@full_name!~"*Prb?Src*"&&@full_name!~"*CfgSrc*"&&@full_name!~"*DbgSrc*"&&@full_name!~"*MscSrc*"&&@full_name!~"*CfgTgt*"&&@full_name!~"*DbgTgt*"&&@full_name!~"*MscTgt*"&&@full_name!~"*Fti*"]
    #CN set DFRegs [remove_from_collection $DFandFCFPRegs $FCFPRegs]
    set DFRegs [get_cells -filter is_sequential&&!is_integrated_clock_gating_cell [remove_from_collection $DFandFCFPRegs $FCFPRegs]]
#N3:set DFckCells [get_cells [get_cells * -hier -filter ref_name=~"CK*AMDBWP*3P48CPD*"||ref_name=~"MRKCK*AMDBWP*3P48CPD*"] -filter @full_name!~"tile_dfx/*"&&@full_name!~"scf_*/*"&&@full_name!~"*AVFS*"&&@full_name!~"*avfs*"&&@full_name!~"*_dft*/*"&&@full_name!~"*_smu_*/*"]
#N6:set DFckCells [get_cells [get_cells * -hier -filter @ref_name=~"HDN*B*VT08_CK*"] -filter @full_name!~"tile_dfx/*"&&@full_name!~"scf_*/*"&&@full_name!~"*AVFS*"&&@full_name!~"*avfs*"&&@full_name!~"*_dft*/*"&&@full_name!~"*_smu_*/*"]
    set DFckCells [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell&&full_name!~"tile_dfx/*"&&full_name!~"scf_*/*"&&full_name!~"*AVFS*"&&full_name!~"*avfs*"&&full_name!~"*_dft*/*"&&full_name!~"*_smu_*/*"]
    #CN set NonDFRegs [remove_from_collection [all_registers] $DFRegs]
    set NonDFRegs [remove_from_collection [get_cells * -hier -filter is_sequential&&!is_integrated_clock_gating_cell] $DFRegs]
#N3:set NonDFckCells [remove_from_collection [get_cells * -hier -filter ref_name=~"CK*AMDBWP*3P48CPD*"||ref_name=~"MRKCK*AMDBWP*3P48CPD*"] $DFckCells]
#N6:set NonDFckCells [remove_from_collection [get_cells * -hier -filter @ref_name=~"HDN*B*VT08_CK*"] $DFckCells]
    set NonDFckCells [remove_from_collection [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell] $DFckCells]
  }
  # IP's sequentials
  set DFinternal [add_to_collection $DFRegs $DFckCells]

  #update_timing -full
  get_cells -hier * ; get_attribute [get_ports *CLK*] full_name ; list
  redirect /dev/null { report_attributes -application -class port [get_ports *CLK*] }
  update_timing -full

  #CN set tpaths [get_timing_paths -nworst 1 -max_paths 1 -from [all_registers] -to $DFinternal]
  #CN set wnsr2r [get_attribute $tpaths slack]
  redirect /dev/null { set wnsr2r [get_att [get_timing_paths -nworst 1 -max_paths 1 -from $DFRegs -to $DFinternal] slack] }
  puts "WNS reg2reg: $wnsr2r"

  set WeightR2RN 1
  puts "WeightR2RT:$WeightR2RT : WeightR2RM:$WeightR2RM : WeightR2RL:$WeightR2RL : WeightR2RN:$WeightR2RN : Tth:$Tth Mth:$Mth Lth:$Lth"
  
  if {$wnsr2r < -20} {
    set tTp [expr $Tth*$wnsr2r]
    set tMp [expr $Mth*$wnsr2r]
    set tLp [expr $Lth*$wnsr2r]
    set t100p 0
  
    echo "1"
#   set CritLaunchCellsT [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"Q*"&&max_slack<$tTp]]
    set CritLaunchCellsT [get_cells -of_objects [get_pins -of_objects $DFRegs -filter direction=="out"&&max_slack<$tTp]]
    echo "2"
#   set CritCapCellsT [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"D*"&&max_slack<$tTp]]
#   echo "3"
#   set CritCapCellsT [add_to_collection -unique $CritCapCellsT [get_cells -of_objects [get_pins -of_objects $DFckCells -filter @name=~"E*"&&max_slack<$tTp]]]
    set CritCapCellsT [get_cells -of_objects [get_pins -of_objects $DFinternal -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tTp]]
    
    echo "3"
#   set CritLaunchCellsM [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"Q*"&&max_slack<$tMp]]
    set CritLaunchCellsM [get_cells -of_objects [get_pins -of_objects $DFRegs -filter direction=="out"&&max_slack<$tMp]]
    set CritLaunchCellsM [remove_from_collection $CritLaunchCellsM $CritLaunchCellsT]
    echo "4"
#   set CritCapCellsM [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"D*"&&max_slack<$tMp]]
#   echo "7"
#   set CritCapCellsM [add_to_collection -unique $CritCapCellsM [get_cells -of_objects [get_pins -of_objects $DFckCells -filter @name=~"E*"&&max_slack<$tMp]]]
    set CritCapCellsM [get_cells -of_objects [get_pins -of_objects $DFinternal -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tMp]]
    set CritCapCellsM [remove_from_collection $CritCapCellsM $CritCapCellsT]
    
    echo "5"
#   set CritLaunchCellsL [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"Q*"&&max_slack<$tLp]]
    set CritLaunchCellsL [get_cells -of_objects [get_pins -of_objects $DFRegs -filter direction=="out"&&max_slack<$tLp]]
    set CritLaunchCellsL [remove_from_collection [remove_from_collection $CritLaunchCellsL $CritLaunchCellsT] $CritLaunchCellsM]
    echo "6"
#   set CritCapCellsL [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"D*"&&max_slack<$tLp]]
#   echo "12"
#   set CritCapCellsL [add_to_collection -unique $CritCapCellsL [get_cells -of_objects [get_pins -of_objects $DFckCells -filter @name=~"E*"&&max_slack<$tLp]]]
    set CritCapCellsL [get_cells -of_objects [get_pins -of_objects $DFinternal -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tLp]]
    set CritCapCellsL [remove_from_collection [remove_from_collection $CritCapCellsL $CritCapCellsT] $CritCapCellsM]
    
    echo "7"
    set CritLaunchCells [add_to_collection -unique $CritLaunchCellsL [add_to_collection -unique $CritLaunchCellsT $CritLaunchCellsM]]
    echo "8"
    set CritCapCells [add_to_collection -unique $CritCapCellsL [add_to_collection -unique $CritCapCellsT $CritCapCellsM]]
    echo "8"
    set CritFlops [add_to_collection -unique $CritLaunchCells $CritCapCells]
    echo "9"
    set noncritLaunch_flop2flop [remove_from_collection $allRegisters $CritLaunchCells]
    echo "10"
    set noncritCap_flop2flop [remove_from_collection $allRegisters $CritCapCells]

    set noncritCap_ClkGating [get_cells -of_objects [get_pins -of_objects $DFckCells -filter @name=~"E*"]]
    set noncritCap_ClkGating [remove_from_collection $noncritCap_ClkGating $CritCapCells]
#FIXME: Check w/ Umesh if only latch based ICGs should be considered
#   set noncritCap_ClkGating [remove_from_collection [get_cells -filter clock_gating_integrated_cell=~"latch_*" $DFckCells] $CritCapCells]

    set colRemoveTheseGPs [get_attribute [get_path_groups -quiet * -filter @name=~"*CLK*"||@name=~"*R2R*"||@name=="reg2reg"] name]    
    if {$colRemoveTheseGPs != ""}  {catch [remove_path_group $colRemoveTheseGPs]}

    if { [sizeof_collection $CritLaunchCellsT] } {
      group_path -name CritTR2R -from $CritLaunchCellsT -to $CritCapCellsT -critical_range 200 -weight $WeightR2RT -priority 10
    }
    
    if { [sizeof_collection $CritLaunchCellsM] } {
      group_path -name CritMR2R -from $CritLaunchCellsM -to $CritCapCellsM -critical_range 200 -weight $WeightR2RM -priority 8
      group_path -name CritMR2R -from $CritLaunchCellsT -to $CritCapCellsM -critical_range 200 -weight $WeightR2RM -priority 8
      group_path -name CritMR2R -from $CritLaunchCellsM -to $CritCapCellsT -critical_range 200 -weight $WeightR2RM -priority 8
    }

    if { [sizeof_collection $CritLaunchCellsL] } {
      group_path -name CritLR2R -from $CritLaunchCellsL -to $CritCapCellsL -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R -from $CritLaunchCellsT -to $CritCapCellsL -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R -from $CritLaunchCellsM -to $CritCapCellsL -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R -from $CritLaunchCellsL -to $CritCapCellsT -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R -from $CritLaunchCellsL -to $CritCapCellsM -critical_range 200 -weight $WeightR2RL -priority 6
    }

    if { [sizeof_collection $noncritLaunch_flop2flop] } {
      group_path -name NonCritR2R -from $noncritLaunch_flop2flop -to $noncritCap_flop2flop -priority 4
      group_path -name NonCritR2R -from $CritLaunchCells -to $noncritCap_flop2flop -priority 4
      group_path -name NonCritR2R -from $noncritLaunch_flop2flop -to $CritCapCells -priority 4

      group_path -name NonCritClkGatingR2R -from $noncritLaunch_flop2flop -to $noncritCap_ClkGating  -priority 4
      group_path -name NonCritClkGatingR2R -from $CritLaunchCells -to $noncritCap_ClkGating  -priority 4
    }

    if { [amd_getvarsave DF_FEINT_IS_TILE_RTL 0] } {
      group_path -name NonDFR2R -from $NonDFRegs -to [all_fanout -flat -only_cell -endpoint -from [get_pins -of_objects $NonDFRegs -filter @pin_direction=="out"]]
      group_path -name NonDFR2R -from [all_fanin -flat -only_cell -startpoint -to [get_pins -of_objects $NonDFRegs -filter @pin_direction=="in"]] -to $NonDFRegs 
    }
  }
  report_path_group_weight
}


proc df_feint_dynPathGroup { args } {
  parse_proc_arguments -args $args options
  foreach o [array name options] { set [string trimleft $o "-"] $options($o) }
  set WeightR2RT 4 ; set WeightR2RM 3 ; set WeightR2RL 2
  if ![info exists WeightR2RT] { set WeightR2RT 4 }
  if ![info exists WeightR2RM] { set WeightR2RM 3 }
  if ![info exists WeightR2RL] { set WeightR2RL 2 }
  if ![info exists WeightR2ICGT] { set WeightR2ICGT 4 }
  if ![info exists WeightR2ICGM] { set WeightR2ICGM 3 }
  if ![info exists WeightR2ICGL] { set WeightR2ICGL 2 }
  if ![info exists Tth] { set Tth 0.90 }
  if ![info exists Mth] { set Mth 0.75 }
  if ![info exists Lth] { set Lth 0.45 }
  set allRegs [all_registers]
  if { ![amd_getvarsave DF_FEINT_IS_TILE_RTL 0] } {
    #CN: Clock-gaters are never start-points
    #set DFRegs [all_registers]
    set DFRegs [get_cells * -hier -filter is_sequential&&!is_integrated_clock_gating_cell]
    #CN: Attribute-based selection instead of name-based
#N3:set DFckCells [get_cells * -hier -filter ref_name=~"CK*AMDBWP*3P48CPD*"||ref_name=~"MRKCK*AMDBWP*3P48CPD*"]                  ;# missing: CKLNQD1BWP143M169H3P48CPDLVT ; CKINV are never end-points
#N3:set DFckCells [get_cells * -hier -filter is_sequential&&(ref_name=~"CK*AMDBWP*3P48CPD*"||ref_name=~"MRKCK*AMDBWP*3P48CPD*")] ;# missing: CKLNQD1BWP143M169H3P48CPDLVT (2226)
#N6:set DFckCells [get_cells * -hier -filter @ref_name=~"HDN*B*VT08_CK*"]
#CN: to skip gate-like ICGs:
#CN set DFckCells [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell&&clock_gating_integrated_cell!~"none_*edge*"]
    set DFckCells [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell]
  } else {
    set DFandFCFPRegs [get_cells $allRegs -filter @full_name!~"tile_dfx/*"&&@full_name!~"scf_*/*"&&@full_name!~"*AVFS*"&&@full_name!~"*avfs*"&&@full_name!~"*_dft*/*"&&@full_name!~"*_smu_*/*"]
    set FCFPRegs [get_cells $allRegs -filter @full_name=~"*FCFP*"&&@full_name!~"*Dat0Tgt*"&&@full_name!~"*Dat0Src*"&&@full_name!~"*ReqTgt*"&&@full_name!~"*ReqSrc*"&&@full_name!~"*ReqNdTgt*"&&@full_name!~"*ReqNdSrc*"&&@full_name!~"*RspTgt*"&&@full_name!~"*RspSrc*"&&@full_name!~"*RspNdTgt*"&&@full_name!~"*RspNdSrc*"&&@full_name!~"*Prb?Tgt*"&&@full_name!~"*Prb?Src*"&&@full_name!~"*CfgSrc*"&&@full_name!~"*DbgSrc*"&&@full_name!~"*MscSrc*"&&@full_name!~"*CfgTgt*"&&@full_name!~"*DbgTgt*"&&@full_name!~"*MscTgt*"&&@full_name!~"*Fti*"]
    #CN set DFRegs [remove_from_collection $DFandFCFPRegs $FCFPRegs]
    set DFRegs [get_cells -filter is_sequential&&!is_integrated_clock_gating_cell [remove_from_collection $DFandFCFPRegs $FCFPRegs]]
#N3:set DFckCells [get_cells [get_cells * -hier -filter ref_name=~"CK*AMDBWP*3P48CPD*"||ref_name=~"MRKCK*AMDBWP*3P48CPD*"] -filter @full_name!~"tile_dfx/*"&&@full_name!~"scf_*/*"&&@full_name!~"*AVFS*"&&@full_name!~"*avfs*"&&@full_name!~"*_dft*/*"&&@full_name!~"*_smu_*/*"]
#N6:set DFckCells [get_cells [get_cells * -hier -filter @ref_name=~"HDN*B*VT08_CK*"] -filter @full_name!~"tile_dfx/*"&&@full_name!~"scf_*/*"&&@full_name!~"*AVFS*"&&@full_name!~"*avfs*"&&@full_name!~"*_dft*/*"&&@full_name!~"*_smu_*/*"]
#CN: to skip gate-like ICGs:
#CN set DFckCells [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell&&clock_gating_integrated_cell!~"none_*edge*"&&full_name!~"tile_dfx/*"&&full_name!~"scf_*/*"&&full_name!~"*AVFS*"&&full_name!~"*avfs*"&&full_name!~"*_dft*/*"&&full_name!~"*_smu_*/*"]
    set DFckCells [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell&&full_name!~"tile_dfx/*"&&full_name!~"scf_*/*"&&full_name!~"*AVFS*"&&full_name!~"*avfs*"&&full_name!~"*_dft*/*"&&full_name!~"*_smu_*/*"]
    #CN set NonDFRegs [remove_from_collection [all_registers] $DFRegs]
    set NonDFRegs [remove_from_collection [get_cells * -hier -filter is_sequential&&!is_integrated_clock_gating_cell] $DFRegs]
#N3:set NonDFckCells [remove_from_collection [get_cells * -hier -filter ref_name=~"CK*AMDBWP*3P48CPD*"||ref_name=~"MRKCK*AMDBWP*3P48CPD*"] $DFckCells]
#N6:set NonDFckCells [remove_from_collection [get_cells * -hier -filter @ref_name=~"HDN*B*VT08_CK*"] $DFckCells]
#CN: to skip gate-like ICGs:
#CN set NonDFckCells [remove_from_collection [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell&&clock_gating_integrated_cell!~"none_*edge*"] $DFckCells]
    set NonDFckCells [remove_from_collection [get_cells * -hier -filter is_sequential&&is_integrated_clock_gating_cell] $DFckCells]
  }
  set DFinternal [add_to_collection $DFRegs $DFckCells]

  #update_timing -full
  redirect /dev/null { get_cells -hier * ; get_attribute [get_ports *CLK*] full_name ; report_attributes -application -class port [get_ports *CLK*] }
  update_timing -full

  #CN set tpaths [get_timing_paths -nworst 1 -max_paths 1 -from [all_registers] -to $DFinternal]
  #CN set wnsr2r [get_attribute $tpaths slack]
  redirect /dev/null { set wnsr2r [get_att [get_timing_paths -nworst 1 -max_paths 1 -from $DFRegs -to $DFinternal] slack] }
  puts "WNS reg2reg: $wnsr2r"

  set WeightR2RN 1
  puts "WeightR2RT:$WeightR2RT : WeightR2RM:$WeightR2RM : WeightR2RL:$WeightR2RL : WeightR2RN:$WeightR2RN"
  puts "WeightR2ICGT:$WeightR2ICGT : WeightR2ICGM:$WeightR2ICGM : WeightR2ICGL:$WeightR2ICGL"
  puts "Tth:$Tth Mth:$Mth Lth:$Lth"
  
  if {$wnsr2r < -20} {
    set tTp [expr $Tth*$wnsr2r]
    set tMp [expr $Mth*$wnsr2r]
    set tLp [expr $Lth*$wnsr2r]
    set t100p 0
  
    echo "1"
#CN set CritLaunchCellsT [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"Q*"&&max_slack<$tTp]]
    set CritLaunchCellsT [get_cells -of_objects [get_pins -of_objects $DFRegs -filter direction=="out"&&max_slack<$tTp]]
    echo "2"
#CN set CritCapCellsT [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"D*"&&max_slack<$tTp]]
#CN echo "3"
#CN set CritCapCellsT [add_to_collection -unique $CritCapCellsT [get_cells -of_objects [get_pins -of_objects $DFckCells -filter @name=~"E*"&&max_slack<$tTp]]]
#CN set CritCapCellsT [get_cells -of_objects [get_pins -of_objects $DFinternal -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tTp]]
    set CritCapFFCellsT  [get_cells -quiet -of_objects [get_pins -of_objects $DFRegs -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tTp]]
    set CritCapICGCellsT [get_cells -quiet -of_objects [get_pins -of_objects $DFckCells -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tTp]]
    
    echo "4"
#CN set CritLaunchCellsM [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"Q*"&&max_slack<$tMp]]
    set CritLaunchCellsM [get_cells -of_objects [get_pins -of_objects $DFRegs -filter direction=="out"&&max_slack<$tMp]]
    echo "5"
    set CritLaunchCellsM [remove_from_collection $CritLaunchCellsM $CritLaunchCellsT]
    echo "6"
#CN set CritCapCellsM [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"D*"&&max_slack<$tMp]]
#CN echo "7"
#CN set CritCapCellsM [add_to_collection -unique $CritCapCellsM [get_cells -of_objects [get_pins -of_objects $DFckCells -filter @name=~"E*"&&max_slack<$tMp]]]
#CN set CritCapCellsM [get_cells -of_objects [get_pins -of_objects $DFinternal -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tMp]]
    set CritCapFFCellsM  [get_cells -quiet -of_objects [get_pins -of_objects $DFRegs -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tMp]]
    set CritCapICGCellsM [get_cells -quiet -of_objects [get_pins -of_objects $DFckCells -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tMp]]
    echo "8"
#CN set CritCapCellsM [remove_from_collection $CritCapCellsM $CritCapCellsT]
    set CritCapFFCellsM  [remove_from_collection $CritCapFFCellsM  $CritCapFFCellsT]
    set CritCapICGCellsM [remove_from_collection $CritCapICGCellsM $CritCapICGCellsT]
    
    echo "9"
#CN set CritLaunchCellsL [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"Q*"&&max_slack<$tLp]]
    set CritLaunchCellsL [get_cells -of_objects [get_pins -of_objects $DFRegs -filter direction=="out"&&max_slack<$tLp]]
    echo "10"
    set CritLaunchCellsL [remove_from_collection [remove_from_collection $CritLaunchCellsL $CritLaunchCellsT] $CritLaunchCellsM]
    echo "11"
#CN set CritCapCellsL [get_cells -of_objects [get_pins -of_objects $DFRegs -filter @name=~"D*"&&max_slack<$tLp]]
#CN echo "12"
#CN set CritCapCellsL [add_to_collection -unique $CritCapCellsL [get_cells -of_objects [get_pins -of_objects $DFckCells -filter @name=~"E*"&&max_slack<$tLp]]]
#CN set CritCapCellsL [get_cells -of_objects [get_pins -of_objects $DFinternal -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tLp]]
    set CritCapFFCellsL  [get_cells -quiet -of_objects [get_pins -of_objects $DFRegs -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tLp]]
    set CritCapICGCellsL [get_cells -quiet -of_objects [get_pins -of_objects $DFckCells -filter direction=="in"&&(is_data_pin||lib_pin.is_data_pin)&&!is_scan&&!is_async_pin&&max_slack<$tLp]]
    echo "13"
#CN set CritCapCellsL [remove_from_collection [remove_from_collection $CritCapCellsL $CritCapCellsT] $CritCapCellsM]
    set CritCapFFCellsL  [remove_from_collection [remove_from_collection $CritCapFFCellsL  $CritCapFFCellsT]  $CritCapFFCellsM]
    set CritCapICGCellsL [remove_from_collection [remove_from_collection $CritCapICGCellsL $CritCapICGCellsT] $CritCapICGCellsM]
    
    echo "14"
    set CritLaunchCells [add_to_collection -unique $CritLaunchCellsL [add_to_collection -unique $CritLaunchCellsT $CritLaunchCellsM]]
    echo "15"
#CN set CritCapCells [add_to_collection -unique $CritCapCellsL [add_to_collection -unique $CritCapCellsT $CritCapCellsM]]
    set CritCapFFCells  [add_to_collection -unique $CritCapFFCellsL  [add_to_collection -unique $CritCapFFCellsT  $CritCapFFCellsM]]
    set CritCapICGCells [add_to_collection -unique $CritCapICGCellsL [add_to_collection -unique $CritCapICGCellsT $CritCapICGCellsM]]
#CN echo "16"
#CN set CritFlops [add_to_collection -unique $CritLaunchCells $CritCapFFCells]
    echo "17"
    set noncritLaunch_flop2flop [remove_from_collection $allRegs $CritLaunchCells]
    echo "18"
#CN set noncritCap_flop2flop [remove_from_collection [all_reg] $CritCapCells]
    set noncritCap_flop2flop [remove_from_col [remove_from_collection $allRegs $CritCapFFCells] $CritCapICGCells]

    #CN: Consider just latch based ICGs:
    set noncritCap_ClkGating [get_cells -of_objects [get_pins -of_objects $DFckCells -filter @name=~"E*"]]
#CN set noncritCap_ClkGating [remove_from_collection $noncritCap_ClkGating $CritCapCells]
    set noncritCap_ClkGating [remove_from_collection $noncritCap_ClkGating $CritCapICGCells]

    set colRemoveTheseGPs [get_attribute [get_path_groups -quiet * -filter @name=~"*CLK*"||@name=~"*R2R*"||@name=="reg2reg"] name]    
    if {$colRemoveTheseGPs != ""}  {catch [remove_path_group $colRemoveTheseGPs]}

    if { [sizeof_collection $CritLaunchCellsT] } {
#CN   group_path -name CritTR2R -from $CritLaunchCellsT -to $CritCapCellsT -critical_range 200 -weight $WeightR2RT -priority 10
      group_path -name CritTR2R   -from $CritLaunchCellsT -to $CritCapFFCellsT  -critical_range 200 -weight $WeightR2RT -priority 10
      group_path -name CritTR2ICG -from $CritLaunchCellsT -to $CritCapICGCellsT -critical_range 200 -weight $WeightR2ICGT -priority 10
    }
    
    if { [sizeof_collection $CritLaunchCellsM] } {
#CN   group_path -name CritMR2R -from $CritLaunchCellsM -to $CritCapCellsM -critical_range 200 -weight $WeightR2RM -priority 8
#CN   group_path -name CritMR2R -from $CritLaunchCellsT -to $CritCapCellsM -critical_range 200 -weight $WeightR2RM -priority 8
#CN   group_path -name CritMR2R -from $CritLaunchCellsM -to $CritCapCellsT -critical_range 200 -weight $WeightR2RM -priority 8
      group_path -name CritMR2R   -from $CritLaunchCellsM -to $CritCapFFCellsM  -critical_range 200 -weight $WeightR2RM -priority 8
      group_path -name CritMR2R   -from $CritLaunchCellsT -to $CritCapFFCellsM  -critical_range 200 -weight $WeightR2RM -priority 8
      group_path -name CritMR2R   -from $CritLaunchCellsM -to $CritCapFFCellsT  -critical_range 200 -weight $WeightR2RM -priority 8
      group_path -name CritMR2ICG -from $CritLaunchCellsM -to $CritCapICGCellsM -critical_range 200 -weight $WeightR2ICGM -priority 8
      group_path -name CritMR2ICG -from $CritLaunchCellsT -to $CritCapICGCellsM -critical_range 200 -weight $WeightR2ICGM -priority 8
      group_path -name CritMR2ICG -from $CritLaunchCellsM -to $CritCapICGCellsT -critical_range 200 -weight $WeightR2ICGM -priority 8
    }

    if { [sizeof_collection $CritLaunchCellsL] } {
#CN   group_path -name CritLR2R -from $CritLaunchCellsL -to $CritCapCellsL -critical_range 200 -weight $WeightR2RL -priority 6
#CN   group_path -name CritLR2R -from $CritLaunchCellsT -to $CritCapCellsL -critical_range 200 -weight $WeightR2RL -priority 6
#CN   group_path -name CritLR2R -from $CritLaunchCellsM -to $CritCapCellsL -critical_range 200 -weight $WeightR2RL -priority 6
#CN   group_path -name CritLR2R -from $CritLaunchCellsL -to $CritCapCellsT -critical_range 200 -weight $WeightR2RL -priority 6
#CN   group_path -name CritLR2R -from $CritLaunchCellsL -to $CritCapCellsM -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R   -from $CritLaunchCellsL -to $CritCapFFCellsL  -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R   -from $CritLaunchCellsT -to $CritCapFFCellsL  -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R   -from $CritLaunchCellsM -to $CritCapFFCellsL  -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R   -from $CritLaunchCellsL -to $CritCapFFCellsT  -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2R   -from $CritLaunchCellsL -to $CritCapFFCellsM  -critical_range 200 -weight $WeightR2RL -priority 6
      group_path -name CritLR2ICG -from $CritLaunchCellsL -to $CritCapICGCellsL -critical_range 200 -weight $WeightR2ICGL -priority 6
      group_path -name CritLR2ICG -from $CritLaunchCellsT -to $CritCapICGCellsL -critical_range 200 -weight $WeightR2ICGL -priority 6
      group_path -name CritLR2ICG -from $CritLaunchCellsM -to $CritCapICGCellsL -critical_range 200 -weight $WeightR2ICGL -priority 6
      group_path -name CritLR2ICG -from $CritLaunchCellsL -to $CritCapICGCellsT -critical_range 200 -weight $WeightR2ICGL -priority 6
      group_path -name CritLR2ICG -from $CritLaunchCellsL -to $CritCapICGCellsM -critical_range 200 -weight $WeightR2ICGL -priority 6
    }

    if { [sizeof_collection $noncritLaunch_flop2flop] } {
      group_path -name NonCritR2R -from $noncritLaunch_flop2flop -to $noncritCap_flop2flop -priority 4
      group_path -name NonCritR2R -from $CritLaunchCells -to $noncritCap_flop2flop -priority 4
#CN   group_path -name NonCritR2R -from $noncritLaunch_flop2flop -to $CritCapFFCells -priority 4

      group_path -name NonCritClkGatingR2R -from $noncritLaunch_flop2flop -to $noncritCap_ClkGating  -priority 4
      group_path -name NonCritClkGatingR2R -from $CritLaunchCells -to $noncritCap_ClkGating  -priority 4
    }

    if { [amd_getvarsave DF_FEINT_IS_TILE_RTL 0] } {
      group_path -name NonDFR2R -from $NonDFRegs -to [all_registers [all_fanout -flat -only_cell -endpoint -from [get_pins -of_objects $NonDFRegs -filter @pin_direction==out]]]
      group_path -name NonDFR2R -from [all_registers [all_fanin -flat -only_cell -startpoint -to [get_pins -of_objects $NonDFRegs -filter @pin_direction==in]]] -to $NonDFRegs 
    }
  }
  report_path_group_weight
}
define_proc_attributes df_feint_dynPathGroup \
    -info "Create dynamic group paths for reg2reg/reg2icg." \
    -define_args {
      {-WeightR2RT   "Group_path weight for topCrit R2R group (default 4)"  "" string optional} \
      {-WeightR2RM   "Group path weight for midCrit R2R group (default 3)"  "" string optional} \
      {-WeightR2RL   "Group path weight for lowCrit R2R group (default 2)"  "" string optional} \
      {-WeightR2ICGT "Group path weight for topCrit R2ICG group (default 4)"  "" string optional} \
      {-WeightR2ICGM "Group path weight for midCrit R2ICG group (default 3)"  "" string optional} \
      {-WeightR2ICGL "Group path weight for lowCrit R2ICG group (default 2)"  "" string optional} \
      {-Tth          "Critical wns threshold for topCrit path groups (default .90*WNS)"  "" string optional} \
      {-Mth          "Critical wns threshold for midCrit path groups (default .75*WNS)"  "" string optional} \
      {-Lth          "Critical wns threshold for lowCrit path groups (default .45*WNS)"  "" string optional} \
    }


proc df_feint_report_FlopSkew {TARGET_NAME} {
   update_timing -full
   set AllRegs [all_registers -edge]
   set mRegs [get_cells $AllRegs -f "full_name!~*tile_dfx*&&full_name!~*smn*&&full_name!~*smu*&&full_name!~*avfs*&&full_name!~*DDR*&&full_name!~*FCFP*&&full_name!~*FEED*"]
   
   if [info exists exRegs] {unset exRegs}
   foreach_in_collection mPort [remove_from_collection [all_inputs] [get_ports [all_clock_sources]]] {
   	append_to_collection -unique exRegs [get_cells -quiet [all_fanout -quiet -flat -endpoints_only -only_cells -from $mPort]]
   }
   foreach_in_collection mPort [all_outputs] {
   	append_to_collection -unique exRegs [get_cells -quiet [all_fanin -quiet -flat -startpoints_only -only_cells -to $mPort]]
   }
   
   if [info exists earlyExRegs] {unset earlyExRegs}
   if [info exists lateExRegs] {unset lateExRegs}
   set earlyExRegs $exRegs
   set lateExRegs $exRegs
   
   #clk_gate_AutoRefReqPb_reg_latch/E
   #clk_gate_FEI_SDPINTF_TagArrVld_reg_191__latch__FLOP_an2_744__SCMT_5C5_G_XPND/EN
   #latch_latch
   #In case of split CG, pick only the AND part of the CG, not the latch - only for DF and UMC IP
   set clkGateCells [get_cells -hier * -f "full_name=~*clk_gate_*&&full_name!~*_latch_*&&full_name!~*tile_dfx*&&full_name!~*smn*&&full_name!~*smu*&&full_name!~*avfs*&&full_name!~*DDR*&&full_name!~*FCFP*&&full_name!~*FEED*"]
   foreach_in_collection mPin [get_pins -quiet -of_objects $clkGateCells -f "name=~E*&&max_slack<50"] {
   	set mOutPin [get_pins -of_objects [get_cells -of_objects $mPin] -f "name==Z||name==X"]
   	append_to_collection -unique earlyExRegs [get_cells -quiet [all_fanout -quiet -flat -endpoints_only -only_cells -from $mOutPin]]
   }
   
   append_to_collection -unique earlyExRegs [get_cells -of_objects [get_pins -quiet -of_objects $mRegs -f "name=~D*&&max_slack<50"]]
   set pEarlySkewRegs [remove_from_collection -inter $mRegs [get_cells -of_objects [get_pins -quiet -of_objects $mRegs -f "name=~Q*&&max_slack<5"]]]
   set eSkewRegs [remove_from_collection $pEarlySkewRegs $earlyExRegs]
   redirect -f rpts/${TARGET_NAME}/skewEarlyRegs.rpt {
   	foreach_in_collection mCell $eSkewRegs {
   		echo [get_object_name $mCell]
   	}
   }
   
   append_to_collection -unique lateExRegs [get_cells -of_objects [get_pins -quiet -of_objects $mRegs -f "name=~Q*&&max_slack<50"]]
   set pLateSkewRegs [remove_from_collection -inter $mRegs [get_cells -of_objects [get_pins -quiet -of_objects $mRegs -f "name=~D*&&max_slack<5"]]]
   set lSkewRegs [remove_from_collection $pLateSkewRegs $lateExRegs]
   set lSkewRegs [remove_from_collection $lSkewRegs $eSkewRegs]
   redirect -f rpts/${TARGET_NAME}/skewLateRegs.rpt {
   	foreach_in_collection mCell $lSkewRegs {
   		echo [get_object_name $mCell]
   	}
   }
}

## Start: Dynamic group paths for in2reg/reg2out ##

proc df_feint_dynPathGroupIO { args } {
  parse_proc_arguments -args $args results
  
  set FeedFilter "name!~*FEED*&&name!~*FCFP*&&name!~*SSB*&&defined(net)"
  set gptype  $results(-type)
  set WeightT 1
  if {[info exist results(-wtt)]} {
    set WeightT $results(-wtt)
  }
  set WeightM 1
  if {[info exist results(-wtm)]} {
    set WeightM $results(-wtm)
  }
  set WeightL 1
  if {[info exist results(-wtl)]} {
    set WeightL $results(-wtl)
  }
  set CritWNSLimit -20
  if {[info exist results(-wns)]} {
    set CritWNSLimit $results(-wns)
  }

  if { $gptype == "in2reg" } {
    set TimCmd "get_timing_paths -nworst 1 -max_paths 1  -from \[get_ports * -filter \"direction==in&&$FeedFilter\"\]"
    set GPCmd "group_path -from"
    set GPName "I2R"
    set pdir "in"
  } elseif { $gptype == "reg2out" } {
    set TimCmd "get_timing_paths -nworst 1 -max_paths 1  -to \[get_ports * -filter \"direction==out&&$FeedFilter\"\]"
    set GPCmd "group_path -to"
    set GPName "R2O"
    set pdir "out"
  } else {
    puts "Error: Incorrect path group name!!"
    return ""
  }
  
  set tpaths [eval $TimCmd]

  set CritWNS 1
  foreach_in_collection path $tpaths {
    set twns [get_attribute $path slack]
    if {$twns < $CritWNS} { 
      set CritWNS $twns
    }
  }
  
  if {$CritWNS < $CritWNSLimit} {
    puts "Info: Creating dynamic group paths for $gptype"
    set tTp [expr (1-0.1)*$CritWNS]
    set tMp [expr (1-0.25)*$CritWNS]
    set tLp [expr (1-0.55)*$CritWNS]
    set t100p 0

    set CritPathT [get_ports * -filter "direction==$pdir&&max_slack<$tTp&&$FeedFilter"]
    set CritPathM [get_ports * -filter "direction==$pdir&&max_slack<$tMp&&$FeedFilter"]
    set CritPathM [remove_from_collection $CritPathM $CritPathT]
    set CritPathL [get_ports * -filter "port_direction==$pdir&&max_slack<$tLp&&$FeedFilter"]
    set CritPathL [remove_from_collection [remove_from_collection $CritPathL $CritPathT] $CritPathM]

    if { [sizeof_collection $CritPathT] } {eval $GPCmd $CritPathT -critical_range 200 -weight $WeightT -name CritT$GPName}
    if { [sizeof_collection $CritPathM] } {eval $GPCmd $CritPathM -critical_range 200 -weight $WeightM -name CritM$GPName}
    if { [sizeof_collection $CritPathL] } {eval $GPCmd $CritPathL -critical_range 200 -weight $WeightL -name CritL$GPName}
 }
}

define_proc_attributes df_feint_dynPathGroupIO \
    -info "Create dynamic group paths for in2reg/reg2out." \
    -define_args {
      {-type     "group_path type: in2reg or reg2out"   "" string required} \
      {-wtt      "group path weight for topCrit group"  "" string optional} \
      {-wtm      "group path weight for midCrit group"  "" string optional} \
      {-wtl      "group path weight for lowCrit group"  "" string optional} \
      {-wns      "Critical wns limit for path grouping"  "" string optional} \
    }
## End: Dynamic group paths for in2reg/reg2out ##

# Author: Christopher Stites
# Date: 10/01/2014
# Description: Find distribution of the levels of gaters across all flops
proc df_feint_count_gater_levels {} {

    # Find all gated flops
    #CN set colAllFlops [get_cells -hier -filter "ref_name=~*F*D*"]
    #CN only FFs:
    #CN set colAllFlops [get_cells -hier -filter is_fall_edge_triggered||is_rise_edge_triggered]
    #CN FFs & latches (no ICGs):
    set colAllFlops [get_cells -hier -filter is_sequential&&!is_integrated_clock_gating_cell]
    #CN set colUngatedFlops [get_cells -of_objects [get_pins -of_objects [get_nets Cpl_FCLK] -filter "pin_direction==in"]]
    set colUngatedFlops [get_cells -of_obj [get_pins -leaf -of_objects [get_nets Cpl_FCLK] -filter "pin_direction==in"] -filter is_sequential&&!is_integrated_clock_gating_cell]
    set colGatedFlops [remove_from_collection $colAllFlops $colUngatedFlops]

    echo [format "%20s %7d" "Number of msf's:" [sizeof $colAllFlops]]
    echo [format "%20s %7d" "Ungated msf's:" [sizeof $colUngatedFlops]]
    echo [format "%20s %7d" "Gated msf's:" [sizeof $colGatedFlops]]
    echo ""
    
    # Set variables
    set lstGaterCounts {}
    set lstNonGaterCounts {}
    set colCurCells $colGatedFlops
    set nLevel 0
    set arrCounts($nLevel) [sizeof $colCurCells]
    
    # Iterate through each level of gaters
    set nInfiniteLoopCtr 0
    while { [sizeof $colCurCells] > 0 } {
    
        # Check for infinite loop
        if { $nInfiniteLoopCtr > 10 } { break }
        incr nInfiniteLoopCtr
    
        # Lets get all of the gaters at the next level
        #CN set colCLKPins [get_pins -of_objects $colCurCells -filter "name==CP||name==CPN||name==CLK||name==CK"]
        set colCLKPins [get_pins -of_objects $colCurCells -filter pin_direction=="in"&&(lib_pin.is_clock_pin||is_clock_pin)]
        set colCLKNets [get_nets -of_objects $colCLKPins -segments]
        set colOutPins [get_pins -of_objects $colCLKNets -filter "pin_direction==out"]
        set colCurAllCells [get_cells -of_objects $colOutPins -filter "is_hierarchical==false"]
        #CN set colCurGaterCells    [filter_collection $colCurAllCells "ref_name==$strGaterCell"]
        #CN set colCurNonGaterCells [filter_collection $colCurAllCells "ref_name!=$strGaterCell"]
        set colCurGaterCells [get_cells $colCurAllCells -filter is_integrated_clock_gating_cell]
        set colCurNonGaterCells [get_cells $colCurAllCells -filter !is_integrated_clock_gating_cell]
    
        # Save off the data
        incr nLevel
        lappend lstGaterCounts [list $nLevel [sizeof $colCurGaterCells]]
        lappend lstNonGaterCounts [list $nLevel [sizeof $colCurNonGaterCells]]
        
        set colCurCells $colCurGaterCells
    }
    
    # Print statistics
    echo "Gaters on specific level"
    echo "Level :   Count"
    for {set idx 0} {$idx < [llength $lstGaterCounts]} {incr idx} {
        set tuple [lindex $lstGaterCounts $idx]
        set nLevel [lindex $tuple 0]
        set nGatersOnLevel [lindex $tuple 1]

        # We have to do something tricky here. Since we count the number of gaters
        #  at each level, that means a 2-level gater will be counted in the first
        #  bucket and the second bucket. We have to remove all of the gaters in
        #  the subsequent bucket to get the proper number of gaters at one specific
        #  level
        #
        # Example:
        #  lstGaterCounts = {{1 10} {2 5} {3 1}}
        # This says we have:
        #  10 gaters at level 1
        #   5 gaters at level 2
        #   1 gater  at level 3
        #  In reality, we have 10 total gaters, not 16:
        #   5 gaters ending at level 1
        #   4 gaters ending at level 2
        #   1 gater  ending at level 3
        if { [expr $idx + 1] == [llength $lstGaterCounts] } {
            set nLevelCount $nGatersOnLevel
        } else {
            set nGatersOnNextLevel [lindex [lindex $lstGaterCounts [expr $idx+1]] 1]
            set nLevelCount [expr $nGatersOnLevel - $nGatersOnNextLevel]
        }
        echo [format "%5s : %7d" $nLevel $nLevelCount]
    }
    echo ""

    echo "Non-gaters on specific level"
    echo "Level :   Count"
    for {set idx 0} {$idx < [llength $lstNonGaterCounts]} {incr idx} {
        set tuple [lindex $lstNonGaterCounts $idx]
        set nLevel [lindex $tuple 0]
        set nNonGatersOnLevel [lindex $tuple 1]
        echo [format "%5s : %7d" $nLevel $nNonGatersOnLevel]
    }
    echo ""

}
##############################################################
proc PrintHighFanoutPins {thrshld} {
    set dfmt 50
    set dList [list]
    foreach_in_collection dNet [all_high_transitive_fanout -nets -threshold $thrshld] {
        #set Driver [get_pins -of_objects $dNet -filter "pin_direction==out"]
        set Driver [get_object_name [get_pins -of_objects [get_nets $dNet -segments] -filter "pin_direction==out&&is_hierarchical!=true"]]
        #set NumLoads [sizeof [get_pins -of_objects $dNet -filter "pin_direction==in"]]
        set NumLoads [sizeof [get_pins -of_objects [get_nets $dNet -segments] -filter "pin_direction==in&&is_hierarchical!=true"]]
        lappend dList [list $Driver $NumLoads]
        if { [string length $Driver] > $dfmt } {
            set dfmt [expr [string length $Driver] +4]
        }
    }
    set dListSorted [lsort -integer -decreasing -index 1 $dList]
    
    puts [format "%6s%-${dfmt}s%s%8s%s%10s%s%9s%s" " " "DriverPin" ":" "Fanout" " : " "dont_touch" " : " "ideal_net" " :"]
    puts "-------------------------------------------------------------------------------------------------------------------"
    set cnt 1
    foreach i $dListSorted {
        set dPin [lindex $i 0]
        set dLoad [lindex $i 1]
        set dtpp [get_attribute [get_cells -of_objects $dPin] dont_touch]
        set idnp [get_attribute [all_connected $dPin] ideal_net]
        puts [format "%4d%s%-${dfmt}s%s%8d%s%10s%s%9s%s" $cnt ": " $dPin ":" $dLoad " : " $dtpp " : " $idnp " :"]
        incr cnt
    }
    puts "-------------------------------------------------------------------------------------------------------------------"
}

###################################################################

#This replaces df_feint_ReportUnplacedPortsAndMacros
proc df_feint_ReportUnplacedPortsAndMacros {} {
  ### Ports w/ defined terminal (probably missing from DEF)
  set allTerms [get_terminals -quiet -filter port.port_type!="power"&&port.port_type!="ground"]
  set allPorts [get_ports -quiet -filter port_type!="power"&&port_type!="ground"]
  foreach_in_col t $allTerms { set allPorts [remove_from_col $allPorts [get_att $t port]] }
  if [sizeof_col $allPorts] { puts "\nError: Ports w/o terminal:"
                              foreach_in_col p $allPorts { puts [get_att $p name] }
  }

  ### Unfixed ports
  set ports [get_ports -quiet -filter !is_fixed&&port_type!~"power"&&port_type!~"ground"&&name!~"DUMMYPORT_SSE"]
  if [sizeof_col $ports] {
     set uPorts ""
     foreach_in_col p $ports { if { [sizeof_col [get_terminals -filter port.name==[get_att $p name]]] == 0 } { lappend uPorts [get_att $p name] } }
     if [llength $uPorts] {
        puts "\nError: Unfixed [llength $uPorts] ports:"
        foreach p $uPorts { puts $p }
     } else { puts "\nAll ports are fixed." }
  } else { puts "\nAll ports are fixed." }

  ### Terminals outside of block area
  set pBlock [create_poly_rect -boundary [get_att [get_block] boundary]]
  unset -nocomplain outsideO
  foreach_in_col t $allTerms {
     set pT [create_poly_rect -boundary [get_att $t boundary]]
     if ![get_att [compute_polygons -operation NOT -objects1 $pT -objects2 $pBlock] is_empty] { append_to_col outsideO $t }
  }
  if [info exists outsideO] { puts "\nError: Terminals outside of block area:"
                              foreach_in_col t $outsideO { puts [get_att $t name] }
  } else {                    puts "\nAll terminals are placed withing block area." }

  ### Unfixed macros
  set allMacros [get_cells -quiet -hier -filter is_hard_macro||is_soft_macro||is_memory_cell||design_type=="macro"]
  if [sizeof_col $allMacros] {
     set unfixMacros [get_cells -quiet -hier -filter !is_fixed $allMacros]
     if [sizeof_col $unfixMacros] {
        puts "\nError: Unfixed [sizeof_col $unfixMacros] macros:"
        foreach_in_col m $unfixMacros { puts [get_att $m name] }
     } else { puts "\nAll macros are fixed." }
  }

  ### Macros outside of core area
  if [sizeof_col $allMacros] {
     set pCore [create_poly_rect -boundary [get_att [get_core_area] boundary]]
     unset -nocomplain outsideO
     foreach_in_col m $allMacros {
        set pM [create_poly_rect -boundary [get_att $m bbox]]
        if ![get_att [compute_polygons -operation NOT -objects1 $pM -objects2 $pCore] is_empty] { append_to_col outsideO $m }
     }
     if [info exists outsideO] { puts "\nError: Macros outside of block area:"
                                 foreach_in_col m $outsideO { puts [get_att $m name] }
     } else {                    puts "\nAll macros are placed withing core area." }
  }
}

define_proc_attributes df_feint_ReportUnplacedPortsAndMacros \
  -info "Verifies if there are unplaced and unfixed ports or macros" 

proc df_feint_ReportUnplacedPortsAndMacrosOld {} {
    puts "INFO: Entering proc df_feint_ReportUnplacedPortsAndMacrosOld"
    global P

    if { $P(DC_SPG_MASTERKNOB)==0 } {
        echo "Non SPG/def mode. Returning ..."
        return ""
    }

    # Parse the physical constraint report for the following:
    #   Unplaced ports & unplaced macros
    redirect -var physRpt {report_physical_constraints}
    set upportC [get_ports *]
    set upmacroC [get_cells -hier -filter "is_hard_macro==true||is_soft_macro==true||is_memory_cell==true"]
    set floatmacroC [get_cells $upmacroC -filter "is_physical_only==true"]
    if {[sizeof_collection $floatmacroC] > 0} {
	set upmacroC [remove_from_collection $upmacroC $floatmacroC]
    }
    set totports [sizeof_collection $upportC]
    set totmacros [sizeof_collection $upmacroC]
    set portsec 0
    set macrosec 0
    foreach line [split $physRpt "\n"] {
	regsub -all {\{\s+} $line {\{} line
	regsub -all {\s+\}} $line {\}} line
	regsub -all {\\} $line {} line
	if [regexp {^\s*$} $line junk] {
	    set portsec 0
	    set macrosec 0
	    continue
	} elseif [regexp {^\s*PORT\s+LOCATION\s+\d+} $line junk] {
	    set portsec 1
	    continue
	} elseif [regexp {^\s*CELL\s+\d+} $line junk] {
	    set macrosec 1
	    continue
	} elseif {$portsec} {
	    if [regexp {^\s*(\S+)} $line junk pName] {
		if [regexp {^\{} $pName junk] {
		    continue
		} else {
		    set upportC [remove_from_collection $upportC [get_ports -quiet $pName]]
		}
	    }
	    continue
	} elseif {$macrosec} {
	    if [regexp {^\s*(\S+)} $line junk mName] {
		if [regexp {^\{} $mName junk] {
		    continue
		} else {
		    set upmacroC [remove_from_collection $upmacroC [get_cells -quiet $mName]]
		}
	    }
	    continue
	}
    }
    
    # Create list of unplaced ports
    set upportlist [list]
    foreach_in_collection upport $upportC {
	set name [get_attribute $upport full_name]
	lappend upportlist $name
    }

    # Create list of unplaced macros
    set upmacrolist [list]
    foreach_in_collection upmacro $upmacroC {
	set name [get_attribute $upmacro full_name]
	lappend upmacrolist $name
    }

    # Some useful messaging...
    puts "###################################################################################################"
    if {[llength $upportlist] > 0} {
	    set ::numUnplacedPorts [llength $upportlist]
	    puts "INFO: Unplaced ports detected. $::numUnplacedPorts out of $totports ports are unplaced"
	    puts "Following are the unplaced ports:"
	    foreach upp $upportlist {
	        puts $upp
	    }
    } else {
	    puts " All $totports ports are placed"
    }
    puts "###################################################################################################"
    if {[llength $upmacrolist] > 0} {
	    set ::numUnplacedMacros [llength $upmacrolist]
	    puts " Unplaced logical macros detected. $::numUnplacedMacros out of $totmacros macros are unplaced"
	    puts "Following are the unplaced macros:"
        foreach upm $upmacrolist {
	        puts $upm
	    }
    } else {
	    puts " All $totmacros logical macros are placed"
    }
    if {[sizeof_collection $floatmacroC] > 0} {
	    puts " Physical-only macros detected. [sizeof_collection $floatmacroC] macros are physical-only"
    }
    
    puts "INFO: Exit proc df_feint_ReportUnplacedPortsAndMacros"
}

##############################################
####### Reports blockages, bounds and magPorts ###
##############################################
proc reportBoundsMagPorts {magPorts} {
  redirect -tee data/FxSynthesize.bounds.log {
      report_bounds 
  }
  
  #redirect -tee data/DgSynthesize.blockages.log {
  #  if { [sizeof [get_placement_blockages -quiet ] ] > 0 } {
  #    report_attributes [get_placement_blockages]
  #  } else {
  #   puts "Info: No placement_blockages in the design."
  #  }
  #}
  
  redirect -tee data/FxSynthesize.magnet_ports.tcl {
    if { [info exists magPorts]} {
      if { [sizeof [get_ports -quiet $magPorts] ] > 0 } {
        puts "set magPorts { \\"
        foreach_in_col po $magPorts {
          puts "[get_object_name $po] \\"
        }
        echo "}"
      } else {
        puts "Info: No magnet ports in the design."
      }
    } else {
      puts "Info: No magnet ports in the design."
    }
  }
}

##############################################
# Author: Christopher Stites   christopher.stites@amd.com
# Date: 7/6/15
#
# Description: This script finds constant ports. What that means is, all output ports 
#   being driven by constants are reported and all input ports driving no sequential 
#   logic or output ports are reported.

proc df_feint_check_constant_ports { strTopModule strReportFile } {

    # Check output ports
    set lstConstantOutports {}
    set colConstantPortDrivers [filter_collection [all_fanin -flat -start -to [get_ports -filter "pin_direction==out"]] "name=~*logic*"]
    set colConstantDrivenPorts [filter_collection [all_fanout -flat -end -from $colConstantPortDrivers] "object_class==port"]
    foreach_in_collection colPort $colConstantDrivenPorts {
        set colStartpoints [all_fanin -flat -start -to $colPort]
        set colConstantStartpoints [filter_collection $colStartpoints "name=~*logic*"]
        if { [sizeof $colStartpoints] == [sizeof $colConstantStartpoints] } {
            lappend lstConstantOutports [get_object_name $colPort]
        }
    }
    
    
    # Check input ports
    set lstVerifiedConstantInports {}
    set lstUnverifiedConstantInports {}
    set colPotentialConstantInports {}
    foreach_in_collection colPort [get_ports * -filter "pin_direction==in"] {
        set strMaxSlack [get_attr $colPort max_slack]
        if {$strMaxSlack == ""} {
            append_to_collection colPotentialConstantInports $colPort
        }
    }
    foreach_in_collection colPort $colPotentialConstantInports {
        if { [get_nets -of_objects $colPort] == ""} {
            lappend lstVerifiedConstantInports [get_object_name $colPort]
        } else {
            set colEndpoints [all_fanout -flat -end -from $colPort]
            if { [filter_collection $colEndpoints "object_class==port"] != "" } {
                # There is a timing endpoint. Skip.
                continue
            }
            if { [get_cells -of_objects $colEndpoints -filter "is_sequential==true"] != "" } {
                # There is a timing endpoint. Skip.
                continue
            }
            lappend lstUnverifiedConstantInports [get_object_name $colPort]
        }
    }
    
    # Report
    redirect -tee -file $strReportFile {
        echo "Constant output ports ([llength $lstConstantOutports]):"
        foreach strPort [lsort $lstConstantOutports] { echo "  $strPort" }
        echo ""
        echo "Constant input ports ([llength $lstVerifiedConstantInports]):"
        foreach strPort [lsort $lstVerifiedConstantInports] { echo "  $strPort" }
        echo ""
        echo "Potential other constant input ports ([llength $lstUnverifiedConstantInports]):"
        foreach strPort [lsort $lstUnverifiedConstantInports] { echo "  $strPort" }
        echo ""
        echo "Port constants summary:"
        echo "block : outputs / verified inputs / potential inputs"
        echo [format "%16s : %4d / %4d / %4d" $strTopModule [llength $lstConstantOutports] [llength $lstVerifiedConstantInports] [llength $lstUnverifiedConstantInports]]
        echo ""

    }

}

proc df_feint_GetClockSource {} {
    puts "All Reg: [sizeof [all_registers]]"
    
    set NxtLvlReg [all_fanin -to [get_pins -of_objects [all_registers] -filter "name=~C*K"] -start -only -flat]
    set AllSources [filter_col [all_fanin -to [get_pins -of_objects [all_registers] -filter "name=~C*K"] -start -flat]  "object_class==port"]
    
    puts "NxtLvlReg: [sizeof $NxtLvlReg]"
    
    while { [sizeof $NxtLvlReg] } {
    
        add_to_collection -unique $AllSources [filter_col [all_fanin -to [get_pins -of_objects $NxtLvlReg -filter "name=~C*K"] -start -flat]  "object_class==port"]
        set NxtLvlReg [all_fanin -to [get_pins -of_objects $NxtLvlReg -filter "name=~C*K"] -start -only -flat]
    
        puts "NxtLvlReg: [sizeof $NxtLvlReg]"
    }
    
    puts "Number of all Clock Sources: [sizeof $AllSources]"
    
    set cnt 1
    foreach_in_collection item [sort_collection $AllSources {full_name}] {
            echo "$cnt: [get_object_name $item]"
            incr cnt
    }
}

proc df_feint_Checkflopresetpin {} {

   puts "Summary of flops which have SET/RESET pins"
   puts "Instance Name -------------------------------- Reference Name\n"
   
   set target_collection  [get_cells -of_objects [get_pins -of_objects [get_cells -hier * -filter "is_sequential==true"] -filter "name=~*SET*"] -filter "is_hierarchical==false"]
   
   foreach_in_collection mycell $target_collection {
   
      set instance_name [get_object_name [get_cells $mycell]]
      set reference_name [get_attribute $instance_name ref_name]
      puts "$instance_name    $reference_name"
   
   }

}

proc MakeRefList {inColl} {
    set outList ""
    foreach ttEl [lsort -unique [get_attribute $inColl  ref_name]] {
        #puts "[regsub "xss.*" $uniqRef xss]"
        lappend outList [regsub "xss.*" $ttEl "xss*"]
    }
    return [lsort -unique $outList]
}

proc PrintColl {mycol fn} {
	foreach_in_collection item [sort_collection $mycol {full_name}] {
		puts $fn [get_object_name $item]
	}
}

proc df_feint_CheckSeqElem {} {
    set AllRegNo [all_registers]
    set AllEtReg [all_registers -edge_triggered]
    set AllLsReg [all_registers -level_sensitive]
    set AllRemReg [remove_from_collection $AllRegNo [add_to_collection $AllEtReg $AllLsReg]]
    
    set OutSum  [open rpts/FxSynthesize/AllRegSummary.rpt w]
    
    puts $OutSum "#####################################################\n## Edge Triggered Sequential Elements\n#####################################################"
    
    foreach uniqRef [MakeRefList $AllEtReg] {
    
        puts $OutSum [format "%25s%7d" "$uniqRef: " "[sizeof [get_cells $AllEtReg -filter @ref_name=~$uniqRef]]"]
    
    }
    puts $OutSum "\n#####################################################\n## Level Sensitive Sequential Elements\n#####################################################"
    foreach uniqRef [MakeRefList $AllLsReg] {
    
        puts $OutSum [format "%25s%7d" "$uniqRef: " "[sizeof [get_cells $AllLsReg -filter @ref_name=~$uniqRef]]"]
    
    }
    puts $OutSum "\n#####################################################\n## Remaining Sequential Elements\n#####################################################"
    foreach uniqRef [MakeRefList $AllRemReg] {
    
        puts $OutSum [format "%25s%7d" "$uniqRef: " "[sizeof [get_cells $AllRemReg -filter @ref_name=~$uniqRef]]"]
    
    }
    
    close $OutSum
    
    set OutExp  [open rpts/FxSynthesize/AllRegException.rpt w]
    
    
    puts $OutExp "## Exception List\n######################################################"
    puts $OutExp "EdgeTriggered : not\(hdmsfqxss*|hdhsmsfqxss*|hdhsusmsfqxss*|hdfqbxss*\)"
    puts $OutExp "LevelSensitive: not\(hdlaqnsxss*|hdlbqnsxss*|hdrlbqnsxss*|hdquadlbqns2vxss*\)"
    puts $OutExp "######################################################\n"
    
    foreach uniqRef [lsearch -regexp -all -inline -not [MakeRefList $AllEtReg] "hdmsfqxss*|hdhsmsfqxss*|hdhsusmsfqxss*|hdfqbxss*"] {
        
        puts $OutExp "\n######################################################\n## Instance Names @$uniqRef\n######################################################"
        if {[string match "hdrsmsfqxss*" $uniqRef]} {
            if {[sizeof [get_cells -hier -filter "ref_name=~hdrsmsfqxss*&&full_name!~tile_dfx/*"]]} {
                #puts "$uniqRef: [sizeof [get_cells $AllEtReg -filter @ref_name==$uniqRef]]"
                PrintColl [get_cells $AllEtReg -filter @ref_name=~$uniqRef] $OutExp
            } else {
                puts $OutExp "All hdrsmsfqxss* cells are inside tile_dfx hierarchy"
            }
        } else {
            #puts "$uniqRef: [sizeof [get_cells $AllEtReg -filter @ref_name==$uniqRef]]"
            PrintColl [get_cells $AllEtReg -filter @ref_name=~$uniqRef] $OutExp
        }
    
    }
    
    foreach uniqRef [lsearch -regexp -all -inline -not [MakeRefList $AllLsReg] "hdlaqnsxss*|hdlbqnsxss*|hdrlbqnsxss*|hdquadlbqns2vxss*"] {
        
        puts $OutExp "\n######################################################\n## Instance Names @$uniqRef\n######################################################"
        #puts "$uniqRef: [sizeof [get_cells $AllLsReg -filter @ref_name==$uniqRef]]"
        PrintColl [get_cells $AllLsReg -filter @ref_name=~$uniqRef] $OutExp
    }
    
    close $OutExp
    sh gzip -f rpts/FxSynthesize/AllRegException.rpt rpts/FxSynthesize/AllRegSummary.rpt
}

proc generate_PathGraph_data {} {
    ## Author: Umesh Chejara ##
    ## Date: 01/31/2021 ##
    ## Generate data for graphs for critical paths similar to Cores##


    #update_timing

    redirect /dev/null { set TimPaths [get_timing_paths -delay_type max -slack_lesser_than 0.0  -from [all_registers] -to [all_registers] -max_paths 20000] }

    ######################################################
    ###### DSlack Data ###################################
    if {[info exists dSlackData]} {unset dSlackData}
    if {[info exists dLolData]} {unset dLolData}

    set clkPeriod 0

    foreach_in_collection mPath $TimPaths {
       set slack [get_attribute $mPath slack]
       set clkPeriod [get_attribute $mPath startpoint_clock_period]

       set wSlack $slack
       set nwSlack [expr (round($wSlack/5.0))*5]  
       if {[info exists dSlackData] && [dict exists $dSlackData $nwSlack]} {
           dict set dSlackData $nwSlack [expr [dict get $dSlackData $nwSlack]+1]
       } else {
           dict set dSlackData $nwSlack 1
       }

       set mPoints [get_attribute $mPath points] 
       set numPoints [sizeof $mPoints]
       set nwLol [expr (round($numPoints/2.0))*1]
       if {[info exists dLolData] && [dict exists $dLolData $nwLol]} {
           dict set dLolData $nwLol [expr [dict get $dLolData $nwLol]+1]
       } else {
           dict set dLolData $nwLol 1
       }

       set aSlack [expr (round($slack))]
       set aLol $nwLol
       if {[info exists aData] && [dict exists $aData $aSlack]} {
           dict set aData $aSlack numPath [expr [dict get $aData $aSlack numPath]+1]
           set tLol [dict get $aData $aSlack Lol]
           dict set aData $aSlack Lol [expr $tLol+$aLol]
       } else {
           dict set aData $aSlack numPath 1
           dict set aData $aSlack Lol $aLol
       }

    }

    ###########
    if {![info exists dSlackData]} {
        dict set dSlackData 5 0
    }

    echo "DSlack, Num of Paths, Cumulative #of Paths\n" > rpts/FxSynthesize/dPathSlack.csv
    set sumPaths 0
    redirect -append rpts/FxSynthesize/dPathSlack.csv {
        foreach tkey [lsort -integer -increasing [dict keys $dSlackData]] {
            set numPaths [dict get $dSlackData $tkey]
            set sumPaths [expr $sumPaths+$numPaths]
            puts "$tkey, $numPaths, $sumPaths, "
        }
    }

    ###########
    if {![info exists dLolData]} {
        dict set dLolData 25 1
    }
    echo "DLOL, Num of Paths, Cumulative #of Paths\n" > rpts/FxSynthesize/dPathLOL.csv
    set sumPaths 0
    redirect -append rpts/FxSynthesize/dPathLOL.csv {
      foreach tkey [lsort -integer -increasing [dict keys $dLolData]] {
        set numPaths [dict get $dLolData $tkey]
        set sumPaths [expr $sumPaths+$numPaths]
        puts "$tkey, $numPaths, $sumPaths, "
      }
    }


    ####
    set pCnt 0
    set pLOL 0
    set p100F 0
    set p500F 0
    set p1000F 0
    set p2000F 0
    set p5000F 0

    set LOL100 0
    set LOL500 0
    set LOL1000 0
    set LOL2000 0
    set LOL5000 0

      foreach tkey [lsort -integer -increasing [dict keys $aData]] {
        set tCnt [dict get $aData $tkey numPath]
        set pCnt [expr $pCnt + $tCnt]
        set tLOL [dict get $aData $tkey Lol]
        set pLOL [expr $pLOL + $tLOL]
        if {$p100F==0 && $pCnt>=100} {
           set p100F $pCnt
           set LOL100 [expr round($pLOL/$pCnt)]
           set pLOL  0
        } elseif {$p500F==0 && $pCnt>=500} {
           set p500F $pCnt
           set LOL500 [expr round($pLOL/($pCnt-$p100F))]
           set pLOL  0
        } elseif {$p1000F==0 && $pCnt>=1000} {
           set p1000F $pCnt
           set LOL1000 [expr round($pLOL/($pCnt-$p500F))]
           set pLOL  0
        } elseif {$p2000F==0 && $pCnt>=2000} {
           set p2000F $pCnt
           set LOL2000 [expr round($pLOL/($pCnt-$p1000F))]
           set pLOL  0
        } elseif {$p5000F==0 && $pCnt>=5000} {
           set p5000F $pCnt
           set LOL5000 [expr round($pLOL/($pCnt-$p2000F))]
           set pLOL  0
        }
      }
           
    redirect -append rpts/FxSynthesize/dPathStat.csv {
      puts "PathCnt, 100th, 500th, 1000th, 2000th, 5000th, "
      puts "LOL, $LOL100, $LOL500, $LOL1000, $LOL2000, $LOL5000, \n\n\n  "
    }

    ####
    set pCnt 0
    set pLOL 0
    set p102F 0
    set p105F 0
    set p110F 0
    set p120F 0
    set p130F 0
    set pg130F 0
    set pLast 0

    set LOL102 0
    set LOL105 0
    set LOL110 0
    set LOL120 0
    set LOL130 0
    set LOLg130 0
    
    echo "Clock period: $clkPeriod\n"
    set c102 [expr $clkPeriod*0.02]
    set c105 [expr $clkPeriod*0.05]
    set c110 [expr $clkPeriod*0.10]
    set c120 [expr $clkPeriod*0.20]
    set c130 [expr $clkPeriod*0.30]

      foreach tkey [lsort -integer -increasing [dict keys $aData]] {
        set tSlk [expr abs($tkey)]

        if {$pg130F==0&&($pCnt>$pLast)&&$tSlk<=$c130}  {
           set pg130F $pCnt
           set LOLg130 [expr round($pLOL/($pg130F))]
           set pLOL  0
           set pLast $pCnt
        } elseif {$p130F==0&&($pCnt>$pLast)&&$tSlk<=$c120} {
           set p130F [expr $pCnt-$pLast]
           set LOL130 [expr round($pLOL/($p130F))]
           set pLOL  0
           set pLast $pCnt
        } elseif {$p120F==0&&($pCnt>$pLast)&&$tSlk<=$c110} {
           set p120F [expr $pCnt-$pLast]
           set LOL120 [expr round($pLOL/($p120F))]
           set pLOL  0
           set pLast $pCnt
        } elseif {$p110F==0&&($pCnt>$pLast)&&$tSlk<=$c105} {
           set p110F [expr $pCnt-$pLast]
           set LOL110 [expr round($pLOL/($p110F))]
           set pLOL  0
           set pLast $pCnt
        } elseif {$p105F==0&&($pCnt>$pLast)&&$tSlk<=$c102} {
           set p105F [expr $pCnt-$pLast]
           set LOL105 [expr round($pLOL/($p105F))]
           set pLOL  0
           set pLast $pCnt
        } 

        set tCnt [dict get $aData $tkey numPath]
        set pCnt [expr $pCnt + $tCnt]
        set tLOL [dict get $aData $tkey Lol]
        set pLOL [expr $pLOL + $tLOL]
      }

      if {$pCnt>$pLast} {
         set p102F [expr $pCnt-$pLast]
         set LOL102 [expr round($pLOL/($p102F))]
      }

           
    redirect -append rpts/FxSynthesize/dPathStat.csv {
      puts "Freq, 100-102%, 102-105%, 105-110%, 110-120%, 120-130%, >130%, "
      puts "NumPaths, $p102F, $p105F, $p110F, $p120F, $p130F, $pg130F, "
      puts "LOL, $LOL102, $LOL105, $LOL110, $LOL120, $LOL130, $LOLg130, \n\n\n  "
    }


  sh gzip -f rpts/FxSynthesize/dPathLOL.csv rpts/FxSynthesize/dPathSlack.csv
}

# Author: Christopher Stites (chris.stites@amd.com)
# Date: 2/1/17
# Version: 1.01
#
# Description: Commands run within a native TCL 'if' statement are not echo-ed
#   to the console. Consequently, one can never be certain that code within an
#   'if' statement was executed without adding echo commands to the end of the
#   'if' block. Also, when errors are through, the error message is outputted
#   but not the command that threw the error. And depending on the error type,
#   it might cause the 'if' statement to stop executing lines within the 'if'
#   block.
#
#   This function stands for 'fixed if' statement. It will execute each
#   command along with the return value for each command within the 'if' block.
#   Also, the commands are executed in a way such that the block will not stop
#   execution if an error is encountered.
#
# Future upgrades:
# - Right now, the files to source are being put in the current directory
#   that the script is in. This can be problematic if there is a change
#   dir command. Therefore, we should put all the files for execution in
#   the same directory (I think; it might also prove not to be a problem).
# - There is no syntax checking to make sure that the correct empty word
#   is in the correct position.
#       So we can have an: "if .. else .. else" statement and it wouldn't
#       trigger an error message
#
# Finished Upgrades:
# - (1.01 - 2/23/17) Using 'fif' inside a loop with a continue statement causes the continue to
#   fail
proc fif {args} {
    # Variables
    global dfFeintFifEvalDir
    global dfFeintFifStackNum

    # Note: The arguments must be put in the global scope (until I can think
    #   of a better way to do this) because when we run uplevel 1, that puts
    #   the variable scope up one level. Our argument string would be in the
    #   local context, so the string wouldn't be found. If we didn't do the
    #   uplevel command, then the expression to evaluate would be at the
    #   wrong level (catch 22)
    global dfFeintFifArg
    
    # We are in the 'fif' block, so increment the counter
    # This is used to have multiple files for execution
    # when we have nested fif statements
    incr dfFeintFifStackNum

    # Keep track of the return code and return value. These will be used to
    # return the value of the last line of code run in the 'fif' statement.
    # It returns "" if nothing executed.
    # The code will be used to continue or break loops at higher levels.
    set retValue ""
    set retCode 0
    
    if {[catch {
        # Get the number of arguments
        set nArgs [llength $args]
        set nArgsm1 [expr $nArgs - 1]
        
        # Set the initial state
        # 0 - Look for conditional expression
        # 1 - Run TCL code
        # 2 - Skip this iteration (conditional was false)
        set state 0

        # Get filename
        set strFifFilename [join [list "fifEval" $dfFeintFifStackNum ".tcl"] ""]

        # Loop through each argument
        for {set idx 0} {$idx<$nArgs} {incr idx} {

            # The conditional returned false, so skip this iteration.
            # Next iteration will be a conditional again.
            if {$state == 2} {
                set state 0
                continue
            }
            
            # Get the argument
            set dfFeintFifArg [lindex $args $idx]
            #echo "echo: " $dfFeintFifArg

            # Skip empty words
            if {$dfFeintFifArg == "then"} continue
            if {$dfFeintFifArg == "else"} continue
            if {$dfFeintFifArg == "elseif"} continue

            # If this is the last argument
            if {$idx == $nArgsm1} { set state 1 }

            if {$state == 0} {
                # Look for conditional execution
                if {[uplevel 1 {global dfFeintFifArg; expr "$dfFeintFifArg"}]} {
                    set state 1
                } else {
                    set state 2
                }
            } elseif {$state == 1} {
                # Write TCL to a file
                set fp [open $strFifFilename w+]
                puts $fp $dfFeintFifArg
                close $fp

                # Use the source command to echo commands and return values
                # Also, suppress "continue" and "break" warnings
                uplevel #0 lappend suppress_errors "CMD-021"
                set retCode [catch {uplevel 1 source -echo -verbose -continue_on_error $strFifFilename} retValue]
                uplevel #0 {set suppress_errors [lrange $suppress_errors 0 [expr [llength $suppress_errors] - 2]]}

                # Delete the temporary file
                file delete $strFifFilename

                # Once one of the if branches are taken, all of branches are out
                break
            }
        }
    } fifMsg] == 1} {
        #echo "Error: fif statement has encountered an error. Handling harshly and exiting ..."
        #exit 0
        echo $fifMsg
        echo "Error: fif statement has encountered an error. Please debug ..."
        return 0
    }
    
    # We are finished with the fif, so decrement the counter
    incr dfFeintFifStackNum -1

    if {$retCode == 3} {
        # Pass 'break' up
        return -code 3 -level 1
    } elseif {$retCode == 4} {
        # Pass 'continue' up
        return -code 4 -level 1
    } else {
        # Return last executed statement
        return $retValue
    }
}

define_proc_attributes fif -info \
"This script is a replacement for the TCL 'if' statement ('fif'
stands for 'fixed if' When you wrap commands in the TCL if, they
are not echo-ed to stdout. This function will make sure that all
commands are echo-ed as well as the return result. It also makes
sure that the 'if' body doesn't exit when an error occurs (it
continues running the rest of the body)."


proc df_feint_report_lol {} {
   ## Author: Umesh Chejara ##
   ## Date: 12/16/2019 ##
   ## Generate LOL report ##
   
   ##Updated by pnunna to report IO paths - 04/07
   
   suppress_message {UID-606 UIC-040}
   #CN Sometime TARGET_NAME is used in Syn.Constraints.sdc
   global TARGET_NAME
#CN   if {[file exists tune/FxSynthesize/FxSynthesize.I2Place.Constraints.sdc]} {
#CN       sh cp -f tune/FxSynthesize/FxSynthesize.I2Place.Constraints.sdc tune/FxSynthesize/FxSynthesize.I2Place.Constraints32.sdc
#CN       sh perl -pi -e 's/set CLOCK_PERIOD\\(FCLK\\).*/set CLOCK_PERIOD\\(FCLK\\) 32/' tune/FxSynthesize/FxSynthesize.I2Place.Constraints32.sdc
#CN       sh perl -pi -e 's/set CLOCK_PERIOD\\(UCLK\\).*/set CLOCK_PERIOD\\(UCLK\\) 32/' tune/FxSynthesize/FxSynthesize.I2Place.Constraints32.sdc
#CN       sh perl -pi -e 's/set CLOCK_PERIOD\\(MCD_FCLK\\).*/set CLOCK_PERIOD\\(MCD_FCLK\\) 32/' tune/FxSynthesize/FxSynthesize.I2Place.Constraints32.sdc
#CN       source tune/FxSynthesize/FxSynthesize.I2Place.Constraints32.sdc
#CN   }
   if {[file exists tune/FxSynthesize/Syn.Constraints.sdc]} {
       sh cp -f tune/FxSynthesize/Syn.Constraints.sdc tune/FxSynthesize/Syn.Constraints32.sdc
       sh perl -pi -e 's/set CLOCK_PERIOD\\(FCLK\\).*/set CLOCK_PERIOD\\(FCLK\\) 32/' tune/FxSynthesize/Syn.Constraints32.sdc
       sh perl -pi -e 's/set CLOCK_PERIOD\\(UCLK\\).*/set CLOCK_PERIOD\\(UCLK\\) 32/' tune/FxSynthesize/Syn.Constraints32.sdc
       sh perl -pi -e 's/set CLOCK_PERIOD\\(MCD_FCLK\\).*/set CLOCK_PERIOD\\(MCD_FCLK\\) 32/' tune/FxSynthesize/Syn.Constraints32.sdc
       #CN $P(SYN_TIMING_MODE) is used inside Syn.Constraints.sdc to decide if DFfeint constraints are overwriting chip-level constraints.
       global P
       source tune/FxSynthesize/Syn.Constraints32.sdc
   } else {
       error "FCLK definition couldn't be found. Please check that its defined in tune/FxSynthesize/Syn.Constraints.sdc"
   }
   remove_clock_uncertainty [all_clocks]
   remove_clock_uncertainty -from [all_clocks] -to [all_clocks]
   
   set clocks [filter_collection [all_clocks] "full_name!~*FCLK*"]
   set clocks [filter_collection $clocks "full_name!~*UCLK*"]
   set clocks [filter_collection $clocks "full_name!~*UMCCLK*"]
   set clocks [filter_collection $clocks "full_name!~*MCLK*"]
   set clocks [filter_collection $clocks "full_name!~*HCLK*"]
   set clocks [filter_collection $clocks "full_name!~*DFICLK*"]
   if {[sizeof $clocks]>0} { remove_clock $clocks }
   
   # Redefine clocks which should have been redefined in FxSynthesize.I2Place.Constraints32.sdc above
   foreach_in_col clk [get_clocks] {
      set src [get_att -quiet $clk sources]
      set prd 32
      set nme [get_att -quiet $clk name]
      if { [sizeof_col $src]==0 } { create_clock -name $nme -period $prd -waveform "0 [expr $prd/2]"
      } else {                      create_clock -name $nme -period $prd -waveform "0 [expr $prd/2]" $src }
   }

   reset_timing_derate
   set_ideal_network -no_propagate [get_nets -hierarchical *]
   set_pocvm_corner_sigma 0
   
#CN   # Add a unit delay on all of the standard cells
#CN   set myInstances [get_cells -hierarchical * -filter @is_hierarchical==false]
#CN   foreach_in_collection instance $myInstances {
#CN      set myInPins [get_pins -of_objects $instance -filter @pin_direction==in&&@name!=VSS&&@name!=VDD&&@name!=VBP&&@name!=VBN]
#CN      set myOutPins [get_pins -of_objects $instance -filter @pin_direction==out]
#CN      set_annotated_delay -cell 1.00 -from $myInPins -to $myOutPins
#CN   }   
   # Add a unit delay on all of the comb cells (skip comb clock cells like CKNR2D2AMDBWP143M169H3P48CPD which are defined as seq ICGs)
   set myInstances [get_cells -quiet -hierarchical -filter !is_hierarchical&&!is_sequential]
   foreach_in_collection instance $myInstances {
      #set myInPins [get_pins -of_objects $instance -filter @pin_direction==in&&@name!=VSS&&@name!=VDD&&@name!=VBP&&@name!=VBN]
      set myInPins  [get_pins -of_objects $instance -filter pin_direction=="in"&&port_type=="signal"]
      set myOutPins [get_pins -of_objects $instance -filter pin_direction=="out"]
      #Tie-off cells & other physical cells need to be excluded as they might not have inputs.
      if { [sizeof_collection $myInPins] != 0 && [sizeof_collection $myOutPins] != 0} {
         #set_annotated_delay -cell 1.00 -from $myInPins -to $myOutPins
         #To avoid warning about missing timing arcs of some "multi-bit one-hot muxes" in the library.
         foreach_in_col myInPin $myInPins {
            foreach_in_col myOutPin $myOutPins {
               if [sizeof_col [get_timing_arcs -quiet -from $myInPin -to $myOutPin]] { set_annotated_delay -cell 1.00 -from $myInPin -to $myOutPin }
            }
         }
      }
   }
   # Add a unit delay on all of the seq cells' async-inputs to output timing arc 
   set myInstances [get_cells -quiet -hierarchical -filter !is_hierarchical&&is_sequential]
   foreach_in_collection instance $myInstances {
      #set myInPins [get_pins -of_objects $instance -filter @pin_direction==in&&@name!=VSS&&@name!=VDD&&@name!=VBP&&@name!=VBN]
      set myInPins [get_pins -of_objects $instance -filter pin_direction=="in"&&port_type=="signal"&&(is_async_pin||lib_pin.is_async_pin||lib_pin.is_clock_pin||is_clock_pin||is_clock_gating_clock||is_clock_used_as_clock)]
      set myOutPins [get_pins -of_objects $instance -filter pin_direction=="out"]
      if [sizeof_col $myInPins] { set_annotated_delay -cell 1.00 -from $myInPins -to $myOutPins }
   }   

   # Add a unit setup delay to the flops (FF & latches & ICG; excluding async inputs: Warning: There is no 'setup' check arc between pins 'ncm_pg/FtiRdRspDatBuf07/I_d0nt_sse_en_X/CP' and 'ncm_pg/FtiRdRspDatBuf07/I_d0nt_sse_en_X/CDN'.)
   set setupCells [get_cells -quiet -hierarchical -filter !is_hierarchical&&is_sequential]
   #remove_output_delay [get_pins -of_objects $setupCells -filter @pin_direction==in&&@name!=CLK&&@name!=CK&&@name!=CP]
   remove_output_delay [get_pins -of_objects $setupCells -filter pin_direction=="in"&&(!lib_pin.is_clock_pin&&!is_clock_pin&&!is_clock_gating_clock&&!is_clock_used_as_clock)]
   foreach_in_collection mCell $setupCells {
      #set mClkPins [get_pins -of_objects $mCell -filter @pin_direction==in&&(@name==CLK||@name==CK||@name==CP)]
      set mClkPins  [get_pins -of_objects $mCell -filter pin_direction=="in"&&(lib_pin.is_clock_pin||is_clock_pin||is_clock_gating_clock||is_clock_used_as_clock)]
      #set mDataPins [get_pins -of_objects $mCell -filter @pin_direction==in&&@name!=CLK&&@name!=CK&&name!=CP]
      set mDataPins  [get_pins -of_objects $mCell -filter pin_direction=="in"&&port_type=="signal"&&(!lib_pin.is_clock_pin&&!is_clock_pin&&!lib_pin.is_async_pin&&!is_async_pin&&!is_clock_gating_clock&&!is_clock_used_as_clock)]
#     There is no setup check timing arc befween gate and "mux's output selection of AOI seq cell".
#                 N6:        |N5          |N5/N3:
      if [regexp {LDPQM8AOI22|MB8LHQ2AOI22|MB8LHQAOI22} [get_attribute $mCell ref_name]] { set mDataPins [remove_from_col $mDataPins [get_pins -phys -of $mCell -filter name=="S0"||name=="S1"]] }
      if { [sizeof_collection $mClkPins] != 0 && [sizeof_collection $mDataPins] != 0} {    set_annotated_check -setup -from $mClkPins -to $mDataPins 1 }
   }
   
   #
   unset -nocomplain sid sod
   update_timing -full
   foreach_in_col p [remove_from_col [get_ports -filter port_direction=="in"&&port_type=="signal"] [get_ports -quiet [get_att -quiet [get_clocks] sources]]] {
      set arrW [get_att $p arrival_window]
      set first 1
      foreach c [lindex $arrW 0] {
         set clk [lindex $c 0] ; set edge [lindex $c 1]
         if { $clk=="" } { set clk [lindex [get_att -quiet [get_clocks] name] 0] }
                      set cmd "set_input_delay -clock $clk"
         if {$edge=="neg_edge"} { append cmd " -clock_fall" }
         if {$first} { set first 0
         } else {                 append cmd " -add_delay" }
                                  append cmd " 0.0 [get_att $p name]"
         lappend sid $cmd
      }
   }
   foreach_in_col p [get_ports -filter port_direction=="out"&&port_type=="signal"] {
      set arrW [get_att $p arrival_window]
      set first 1
      foreach c [lindex $arrW 0] {
         set clk [lindex $c 0] ;     set edge [lindex $c 1]
         if { $clk=="" } { set clk [lindex [get_att [get_att -quiet [get_clocks] sources] name] 0] }
                      set cmd "set_output_delay -clock $clk"
         if {$edge=="neg_edge"} { append cmd " -clock_fall" }
         if {$first} { set first 0
         } else {                 append cmd " -add_delay" }
                                  append cmd " 0.0 [get_att $p name]"
         lappend sod $cmd
      }
   }
   foreach cmd $sid { eval $cmd }
   foreach cmd $sod { eval $cmd }

   # Put a larger setup on the clock gaters to account for clock tree expansion
   #CN set_clock_gating_check -setup 4 [get_cells -hierarchical * -filter is_integrated_clock_gating_cell&&!is_hierarchical]
   set ICGs [get_cells -quiet -hierarchical -filter is_integrated_clock_gating_cell&&!is_hierarchical&&full_name!~"*I_d0nt_ck*"]
   if [sizeof_col $ICGs] { set_clock_gating_check -setup 4 $ICGs }
   
   # Put a larger setup on the half-cycle gaters in the latch arrays, but make it half the delay of the full-cycle paths. 
   #CN set_clock_gating_check -setup 2 [get_cells -hierarchical * -filter @full_name=~*I_d0nt_ck*]
   set d0ntCKs [get_cells -quiet -hierarchical -filter is_integrated_clock_gating_cell&&!is_hierarchical&&full_name=~"*I_d0nt_ck*"] 
   if [sizeof_col $d0ntCKs] { set_clock_gating_check -setup 2 $d0ntCKs }
   
   # Generate the full LOL timing report
   report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 > rpts/FxSynthesize/report_LOL.rpt
   
   # Generate another report for the half-cycle paths so we can track seperately 
   report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -rise_from [get_clocks] -fall_to [get_clocks] > rpts/FxSynthesize/report_LOL_halfCycleA.rpt
  
   # Generate another report for the half-cycle paths so we can track seperately 
   report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -fall_from [get_clocks] -rise_to [get_clocks] > rpts/FxSynthesize/report_LOL_halfCycleB.rpt
   
   # Generate yet another report for the clock enables paths so we can track that seperately as well. 
   report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -through [get_pins -of_object [get_cells -hierarchical * -filter (@is_integrated_clock_gating_cell==true)] -filter port_type=="signal"] > rpts/FxSynthesize/report_LOL_gater.rpt
   
   # Generate reg2reg paths separately
   set allSeq [get_cells -quiet -hier -filter is_sequential&&!is_integrated_clock_gating_cell]
   set allLat [get_cells -quiet -hier -filter is_sequential&&!is_integrated_clock_gating_cell&&(is_positive_level_sensitive||is_negative_level_sensitive)]
   set allFF  [get_cells -quiet -hier -filter is_sequential&&!is_integrated_clock_gating_cell&&(is_rise_edge_triggered||is_fall_edge_triggered)]
   #
   if [sizeof_col $allFF] {
      report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from $allFF -to $allFF > rpts/FxSynthesize/report_LOL_reg2reg.rpt
      report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from $allFF -to [get_ports -filter port_direction=="out"&&defined(net)] > rpts/FxSynthesize/report_LOL_reg2out.rpt
      report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from [remove_from_col [get_ports -filter port_direction=="in"&&defined(net)] [get_att [get_clocks] sources]] \
                                                                                                                  -to $allFF > rpts/FxSynthesize/report_LOL_in2reg.rpt
   }
   if {[sizeof_col $allFF] && [sizeof_col $allLat]} {
      report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from $allFF -to $allLat > rpts/FxSynthesize/report_LOL_reg2lat.rpt
      report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from $allLat -to $allFF > rpts/FxSynthesize/report_LOL_lat2reg.rpt
   }
   if [sizeof_col $allLat] {
      report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from $allLat -to $allLat > rpts/FxSynthesize/report_LOL_lat2lat.rpt
      report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from $allLat -to [get_ports -filter port_direction=="out"&&defined(net)] > rpts/FxSynthesize/report_LOL_lat2out.rpt
      report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from [remove_from_col [get_ports -filter port_direction=="in"&&defined(net)] [get_att [get_clocks] sources]] \
                                                                                                                  -to $allLat > rpts/FxSynthesize/report_LOL_in2lat.rpt
   }
   #
   report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 -from [remove_from_col [get_ports -filter port_direction=="in"&&defined(net)] [get_att [get_clocks] sources]] \
                                                                                                               -to [get_ports -filter port_direction=="out"&&defined(net)] > rpts/FxSynthesize/report_LOL_in2out.rpt

   redirect -file rpts/FxSynthesize/FxSynthesize.LOL.proc_qor.rpt {proc_qor} 
   
   # Get the worst slack from each group
   redirect /dev/null { set WorstHalfCyclePathSlackA [get_timing_paths -nworst 1 -max_paths 1 -rise_from [get_clocks] -fall_to [get_clocks]] }
   redirect /dev/null { set WorstHalfCyclePathSlackB [get_timing_paths -nworst 1 -max_paths 1 -fall_from [get_clocks] -rise_to [get_clocks]] }
   redirect /dev/null { set WorstGaterPathSlack [get_timing_paths -nworst 1 -max_paths 1 -through [get_pins -of_object [get_cells -hierarchical * -filter @is_integrated_clock_gating_cell==true] -filter port_type=="signal"]] }
   
   # Some tiles don't have a latch array, so they don't have half-cycle paths. In that case, they will show 99 as LOL WNS. 
   set worstSlack 99
   foreach_in_collection path $WorstHalfCyclePathSlackA {
      set getSlack [get_attribute $path slack]
      if {$getSlack < $worstSlack} {
         set worstSlack $getSlack
      }   
   }
   echo "Worst A-phase half-cycle path slack: $worstSlack" >> rpts/FxSynthesize/FxSynthesize.LOL.proc_qor.rpt
   
   set worstSlack 99
   foreach_in_collection path $WorstHalfCyclePathSlackB {
      set getSlack [get_attribute $path slack]
      if {$getSlack < $worstSlack} {
         set worstSlack $getSlack
      }   
   }
   echo "Worst B-phase half-cycle path slack: $worstSlack" >> rpts/FxSynthesize/FxSynthesize.LOL.proc_qor.rpt
   
   set worstSlack 99
   foreach_in_collection path $WorstGaterPathSlack {
      set getSlack [get_attribute $path slack]
      if {$getSlack < $worstSlack} {
         set worstSlack $getSlack
      }   
   }
   echo "Worst gater enable path slack: $worstSlack" >> rpts/FxSynthesize/FxSynthesize.LOL.proc_qor.rpt
   sh gzip -f rpts/FxSynthesize/FxSynthesize.LOL.proc_qor.rpt
   
   ##Generate LOL without inv/buffer
   #set myInstances [get_cells -hierarchical * -filter @is_hierarchical!=true&&(@ref_name=~"*INVD*"||@ref_name=~"*BUFFD*"||@ref_name=~"*_INV_*"||@ref_name=~"*_BUF_*"||@ref_name=~"*hdinxss*"||@ref_name=~"*hdbfxss*")]
   set myInstances [get_cells -quiet -hierarchical * -filter !is_hierarchical&&(ref_block.is_buffer||ref_block.is_inverter)]
   foreach_in_collection instance $myInstances {
      set myInPins  [get_pins -of_objects $instance -filter pin_direction=="in"&&port_type=="signal"]
      set myOutPins [get_pins -of_objects $instance -filter pin_direction=="out"]
      set_annotated_delay -cell 0 -from $myInPins -to $myOutPins
   }   
   
   report_timing -include_hierarchical_pins -net -inp -nosplit -nworst 1 -max_paths 1000 -significant_digits 0 > rpts/FxSynthesize/report_LOL_NoBuf.rpt
   unsuppress_message {UID-606 UIC-040}
   sh gzip -f rpts/FxSynthesize/report_LOL*.rpt
}


proc umc_SRAM_comb {} {
   set flopLibCell [get_lib_cells ts06ncpvlogl08udl057f.TSMC6N.tt.rev1d0u2p1.100v.100c.TSMC6N_1P13M1X1XA1YA5Y2YY2Z1ALRDL/HDN6BULT08_FSDPSYNRBQ_V2Y2_1]
   set invLibCell [get_lib_cells ts06ncpvlogl08udl057f.TSMC6N.tt.rev1d0u2p1.100v.100c.TSMC6N_1P13M1X1XA1YA5Y2YY2Z1ALRDL/HDN6BULT08_INV_2]
   set SRAM [get_cells -hier * -filter "full_name=~*UMCSEC_*KEYS/AES*KEY_SRAM_*/mem_0_0/PDP*"]
   set SRAM_outputs [get_pins -of_objects [get_cells $SRAM] -filter "pin_name=~QB*"]
   remove_buffer_tree -from [get_pins $SRAM_outputs]
   set NR2gates ""
   foreach_in_collection output $SRAM_outputs {
      append_to_collection -unique  NR2gates [get_cells -o_objects [get_pins -of_objects [get_nets -of_objects [get_pins $output] ] -leaf -f "direction==in"]]
      #echo [get_attr [get_cells -of_objects [get_pins -of_objects [get_nets -of_objects [get_pins $output] ] -leaf -f "direction==in"]] ref_name]
      #echo [get_attr [get_cells -of_objects [get_pins -of_objects [get_nets -of_objects [get_pins -of_objects [get_cells -of_objects [get_pins -of_objects [get_nets -of_objects [get_pins $output] ] -leaf -f "direction==in"]] -f "direction==out"]] -f "direction==in"]] ref_name]
   }
   set NR2output [get_pins -of_objects [get_cells $NR2gates] -fil "pin_direction==out"]
   remove_buffer_tree -from [get_pins $NR2output]
   foreach_in_collection output $SRAM_outputs {
      # Get the NR gate and DFF
      set celNR [get_cells -of_objects [get_pins -of_objects [get_nets -of_objects [get_pins $output] ] -leaf -f "direction==in"]]
      set strNR [get_object_name $celNR]
      if { ![regexp NR2B [get_attr $celNR ref_name]] } {
         puts "Debug, something is different with Qpin $output"
         break
      }
      set celDFF [get_cells -of_objects [get_pins -of_objects [get_nets -of_objects [get_pins -of_objects [get_cells -of_objects [get_pins -of_objects [get_nets -of_objects [get_pins $output] ] -leaf -f "direction==in"]] -f "direction==out"]] -f "direction==in"]]
      set strDFF [get_object_name $celDFF]
      # Get all the nets connected
      set netNR_A [get_nets -of_objects [get_pins -of_objects [get_cells $celNR] -f "pin_name==A"]]
      set netNR_B [get_nets -of_objects [get_pins -of_objects [get_cells $celNR] -f "pin_name==B"]]
      set netDFF_Q [get_nets -of_objects [get_pins -of_objects [get_cells $celDFF] -f "pin_name==Q"]]
      set netDFF_SI [get_nets -of_objects [get_pins -of_objects [get_cells $celDFF] -f "pin_name==SI"]]
      set netDFF_SE [get_nets -of_objects [get_pins -of_objects [get_cells $celDFF] -f "pin_name==SE"]]
      set netDFF_CK [get_nets -of_objects [get_pins -of_objects [get_cells $celDFF] -f "pin_name==CK"]]
      # Disconnect the nets from the NR and DFF
      disconnect_net [get_nets $netNR_A] [get_pins -of_objects [get_cells $celNR] -f "pin_name==A"]
      disconnect_net [get_nets $netNR_B] [get_pins -of_objects [get_cells $celNR] -f "pin_name==B"]
      disconnect_net [get_nets $netDFF_Q] [get_pins -of_objects [get_cells $celDFF] -f "pin_name==Q"]
      disconnect_net [get_nets $netDFF_SI] [get_pins -of_objects [get_cells $celDFF] -f "pin_name==SI"]
      disconnect_net [get_nets $netDFF_SE] [get_pins -of_objects [get_cells $celDFF] -f "pin_name==SE"]
      disconnect_net [get_nets $netDFF_CK] [get_pins -of_objects [get_cells $celDFF] -f "pin_name==CK"]
      # Create cell SyncReset Flop
      remove_cell [get_cells [list $strDFF $strNR] ]
      create_cell $strDFF $flopLibCell
      set strReset "${strDFF}_ResetBar"
      create_cell $strReset $invLibCell
      # Connect SynReset flop pins to prev nets
      connect_pin -from [get_pins -of_objects [get_cells $strReset] -f "pin_name==X"] -to [get_pins -of_objects [get_cells $strDFF] -f "pin_name==RD"]
      connect_net [get_nets $netNR_A] [get_pins -of_objects [get_cells $strDFF] -f "pin_name==D"]
      connect_net [get_nets $netNR_B] [get_pins -of_objects [get_cells $strReset] -f "pin_name==A"]
      connect_net [get_nets $netDFF_Q] [get_pins -of_objects [get_cells $strDFF] -f "pin_name==Q"]
      connect_net [get_nets $netDFF_SI] [get_pins -of_objects [get_cells $strDFF] -f "pin_name==SI"]
      connect_net [get_nets $netDFF_SE] [get_pins -of_objects [get_cells $strDFF] -f "pin_name==SE"]
      connect_net [get_nets $netDFF_CK] [get_pins -of_objects [get_cells $strDFF] -f "pin_name==CK"]
   }
}


###########
#Catalin.Nechita@amd.com
### Report per site-row utilization - used in df_feint_report_timing
proc df_feint_rptUtilizationN3 { } {
   set ra117 0.0000 ; set ra169 0.0000
   set ca117 0.0000 ; set ca169 0.0000
   foreach_in_col r [get_site_rows -filter site_name=="unitW48M143H117"] {
      set ra117 [expr $ra117 + ([lindex [get_att $r bbox] 1 0]-[lindex [get_att $r bbox] 0 0]) * ([lindex [get_att $r bbox] 1 1]-[lindex [get_att $r bbox] 0 1])]
   }
   foreach_in_col r [get_site_rows -filter site_name=="unitW48M143H169"] {
      set ra169 [expr $ra169 + ([lindex [get_att $r bbox] 1 0]-[lindex [get_att $r bbox] 0 0]) * ([lindex [get_att $r bbox] 1 1]-[lindex [get_att $r bbox] 0 1])]
   }

   set allCells [get_cells -phys -hier]
   set cells [filter_col $allCells @ref_phys_block.site_name=~"*W48M143H117"] ; set allCells [remove_from_col $allCells $cells]
   foreach_in_col c $cells {
      if { [get_att $c height]>0.117 } { puts "Error(utilization): Cell [get_att $c name] has [get_att $c height] instead of 0.117!" }
      set ca117 [expr $ca117+[get_att $c area]]
   }
   set cells [filter_col $allCells @ref_phys_block.site_name=~"*W48M143H169"] ; set allCells [remove_from_col $allCells $cells]
   foreach_in_col c $cells {
      if { [get_att $c height]>0.169 } { puts "Error(utilization): Cell [get_att $c name] has [get_att $c height] instead of 0.169!" }
      set ca169 [expr $ca169+[get_att $c area]]
   }
   set cells [filter_col $allCells @ref_phys_block.site_name=~"*W48M143H286"||@ref_phys_block.site_name=="unitW48M143H286MX"] ; set allCells [remove_from_col $allCells $cells]
   foreach_in_col c $cells {
      set m [expr [get_att $c height]/0.2860]
      if { [expr int($m)] < $m } { puts "Error(utilization): Cell [get_att $c name] is not multiple of site([get_att $c height])!" }
      set ca117 [expr $ca117+$m*[get_att $c width]*0.117]
      set ca169 [expr $ca169+$m*[get_att $c width]*0.169]
   }
   set cells [filter_col $allCells @ref_phys_block.site_name=~"*W48M143H403"] ; set allCells [remove_from_col $allCells $cells]
   foreach_in_col c $cells {
      if { [get_att $c height]>0.403 } { puts "Error(utilization): Cell [get_att $c name] has [get_att $c height] instead of 0.403!" }
      set ca117 [expr $ca117+2*[get_att $c area]]
      set ca169 [expr $ca169+[get_att $c area]]
   }
   set cells [filter_col $allCells @ref_phys_block.site_name=~"*W48M143H455"] ; set allCells [remove_from_col $allCells $cells]
   foreach_in_col c $cells {
      if { [get_att $c height]>0.455 } { puts "Error(utilization): Cell [get_att $c name] has [get_att $c height] instead of 0.455!" }
      set ca117 [expr $ca117+[get_att $c area]]
      set ca169 [expr $ca169+2*[get_att $c area]]
   }
   set cells [get_cells $allCells -filter !defined(ref_phys_block.site_name)] ; set allCells [remove_from_col $allCells $cells]
   foreach_in_col c $cells {
      set ca117 [expr $ca117+0.4091*[get_att $c area]]
      set ca169 [expr $ca169+0.5909*[get_att $c area]]
   }
   foreach_in_col c $allCells {
      set ca117 [expr $ca117+0.4091*[get_att $c area]]
      set ca169 [expr $ca169+0.5909*[get_att $c area]]
      puts "Warning(utilization): Cell [get_att $c name] has an unknown site [get_att $c ref_phys_block.site_name] - area distributed between 117&169 sites!"
   }
   puts "Site-row-117 utilization:  [format %.2f [expr $ca117*100/$ra117]]%"
   puts "Site-row-169 utilization:  [format %.2f [expr $ca169*100/$ra169]]%"
   puts "Site-row-286 utilization:  [format %.2f [expr ($ca117+$ca169)*100/($ra117+$ra169)]]%"
}
define_proc_attributes df_feint_rptUtilizationN3 \
  -info "Report cell-row/site-row based utilization for hybrid rows approach of N3."


### Report an array with busses from given port list/collection/pattern
proc getBusses { args } {
   parse_proc_arguments -args $args options
   foreach o [array name options] { set [string trimleft $o "-"] $options($o) }
   foreach_in_col p [get_ports $ports -filter full_name=~"*\[*"] {
      set n [lindex [split [get_att $p full_name] "\["] 0]
      lappend busses($n) [get_att $p full_name]
   }
   return [array get busses]
#array set bubu [getBusses [get_ports *]]
}
define_proc_attributes getBusses \
   -info "USER PROC: Return an array of busses from a ports selection" \
   -define_args {
        {-ports "List or collection or pattern of ports" "" string required}
   }
#  -command_group DF_FEINT


### Bank flip-flops(except enableFF, muxFF, sync S/R FF) which share the same bus, hirarchy and clock-net
proc createIO_multibit { args } {
   parse_proc_arguments -args $args options
   foreach o [array name options] { set [string trimleft $o "-"] $options($o) }
   if { ![info exists name] || $name == "" } { set name "ioMB" }
   if ![info exists sbLibCells] { set sbLibCells "" }
   if { [sizeof_col [get_ports $ports]] < 2 } { puts "Warning: (createIO_multibit) Minimum number of ports must be 2!" ; return -1 }

   suppress_message "SQM-1058 SQM-1061 SQM-1067"
   foreach lc $mbLibCells { if { [sizeof [get_lib_cells $lc]] > 1 } { puts "Error: (createIO_multibit) lib_cell $lc is not unique - please close extra libs!" ; return -1 }
                            lappend mbffLibCells "$lc [get_att [get_lib_cells $lc] multibit_width]" }
   set mbffLibCells [lsort -index 1 -integer -decr $mbffLibCells]
   set ioRegs ""

   # Collect IO-registers
   foreach_in_col p [get_ports $ports] {
      if { $pDir == "out" } { set cells [all_fanin  -quiet -flat -only_cells -to $p -startpoints_only] }
      if { $pDir == "in" } {  set cells [all_fanout -quiet -flat -only_cells -from $p -endpoints_only] }
      # Consider only single-bit-rising-edge-clock FFs
      set cells [get_cells -filter !is_integrated_clock_gating_cell&&is_rise_edge_triggered&&multibit_width<=1 $cells]
      # Consider only eligible FF paterns, if any
      if { $sbLibCells != "" } {
         unset -nocomplain tmpCells
         foreach patt $sbLibCells { append_to_col -uniq tmpCells [get_cells -filter ref_name=~$patt $cells] }
         set cells $tmpCells
      }
      # Ignore *Done* cells since they seems to come from a different ICG
      #set cells [get_cells -filter name!~"*Done*" $cells]
      # Ignore FFs w/ enable - no MBFF with enable in the library
      set cells [get_cells -filter ref_name!~"*EDF*" $cells]
      # Ignore FFs w/ asynchronous set/reset - To Be Implemented ...
      set cells [get_cells -filter ref_name!~"*DFNR*"&&ref_name!~"*DFNS*"&&ref_name!~"*DFR*"&&ref_name!~"*DFS*" $cells]
      # Ignore FFs w/ synchronous set/reset - no MBFF with synchronous set/reset in the library
      set cells [get_cells -filter ref_name!~"*DFK*" $cells]
      # Ignore FFs w/ mux - no MBFF with mux in the library
      #set cells [get_cells -filter ref_name!~"*DFM*" $cells]
      if { [sizeof_col $cells] == 0 } { continue }
      # Cell(s) already collected
      if { [sizeof $ioRegs] == [sizeof [append_to_col -uniq ioRegs $cells]] } { continue }
      # Split Regs by hierarchy
      foreach_in_col c $cells {
         if { [get_att $c base_name] == [get_att $c full_name] } { set hier_name "MYROOT"
         } else {                                                  set hier_name [regsub [get_att $c base_name] [get_att $c full_name] ""]
                                                                   set hier_name [string trim $hier_name "\/"] }
         lappend ioRegsList($hier_name) "[get_att $c base_name] [lindex [get_att $p bbox] 0 0] [lindex [get_att $p bbox] 1 1]"
      }
   }
   if { [sizeof $ioRegs] == 0 } { puts "Warning: (createIO_multibit) No Registers found!" ; return -1 }
    

   # Get bus edge
   set first 1 ; set edge "C"
   foreach hier [array name ioRegsList] {
      if { $first } { set minx [lindex $ioRegsList($hier) 0 1] ; set miny [lindex $ioRegsList($hier) 0 2] ; set first 0 ; set maxx $minx ; set maxy $miny }
      foreach el $ioRegsList($hier) {
         if { [lindex $el 1] < $minx } { set minx [lindex $el 1] }
         if { [lindex $el 1] > $maxx } { set maxx [lindex $el 1] }
         if { [lindex $el 2] < $miny } { set miny [lindex $el 2] }
         if { [lindex $el 2] > $maxy } { set maxy [lindex $el 2] }
      }
   }
   if { [expr $maxx-$minx] < 0.1 && [expr $maxy-$miny] < 0.1 } { puts "Error: (createIO_multibit) Missalligned bus!" ; return -1 }
   if { [expr $maxx-$minx] < 0.1 } {
      foreach hier [array name ioRegsList] { set ioRegsList($hier) [lsort -index 2 -real $ioRegsList($hier)] ; set edge "V" } }
   if { [expr $maxy-$miny] < 0.1 } {
      foreach hier [array name ioRegsList] { set ioRegsList($hier) [lsort -index 1 -real $ioRegsList($hier)] ; set edge "H" } }
   if { $edge == "C" } { puts "Error: Corner bus not supported!" ; return -1 }

   # Create MBFFs per each hierarchy and per each clock-net
   set n 0
   foreach hier [array name ioRegsList] {
      # Split regs by clock net
      array unset clocks
      foreach el $ioRegsList($hier) {
         if { $hier == "MYROOT" } { set net [get_att [get_nets -of [get_pins -filter is_clock_pin -of [get_cells [lindex $el 0]]]] full_name]
         } else {                   set net [get_att [get_nets -of [get_pins -filter is_clock_pin -of [get_cells "$hier/[lindex $el 0]"]]] full_name] }
         lappend clocks($net) [lindex $el 0]
      }
      # Bank regs by clock-net into the same hierarchy
      foreach clk [array name clocks] {
         set sz [llength $clocks($clk)]
         foreach lc $mbffLibCells {
            set mbLc [lindex $lc 0]
            set w    [lindex $lc 1]
            while { $sz >= $w } {
               unset -nocomplain cells ; incr n
               if { $hier == "MYROOT" } { for {set i 0} {$i<$w} {incr i} { lappend cells [lindex $clocks($clk) $i 0] }
               } else {                   for {set i 0} {$i<$w} {incr i} { lappend cells "$hier/[lindex $clocks($clk) $i 0]" } }
               remove_multibit_options -exclude [get_cells -phys $cells]
               while { [get_cells -quiet -phys ${name}_${n}] != "" } { incr n }
               create_multibit -sort ascending -lib_cell $mbLc -name ${name}_${n} [get_cells -phys $cells]
               #Seqmentation fault:
               #if { [catch {create_multibit -sort ascending -lib_cell $mbLc -name ${name}_${n} [get_cells -phys $cells]} ] } {
               #   puts "ERROR processing ${name}_${n} on cells:"
               #   foreach_in_col c [sort_col [get_cells -phys $cells] full_name] { puts "[get_att $c ref_name] - [get_att $c full_name]" }
               #}
               set clocks($clk) [lreplace $clocks($clk) 0 [expr $w-1]] ; incr sz -$w
            }
         }
      }
   }
   #set_dont_touch [get_cells -phys *${name}_*] true
   set_size_only [get_cells -phys *${name}_*] true
   unsuppress_message "SQM-1058 SQM-1061 SQM-1067"
}
define_proc_attributes createIO_multibit \
   -info "USER PROC: Bank IO boundary flip-flops which share the same bus, hirarchy and clock-net" \
   -define_args {
        {-ports "List or collection or pattern of ports" "" string required}
        {-pDir "Direction of ports to be banked" "" one_of_string {required {values {in out}}}}
        {-mbLibCells "Multibit lib_cells to be used" "" string required}
        {-sbLibCells "Single-bit register lib_cells to be banked" "" string optional}
        {-name "Name to be use for new multi-bit cells naming (default ioMB)" "" string optional}
   }
#  -command_group DF_FEINT


#CN this comes from /proj/unb_snap_4/scripts/fx_timing/GenTimSumPaths.tcl - krackan (Abhishek3 K.)
proc GenTimSum {TimPaths {tunqfy start} {RepSort wns} {RepD "."}} {

    set_app_options -name shell.common.monitor_cpu_memory -value false
    startparalleltimer "GenTimSum $tunqfy"

    set default_perc_list {50 20 10 5 2 0}

    set clkp [get_att [get_clocks FCLK] period]

    set TimSum [dict create]
    set GrpSum [dict create]
    
    puts "#Number of timing paths : [sizeof $TimPaths]"
    set cnt 1
    while {[sizeof $TimPaths]} {
        set twpth [index $TimPaths 0]
        set PthSp [get_attr $twpth startpoint]
        if {[get_attr $PthSp object_class] == "pin"} {
           set PthSpCl [get_attr $PthSp cell.full_name]
#CN        set PthSpPnFl [get_attr [get_pins [get_attr $twpth points.name] -f "full_name=~${PthSpCl}/Q*"] full_name]
#CN Take the 2nd point in the path which should be the output of seq. el. (when pin_ name is not /Q*):
           set PthSpPnFl [get_attr [lindex [get_attr $twpth points.name] 1] full_name]
        }
        set PthEp     [get_attr $twpth endpoint]
        set PthEpPnFl [get_attr $PthEp full_name]
        set tgrp      [get_attr $twpth path_group_name]

        if {$tunqfy == "end"} {
           if {[get_attr $PthEp object_class] == "port"} {
              regsub {\[\d+\]} [get_attr $PthEp full_name] {[*]} tunqp
              set tUnqColl [filter_collection $TimPaths "endpoint.full_name=~$tunqp&&path_group_name==$tgrp"]
              regsub {\[\d+\]} [get_attr $PthEp full_name] {[#]} tunqp
           } else {
              if {[regexp {reg_\d+__\d+} $PthEpPnFl]} {
                 regsub -all {reg_\d+__\d+} $PthEpPnFl {reg_\d+__\d+} tunqp
              } elseif {[regexp {reg_\d+} $PthEpPnFl]} {
                 regsub -all {reg_\d+} $PthEpPnFl {reg_\d+} tunqp
              } else {
                 set tunqp $PthEpPnFl
              } 
              regsub -all {_\d+} $tunqp {_\d+} tunqp
              set tUnqColl [filter_collection -regexp $TimPaths "endpoint.full_name=~$tunqp&&path_group_name==$tgrp"]
              regsub -all {\\d\+} $tunqp {#} tunqp
           }
           set twStartOrEndP [get_attr $twpth startpoint_name]
#CN move out of if# set stp_str Startpoint
#CN move out of if# set enp_str Endpoint
        } else {
           if {[get_attr $PthSp object_class] == "port"} {
              regsub {\[\d+\]} [get_attr $PthSp full_name] {[*]} tunqp
              set tUnqColl [filter_collection $TimPaths "startpoint.full_name=~$tunqp&&path_group_name==$tgrp"]
              regsub {\[\d+\]} [get_attr $PthSp full_name] {[#]} tunqp
           } else {
              if {[regexp {reg_\d+__\d+} $PthSpPnFl]} {
                 regsub -all {reg_\d+__\d+} $PthSpPnFl {reg_\d+__\d+} tunqp
              } elseif {[regexp {reg_\d+} $PthSpPnFl]} {
                 regsub -all {reg_\d+} $PthSpPnFl {reg_\d+} tunqp
              } else {
                 set tunqp $PthSpPnFl
              }
              regsub -all {_\d+} $tunqp {_\d+} tunqp
              set tUnqColl [filter_collection -regexp $TimPaths "points.full_name=~$tunqp&&path_group_name==$tgrp"]
              regsub -all {\\d\+} $tunqp {#} tunqp                
           }
           set twStartOrEndP [get_attr $twpth endpoint_name]
#CN move out of if# set stp_str Endpoint
#CN move out of if# set enp_str Startpoint
        }
        set stp_str Endpoint
        set enp_str Startpoint
        
        set TimPaths [remove_from_collection $TimPaths $tUnqColl]

        #set twpth [index $tUnqColl 0]
        redirect -variable tpth {report_timing -net -nosp -trans -cap -derate -path_type full_clock_expanded -attributes -inp -physical $twpth}
        set tnvp [sizeof $tUnqColl]
#CN What if slack is: missing, INF, N/A, --, "" for ttns/twns ?
#puts "DBG_1t: [get_attr $tUnqColl slack]"
        set ttns  [expr abs(int([ladd [get_attr $tUnqColl slack]]))]
#puts "DBG_1w: [get_attr $twpth slack]"
        set twns [expr int([get_attr $twpth slack]*100)/100.0]
        
        set tlol [get_attr $twpth logic_levels]
        set tcrn [lindex [split [get_attr $twpth corner_name] "_"] 0]

        set PthStEnInst [get_attr [get_pins -quiet "$PthSp $PthEp"] cell]
        set PthInstAll ""
        append_to_collection -unique  PthInstAll [get_attr [get_pins -quiet [get_attr $twpth points.name]] cell]
        set PthInst [remove_from_collection $PthInstAll $PthStEnInst]
        append_to_collection PthInstAll [get_ports -quiet [get_attr $twpth points.name]]

#CN     set PthBufCnt [sizeof [filter_collection $PthInst "ref_name=~BUF*"]]
#CN     set PthInvColl [filter_collection $PthInst "ref_name=~INV*"]
        set PthBufCnt [sizeof [filter_collection $PthInst "ref_block.is_buffer"]]
        set PthInvColl [filter_collection $PthInst "ref_block.is_inverter"]
        set PthInvCnt [sizeof $PthInvColl]
        
        set PthInvPair 0
        while {[sizeof $PthInvColl]} {
           set tinv [index $PthInvColl 0]
           set tld [remove_from_collection -intersect $PthInst [get_attr [filter_collection [all_connected -leaf [all_connected [get_pins -of $tinv -f "direction==out&&port_type==signal"]]] "direction==in"] cell]]
#CN        if {[sizeof $tld] && [regexp "INV*" [get_attr $tld ref_name]]} {}
           if { [sizeof $tld] && [get_attr $tld ref_block.is_inverter]=="true" } {
              #puts "#[get_object_name $tinv] : [get_object_name $tld]"
              incr PthInvPair
              set PthInvColl [remove_from_collection $PthInvColl $tld]
           }
           set PthInvColl [remove_from_collection $PthInvColl $tinv]
        }
 
        set llx [lindex [get_attr [current_design] boundary_bbox] 1 0]
        set lly [lindex [get_attr [current_design] boundary_bbox] 1 1]
        set urx [lindex [get_attr [current_design] boundary_bbox] 0 0]
        set ury [lindex [get_attr [current_design] boundary_bbox] 0 1]
        
#CN use pin location instead cell location -- big error for mems!!! -- loop through [get_attr $twpth points.name]
        foreach_in_collection c $PthInstAll {
           if {[get_attr $c object_class] == "port"} {
              set tx [lindex [get_attr $c location] 0]
              set ty [lindex [get_attr $c location] 1]
           } else {
              set tx [lindex [get_attr $c origin] 0]
              set ty [lindex [get_attr $c origin] 1]
           }
           if {$tx < $llx} {set llx $tx}
           if {$ty < $lly} {set lly $ty}
           if {$tx > $urx} {set urx $tx}
           if {$ty > $ury} {set ury $ty}
        }
        set PthX [expr $urx - $llx]
        set PthY [expr $ury - $lly]

        if {[get_attr $PthSp object_class] == "port"} {
#CN If input_delay is: missing, INF, N/A, --, "" ==> ttid=0
           set ttid [get_attr -quiet $twpth input_delay]
           if { $ttid=="" || [regexp -nocase {n/a|inf|--} $ttid] } { set ttid 0 }
           set twpthck [expr int($ttid*100/$clkp)]
           set PthPrePathSlk "$twpthck%"
           set PthSpPnFO [sizeof [all_fanout -flat -from $PthSp -endpoints_only]]
        } else {
           set PthSpPn [get_attr $PthSpPnFl name]
           set PthSpPnFO [sizeof [all_fanout -flat -from $PthSpPnFl -endpoints_only]]
#CN If PthSpPrePn is not D (mems' inputs; (a)sync S/R, enable pins; special FFs' pins: A1,A2...) or if there are multiple inputs & D* isn't the worst violated one.
           redirect /dev/null {
#AI get_timing_path command throws an error if flop that is found has D-input at a constant value and async_pin doesn't have an related clock attrib set
             set my_pins [get_pins -of ${PthSpCl} -filter related_clock=="FCLK"&&direction=="in"&&(is_data_pin||is_async_pin)]
             if [sizeof_col $my_pins] { set pPath [get_timing_path -to $my_pins] 
             } else { set pPath "" } 
           }
           if [sizeof_col $pPath] {
#CN What if slack is: missing, INF, N/A, --, ""?
                    set PthPrePathSlk [expr {double(round(100*[get_attr $pPath slack]))/100}]
           } else { set PthPrePathSlk "NA" }
#CN        regsub {Q} $PthSpPn {D} PthSpPrePn
#CN        if {[sizeof [get_pins -quiet ${PthSpCl}/${PthSpPrePn}*]] && [get_attr ${PthSpCl}/${PthSpPrePn}* related_clock] == "FCLK" } {
#CN           set PthPrePathSlk [expr {double(round(100*[get_attr [get_timing_path -to ${PthSpCl}/${PthSpPrePn}*] slack]))/100}]
#CN        } else {
#CN           set PthPrePathSlk "NA" 
#CN        }
        }

        if {[get_attr $PthEp object_class] == "port"} {
#CN If check_value is: missing, INF, N/A, --, "" ==> ttod=0
           set ttod [get_attr -quiet $twpth check_value]
           if { $ttod=="" || [regexp -nocase {n/a|inf|--} $ttod] } { set ttod 0 }
           set twpthck [expr int($ttod*100/$clkp)]
           set PthNxtPathSlk "$twpthck%"
           set PthEpPnFI [sizeof [all_fanin -flat -to $PthEp -startpoints_only]]
        } else {
           set PthEpPn [get_attr $PthEp name]
           set PthEpCl [get_attr $PthEp cell.full_name]
           set PthEpPnFI [sizeof [all_fanin -flat -to $PthEp -startpoints_only]]
#CN If PthEpNxtPn is not Q (mem...) or if the violated input isn't D*.
           redirect /dev/null { 
#AI get_timing_path command throws an error if cell that is found is a synchroniser with out pin that has related_clock different than FCLK
              set my_pins [get_pins -of ${PthEpCl} -filter related_clock=="FCLK"&&direction=="out"] 
              if { [sizeof_col $my_pins] } { set pPath [get_timing_path -th $my_pins] 
              } else                   { set pPath "" }
            }
           if [sizeof_col $pPath] {
#CN What if slack is: missing, INF, N/A, --, ""?
                    set PthNxtPathSlk [expr {double(round(100*[get_attr $pPath slack]))/100}]
           } else { set PthNxtPathSlk "NA" }
#CN        regsub {D} $PthEpPn {Q} PthEpNxtPn
#CN        if {[sizeof [get_pins -quiet ${PthEpCl}/${PthEpNxtPn}]]} {
#CN           set PthNxtPathSlk [expr {double(round(100*[get_attr [get_timing_path -thr ${PthEpCl}/${PthEpNxtPn}] slack]))/100}]
#CN        } elseif {[sizeof [get_pins -quiet ${PthEpCl}/Q]]} {
#CN           set PthNxtPathSlk [expr {double(round(100*[get_attr [get_timing_path -thr ${PthEpCl}/Q] slack]))/100}]
#CN        } else {
#CN           set PthNxtPathSlk "NA" 
#CN        }
        }
        set PthBx "$PthX x $PthY ({$llx $lly} {$urx $ury})"
        #puts "#$cnt# $tgrp : $tunqp"
        incr cnt
        dict set TimSum $tgrp $tunqp crn $tcrn
        dict set TimSum $tgrp $tunqp wsep $twStartOrEndP
        dict set TimSum $tgrp $tunqp wns $twns
        dict set TimSum $tgrp $tunqp tns $ttns
        dict set TimSum $tgrp $tunqp nvp $tnvp
        dict set TimSum $tgrp $tunqp lol $tlol
        dict set TimSum $tgrp $tunqp buf $PthBufCnt
        dict set TimSum $tgrp $tunqp inv $PthInvCnt
        dict set TimSum $tgrp $tunqp invp $PthInvPair
        dict set TimSum $tgrp $tunqp pslk $PthPrePathSlk
        dict set TimSum $tgrp $tunqp nslk $PthNxtPathSlk
        dict set TimSum $tgrp $tunqp sfo $PthSpPnFO
        dict set TimSum $tgrp $tunqp efi $PthEpPnFI
        dict set TimSum $tgrp $tunqp bbx $PthBx
        dict set TimSum $tgrp $tunqp pth $tpth

        if {[dict exists $GrpSum $tgrp all]} {
           dict set GrpSum $tgrp all  fp [expr [dict get $GrpSum $tgrp all fp] + [sizeof $tUnqColl]]
           dict set GrpSum $tgrp all ufp [expr [dict get $GrpSum $tgrp all ufp] + 1]
        } else {
           dict set GrpSum $tgrp all  fp [sizeof $tUnqColl] 
           dict set GrpSum $tgrp all ufp 1
        }

        set ttSlkPPerc "-9999" 
        set PrePerc ""
        foreach CurPerc $default_perc_list {
           set ttSlk [expr -1*($CurPerc*$clkp)/100]
           if {$PrePerc == ""} {
              set tkey [format "%2s - %2s%s (%7.2fps : %7sps)" $CurPerc $PrePerc "%" $ttSlk ""]
           } else {
              set tkey [format "%2s - %2s%s (%7.2fps : %7.2fps)" $CurPerc $PrePerc "%" $ttSlk $ttSlkPPerc]
           }
           if {[dict exists $GrpSum $tgrp $tkey]} {
              dict set GrpSum $tgrp $tkey  fp [expr [dict get $GrpSum $tgrp $tkey fp] + [sizeof [filter_collection $tUnqColl "slack<=$ttSlk&&slack>$ttSlkPPerc"]]]
              if {$twns <= $ttSlk && $twns > $ttSlkPPerc} {
                 dict set GrpSum $tgrp $tkey ufp [expr [dict get $GrpSum $tgrp $tkey ufp] + 1]
              }
           } else {
              dict set GrpSum $tgrp $tkey  fp [sizeof [filter_collection $tUnqColl "slack<=$ttSlk&&slack>$ttSlkPPerc"]]
              if {$twns <= $ttSlk && $twns > $ttSlkPPerc} {
                 dict set GrpSum $tgrp $tkey ufp 1
              } else {
                 dict set GrpSum $tgrp $tkey ufp 0
              }
           }
           set ttSlkPPerc $ttSlk
           set PrePerc $CurPerc
        }
    }

    set frmt_hdr "%-5s %-15.15s  %-12s %-55s  %-55s %10s %8s %5s %5s %8s %5s %10s %12s %12s %12s %12s  %s"
    set frmt_sum "#%-4d %-15.15s  %-12s %-55.55s  %-55.55s %10.2f %8s %5s %5s %8s %5s %10d %12s %12s %12s %12s  %s";
    
    set tto  [open ${RepD}/report_timing.rpt.sum.sort_slack.${tunqfy}ptsa w]
    
    set cnt 1
    foreach grp [if {$RepSort == "group"} {lsort [dict keys $TimSum]} else {dict keys $TimSum}] {

       puts $tto [format "Group: %s\n[string repeat # 275]\n$frmt_hdr" $grp "" "" "" "" "" "" "" "" "" "(bfx +" "Num" "" "Worst" "Start" "Worst" "End" ""]
       puts $tto [format $frmt_hdr "" "" "" "" "" "" "" "Real" "bfx/" "inx" "Pa-" "" "Prev" "Fan" "Next" "Fan" ""]
       puts $tto [format $frmt_hdr "" "Path Group" "Corner" "Uniquified $enp_str" "Worst $stp_str" "Slack" "Lvls" "Lvls" "inx" "pairs)" "ths" "TNS" "Slack" "Out" "Slack" "In" "bbox"]
       puts $tto [string repeat - 275]
   
       set NewDict [lsort -real  -stride 2 -index {1 5} [dict get $TimSum $grp]]
       foreach tts [dict keys $NewDict] {
          #puts "#$cnt : [dict get $NewDict $tts grp] : [dict get $NewDict $tts crn] : $tts : [dict get $NewDict $tts wsep] : [dict get $NewDict $tts wns] : [dict get $NewDict $tts lol] : [dict get $NewDict $tts nvp] : [dict get $NewDict $tts tns] : [dict get $NewDict $tts pslk] : [dict get $NewDict $tts nslk] : [dict get $NewDict $tts bbx]"
          puts $tto [format $frmt_sum $cnt $grp [dict get $NewDict $tts crn] $tts [dict get $NewDict $tts wsep] [dict get $NewDict $tts wns] [dict get $NewDict $tts lol] "NA" "[dict get $NewDict $tts buf]/[dict get $NewDict $tts inv]" "([dict get $NewDict $tts buf]+[dict get $NewDict $tts invp])" [dict get $NewDict $tts nvp] [dict get $NewDict $tts tns] [dict get $NewDict $tts pslk] [dict get $NewDict $tts sfo] [dict get $NewDict $tts nslk] [dict get $NewDict $tts efi] [dict get $NewDict $tts bbx]]
          redirect -append -variable PrntTimPaths {puts "#$cnt"}
          redirect -append -variable PrntTimPaths {puts [dict get $NewDict $tts pth]}
          incr cnt
       }
   
       puts $tto [string repeat - 275]
       puts $tto "Group Summary ($grp) Total Failing ${enp_str}s:  [dict get $GrpSum $grp all fp] (uniquified [dict get $GrpSum $grp all ufp])\n"
       puts $tto [format "%32s %10s %10s" "${enp_str}s Over Target" "Total" "Unique"]
       foreach PercGrp [dict keys [dict remove [dict get $GrpSum $tgrp] all]] {
          puts $tto [format "%s %10d %10d" $PercGrp [dict get $GrpSum $grp $PercGrp fp] [dict get $GrpSum $grp $PercGrp ufp]]   
       }
       puts $tto "[string repeat - 275]\n"
    }
    if [info exists PrntTimPaths] { puts $tto $PrntTimPaths }
    close $tto
    sh gzip -f ${RepD}/report_timing.rpt.sum.sort_slack.${tunqfy}ptsa
    
    stopparalleltimer "GenTimSum $tunqfy"
}
#CN WIP:
#CN define_proc_attributes GenTimSum \
#CN    -info "USER PROC: Summarize the timing paths for a given clock" \
#CN    -define_args {
#CN         {-TimPaths "Collection of timing paths to be processed" "" string required}
#CN         {-tunqfy "..." "" one_of_string {required {values {start stop}}}}
#CN         {-RepSort "Criteria for sorting results(default wns)" "" string optional}
#CN         {-RepD "Folder for dumping the results(default .)" "" string optional}
#CN         {-Clock "Clock name to be checked (default FCLK)" "" string optional}
#CN    }
#CN #  -command_group DF_FEINT

############################
# Exclude IO flops from MBB
############################
#Umesh (01/29/2024), Exclude specified I/O flops based on port list
proc df_feint_excludeIOFlops {args} {

   # Get all the arguments out else set defaults
   parse_proc_arguments -args $args results
   if {![info exists results(-ports)]} {return }
   set exPorts $results(-ports)

   append_to_collection -unique mbbExInputs [get_ports -quiet $exPorts -f direction=="in"&&defined(net)]
   set iExRegs {}
   foreach_in_collection inp $mbbExInputs {
      set mCells [get_cells [all_fanout -quiet -flat -only -from $inp] -filter !ref_block.is_buffer&&!ref_block.is_inverter]
      set mRegs [get_cells $mCells -filter @is_sequential==TRUE]
      set mComboCells [remove_from_collection $mCells $mRegs]
      if ([sizeof_col $mRegs]>0) {
         if ([sizeof_col $mComboCells]<6) {
            append_to_collection -unique iExRegs $mRegs
         } 
      }
   }

   append_to_collection -unique mbbExOutputs [get_ports -quiet $exPorts -f direction=="out"&&defined(net)]
   set oExRegs {}
   foreach_in_collection outp $mbbExOutputs {
      set mCells [get_cells [all_fanin -quiet -flat -only -to $outp] -filter !ref_block.is_buffer&&!ref_block.is_inverter]
      set mRegs [get_cells $mCells -filter @is_sequential==TRUE]
      set mComboCells [remove_from_collection $mCells $mRegs]
      if ([sizeof_col $mRegs]>0) {
         if ([sizeof_col $mComboCells]<6) {
            append_to_collection -unique oExRegs $mRegs
         }
      }
   } 
   set exIoRegs [add_to_collection -unique $iExRegs $oExRegs]
   puts "Number of I/O flops excluded from MBB"
   puts [sizeof $exIoRegs]
   set_multibit_options -exclude $exIoRegs
}

define_proc_attributes df_feint_excludeIOFlops \
   -info "USER PROC: Exclude Flops talking to specified I/O with 6 LOL or less" \
   -define_args {
        {-ports "List or collection or pattern of ports" "" string required}
   }

############
#rushinde Procs to report power metrics for DF Power Demarcation initiative
#From /proj/constr15/elsie/strixb0/run1122/fx_dfp_checks.tcl
proc __dfp_get_scope_domain { {input_upf ""}} {
    global P
    set upf data/GetUpf.upf
    if {$input_upf != "" } { set upf $input_upf }

    set upf_pre_loaded 1
    if {[regexp "DEFAULT_POWER_DOMAIN" [get_object_name [get_power_domains -quiet]]]} {
       set upf_pre_loaded 0
       if {[file exists $upf]} {
          puts "INFO : read upf $upf"
          redirect /dev/null {load_upf $upf}
       }
    }

    set top_design_name [get_object_name [get_designs]]
    set top_scope_domain ""
    foreach_in_collection domain [get_power_domains] {
       echo "[get_object_name $domain]"
       set elements [get_attr $domain elements] 
       foreach_in_collection mod $elements {
          if {[get_att $mod full_name] == $top_design_name} {
            set top_scope_domain [get_object_name $domain]
            break
          }
       }
    }
    if {!$upf_pre_loaded} {
       redirect /dev/null {reset_upf}
    }

    echo "INFO: top scope domain: $top_scope_domain"
    return $top_scope_domain
}


proc __get_sink_pin { pin {include_buff 0} } {
  set currPin [get_pin -quiet -phy $pin]
  if {[sizeof $currPin ] == 0} {
     set currPin [get_pin -quiet -hier $pin]
     if {[sizeof $currPin ] == 0} {
        echo "INFO: (__get_driver_pin) $pin pin doesn't exist.  return."
        return ""
     }
  }
  #echo "#######   INFO: __get_driver_pin [get_object_name $currPin]"
  set cnt 0
  set listofsinks ""
  while {$cnt < 10000} {
     set net [get_net -phy -of_object $currPin -filter "net_type == signal"]
     set sinkPins  [get_pins -quiet -phy -of_object $net -filter "direction == in && port_type == signal"]
     set sinkPorts [get_port -quiet -of_object $net -filter "direction == out && port_type == signal"]
     if {[sizeof $sinkPins] == 0} {
           return $sinkPorts
     } 
     incr cnt

     if {$include_buff} {
        append_to_collection sinkPins [get_port -quiet -of_object $net -filter "direction == out && port_type == signal"]
        return $sinkPins 
     }

     foreach_in_collection sink $sinkPins {
        #echo "sink [get_object_name $sink]"
        set sinkCell [get_cell -phy -quiet -of_object $sink]
        if {[sizeof $sinkCell] == 0} { continue }
        if {[get_att $sinkCell lib_cell.function_id] == "a1.0" || [get_att $sinkCell lib_cell.function_id] == "Ia1.0"} {
           #echo "sink [get_object_name $sinkCell] is buf or inv, keep going"
           set outputPin [get_pins -quiet -phy -of_object $sinkCell -filter "direction == out && port_type == signal"]
           append_to_collection listofsinks [__get_sink_pin $outputPin]
        } else {
           append_to_collection listofsinks $sink
        }
     }

     return $listofsinks
  }
}

proc dfp_report_iso_counts { {outfile ""} } {
    if {$outfile == ""} {
       set outfile "rpts/$TARGET_NAME/dfp_check_isolation_counts.rpt"
    }
    set out_file [open "$outfile" w]

    #First store modules in a power_domain dict
    set power_domain_modules [dict create]
    set domain_module_iso_count [dict create]
    set scopeDomain [__dfp_get_scope_domain]
    
    foreach_in_collection dom [get_power_domains] {
        set all_mods ""
        set domain [get_object_name $dom]
        set hierList [get_att [get_power_domain $dom] elements]
        foreach_in_collection hier $hierList {
            set mod [get_cells -quiet $hier -filter "is_hierarchical"]
            if {[sizeof $mod] == 0} { continue }
            append_to_collection -u all_mods $mod
        }
        dict set power_domain_modules $domain $all_mods
        dict set domain_module_iso_count $domain ""
    }

    foreach_in_collection power_strat [get_power_strategies ISO*] {
        set ruleName [get_object_name $power_strat]
        #echo "##### $ruleName"
        set power_strat_iso_cells [get_cells -phy -filter "is_isolation == true && name =~ *$ruleName*"]
        
        foreach_in_collection iso_cell $power_strat_iso_cells {
            set power_domain [get_object_name [get_power_domain -of $iso_cell]]
            set iso_cell_module [get_object_name [get_att -quiet $iso_cell parent_cell]]
            #echo "ISO: [get_object_name $iso_cell] $power_domain : $iso_cell_module"

            if {$power_domain == $scopeDomain} {
               # iso is at top module hier; so check its sink
               set pin [get_pins -of $iso_cell -filter "port_type == signal && direction == out"]
               set load_cells [get_cells -quiet -of [ __get_sink_pin $pin ]]
               if {[sizeof $load_cells] == 0 } {
                   # sink is not a stdcell, likely output port, so ignore
                   continue
               } else {
                   set iso_cell_in_domain ""
                   foreach_in_collection sinkCell $load_cells {
                      set sinkDomain [get_object_name [get_power_domain -of $sinkCell]]
                      set sink_module [get_object_name [get_att -quiet $sinkCell parent_cell]]

                      if {[dict exists $power_domain_modules $sinkDomain]} {
                         set all_modules_in_domain [dict get $power_domain_modules $sinkDomain]
                         foreach_in_collection domainMod $all_modules_in_domain {
                            if {[regexp [get_object_name $domainMod] $sink_module]} {
                               set iso_cell_in_domain $domainMod
                               #echo "ISO iin scope.  Its sink [get_object_name $sinkCell] in sinkDomain $sinkDomain"
                               break
                            }
                         }
                      }
                   }
                   if {[sizeof $iso_cell_in_domain]>0} {
                      set domain_module_iso [dict get $domain_module_iso_count $sinkDomain]
                      append_to_collection domain_module_iso $iso_cell_in_domain
                      dict set domain_module_iso_count $sinkDomain $domain_module_iso
                      #echo "add to [get_object_name $iso_cell_in_domain]"
                   }
               }
            } elseif  {[dict exists $power_domain_modules $power_domain]} {
                set all_modules_in_domain [dict get $power_domain_modules $power_domain]
                set iso_cell_in_domain ""
                foreach_in_collection domainMod $all_modules_in_domain {
                   if {[regexp [get_object_name $domainMod] $iso_cell_module ]} {
                      set iso_cell_in_domain $domainMod
                      break
                   }
                }
                ###set iso_cell_in_domain [filter_collection $all_modules_in_domain "full_name == $iso_cell_module"]
                
                if {[sizeof $iso_cell_in_domain]>0} {
                    #get - set. Might be better way...
                    set domain_module_iso [dict get $domain_module_iso_count $power_domain]
                    append_to_collection domain_module_iso $iso_cell_in_domain
                    dict set domain_module_iso_count $power_domain $domain_module_iso
                    #echo "add to [get_object_name $iso_cell_in_domain]"
                } else {
                    #get output pin of iso and trace to sink. Check if ios cell is driving a domain and respective module
                    #echo "get output pin of iso and trace"
                    set pin [get_pins -of $iso_cell -filter "port_type == signal && direction == out"] 
                    set load_cells [get_cells -quiet -of [ __get_sink_pin $pin ]]
                    if {[sizeof $load_cells] == 0 } {
                       # sink is not a stdcell, likely output port, so ignore
                       continue
                    } else {
                        set iso_cell_in_domain ""
                        foreach_in_collection sinkCell $load_cells {
                           set sinkDomain [get_object_name [get_power_domain -of $sinkCell]]
                           set sink_module [get_object_name [get_att -quiet $sinkCell parent_cell]]
     
                           if {[dict exists $power_domain_modules $sinkDomain]} {
                              set all_modules_in_domain [dict get $power_domain_modules $sinkDomain]
                              foreach_in_collection domainMod $all_modules_in_domain {
                                 if {[regexp [get_object_name $domainMod] $sink_module]} {
                                    set iso_cell_in_domain $domainMod
                                    #echo "ISO iin scope.  Its sink [get_object_name $sinkCell] in sinkDomain $sinkDomain"
                                    break
                                 }
                              }
                           }
                        }

                        if {[sizeof $iso_cell_in_domain]>0} {
                            set domain_module_iso [dict get $domain_module_iso_count $power_domain]
                            append_to_collection domain_module_iso $iso_cell_in_domain
                            dict set domain_module_iso_count $power_domain $domain_module_iso
                            #echo "add to [get_object_name $iso_cell_in_domain]"
                        }
                    }
                }
            }
        }
    }

    #Report - Redo powerstrat query
    puts $out_file [format "%15s | %30s" "IsoCount" "Power Strategy"]
    puts $out_file "---------------------------------------------------------------------------------------------------------------"
    foreach_in_collection power_strat [get_power_strategies ISO*] {
        set ruleName [get_object_name $power_strat]
        set power_strat_iso_cells [get_cells -phy -filter "is_isolation == true && name =~ *$ruleName*"]
        puts $out_file [format "%15s | %40s" "[sizeof $power_strat_iso_cells ]" "[get_object_name $power_strat ]" ]
    }

    #Filter and store module count results in dict for sorting and reporting
    set iso_counts [dict create]
    dict for {domain_name all_mods} $power_domain_modules {
        foreach_in_collection ref_mod $all_mods {
            set mod_to_check [get_object_name $ref_mod]
            set check [dict get $domain_module_iso_count $domain_name]
            set module_check [filter_collection $check "full_name == $mod_to_check"]
            dict set iso_counts "$mod_to_check:$domain_name" [sizeof $module_check] 
            #puts $out_file [format "%15s | %40s" "[sizeof $module_check]" "$mod_to_check"]
        }
    }
    
    #Report
    puts $out_file ""
    puts $out_file [format "%15s | %15s | %40s" "IsoCount" "PowerDomain" "Module Name"]
    puts $out_file "---------------------------------------------------------------------------------------------------------------"
    set iso_counts_sorted [lsort -decreasing -integer -stride 2 -index 1 $iso_counts]
    dict for {ss iso_count} $iso_counts_sorted {
        lassign [split $ss ":"] module_name domain 
        puts $out_file [format "%15s | %15s | %40s" "$iso_count" "$domain" "$module_name"]
    }
    
    close $out_file
}

proc dfp_check_domain_crossing { {outfile ""} {debug 0} } {
    global P
    global TARGET_NAME 

    set slack [list]
    set scopeDomain [__dfp_get_scope_domain]
    if {$outfile == ""} {
       set outfile "rpts/$TARGET_NAME/dfp_check_domain_crossing_"
    }
    
    set iso_outfile "${outfile}_isoCounts.rpt"    
    set totalInstCnt [sizeof [get_cells -phy -filter "!is_physical_only && !is_power_switch"]]

    foreach_in_collection dom [get_power_domains] {
       set largefanin {}
       set largefanout {}
       set fanin [list]
       set fanout [list]
       set summary ""
       set SOCsummary ""
       set cnt 0
       set highFanoutLines ""


       set domain [get_object_name $dom]
       if {$domain == $scopeDomain } { continue } 
       echo "#### DOMAIN: $domain"
       set rptFile "${outfile}_${domain}.rpt"
       set nestedRpt "${outfile}_nestedDomains.rpt"
       
       set hierList [get_att [get_power_domain $dom] elements]
       set out_file [open "$rptFile" w]
       set out_file_nested [open "$nestedRpt" w]

       set socPushDwnPatterns "tile_dfx FCFP remote_smu"

       foreach_in_collection hier $hierList {
         incr cnt
         #if {$cnt > 50} {break}
         set tmpIn 0
         set tmpOut 0
         set mod [get_cells -quiet $hier -filter "is_hierarchical"]
         if {[sizeof $mod] == 0} { continue }
         set pinCnt 0
         set hetegenousFanout ""
         set hetegenousFanin ""
         set nestedDomainCrossPins ""
         set largefanin ""
         set largefanout ""
         set largefaninPins ""
         set largefanoutPins ""
         set hierName [get_object_name $hier]
         if {$debug} { echo [get_object_name $hier] }
         set modulesize [sizeof [get_flat_cells  -of_objects $hier -filter "lib_cell.function_id != a1.0 && lib_cell.function_id != Ia1.0 && !is_hard_macro"]]
         set fanouts ""
         set fanins ""

         set is_socPushDown 0
         foreach socPushDown $socPushDwnPatterns {
            if {[regexp ^$socPushDown [get_object_name $mod]] } {
               set is_socPushDown 1
            }
         }

         foreach_in_collection pin [get_pins -of $mod -filter "port_type == signal"] {
             incr pinCnt
             set isHeter 0
             set dir [get_attr $pin direction]
             if {$debug} {echo "$hierName : PIN: [get_object_name $pin] (dir $dir)" }
    
             ########################################
             if {$dir == "in"} {
                set pts [all_fanin -quiet -flat -start -to $pin -only_cells ]
                if {$debug } { echo "sizeof pts [sizeof $pts]" }
                set fanInPts [filter_collection $pts "lib_cell.function_id != a1.0 && lib_cell.function_id != Ia1.0 && !is_power_switch"]
    
                set isCurrentDomain [filter_collection $fanInPts "power_domain == $domain"]
                set notCurrentDomain [filter_collection $fanInPts "power_domain != $domain"]
    
                if {[sizeof $isCurrentDomain] > 0 && [sizeof $notCurrentDomain] > 0} {
                   # fanin from other domain and aon domain cone
                   append_to_collection  hetegenousFanin $pin
                   set isHeter 1
                }

                append_to_collection -u fanins $notCurrentDomain

                if {$debug} { echo "fanin: [sizeof $isCurrentDomain] [sizeof $notCurrentDomain] $tmpIn "}
                if { [sizeof $notCurrentDomain] > 1000 } {
                    lappend highFanoutLines "[get_object_name $pin] (dir: in) (isHeter: $isHeter)    cnt: [sizeof $notCurrentDomain]"
                    append_to_collection -unique largefanin $notCurrentDomain
                    append_to_collection -unique largefaninPins $pin
                }
               

                if {[sizeof $notCurrentDomain] > 0} {
                   # check for nested domain crossing 
                   set tmpfanout [all_fanout -quiet -flat -end -from $pin -only_cells ]
                   set diffDomainfanout [filter_collection $tmpfanout "power_domain != $domain"]
                   if {[sizeof $diffDomainfanout]} {
                      ## input pin has fanin cone of diff domain and fanout cone of diff domain. (ONO->AON->ONO)
                      append_to_collection -u nestedDomainCrossPins $pin
                      puts $out_file_nested "------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
                      puts $out_file_nested "PINNAME: [get_object_name $pin] (dir [get_att $pin direction])"
                      foreach_in_collection in $notCurrentDomain {
                         set d [get_attr $in power_domain]
                         puts $out_file_nested "    Fanin : [get_object_name $in] (${d})"
                      }
                      foreach_in_collection out $diffDomainfanout {
                         set d [get_attr $out power_domain]
                         puts $out_file_nested "    Fanout: [get_object_name $out] (${d})"
                      }
                   }
                }


             }
    
             #######################################
             if {$dir == "out"} {
                set pts [all_fanout -quiet -flat -end -from $pin -only_cells ]
                if {$debug} { echo "0: [sizeof_collection $pts]"}

                ## find and filter out iso control pins
                set allfanout [all_fanout -quiet -flat  -from $pin ]
                set isoCntl [filter_collection $allfanout "lib_pin.is_isolation_cell_enable_pin == true"]
                if { [sizeof $isoCntl] } {
                   set toBeSkip [all_fanout -from $isoCntl  -quiet -flat -end -only_cells ]
                   set finalPts [remove_from_collection $pts $toBeSkip]
                   set pts $finalPts
                }
                if {$debug} { echo "1: [sizeof_collection $pts]" }

                ## filter test enable pins 
                set testEnable [filter_collection [all_fanout -quiet -flat  -from $pin -end] "lib_pin.signal_type == is_test_enable"]
                if {[sizeof $testEnable]} {
                    set toBeSkip [get_cells -quiet -phy -of $testEnable]
                    set finalPts [remove_from_collection $pts $toBeSkip]
                    set pts $finalPts
                }
                if {$debug} { echo "2: [sizeof_collection $pts]" }

                
                ## filter clock_gate_test_pin 
                #set testEnable [filter_collection [all_fanout -quiet -flat  -from $pin -end] "lib_pin.clock_gate_test_pin == true"]
                #if {[sizeof $testEnable]} {
                #    set toBeSkip [get_cells -quiet -phy -of $testEnable]
                #    set finalPts [remove_from_collection $pts $toBeSkip]
                #    set pts $finalPts
                #}
                #sizeof_collection $pts


                ## filter out power switch enable pins
                set fanOutPts [filter_collection $pts "lib_cell.function_id != a1.0 && lib_cell.function_id != Ia1.0 && !is_power_switch && !is_diode_cell"]


                if {[sizeof $fanOutPts] == 0} { continue }
    
                set isCurrentDomain [filter_collection $fanOutPts "power_domain == $domain"]
                set notCurrentDomain [filter_collection $fanOutPts "power_domain != $domain"]
    
                if {[sizeof $isCurrentDomain] > 0 && [sizeof $notCurrentDomain] > 0} {
                   # fanin from other domain and aon domain cone
                   append_to_collection  hetegenousFanout $pin
                   set isHeter 1
                }
    

                if {$debug} { echo "pin [get_object_name $pin] : fanout: [sizeof $isCurrentDomain] [sizeof $notCurrentDomain] $tmpOut" }
                append_to_collection -u fanouts $notCurrentDomain
    
                if { [sizeof $notCurrentDomain] > 1000 } {
                    lappend highFanoutLines  "[get_object_name $pin] (dir: out) (isHeter: $isHeter)   cnt: [sizeof $notCurrentDomain]"
                    append_to_collection -unique largefanout $notCurrentDomain
                    append_to_collection -unique largefanoutPins $pin 
                }

                if {[sizeof $notCurrentDomain] > 0} {
                   # check for nested domain crossing 
                   set tmpfanin  [all_fanin  -quiet -flat -start -to $pin -only_cells ]
                   set diffDomainfanin [filter_collection $tmpfanin "power_domain != $domain"]
                   if {[sizeof $diffDomainfanin]} {
                      ## output pin has fanin cone of diff domain and fanout cone of diff domain. (ONO->AON->ONO)
                      append_to_collection -u nestedDomainCrossPins $pin
                      puts $out_file_nested "------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
                      puts $out_file_nested "PINNAME: [get_object_name $pin] (dir [get_attr $pin direction])"
                      foreach_in_collection in  $diffDomainfanin {
                         set d [get_attr $in  power_domain]
                         puts $out_file_nested "    StartPt: [get_object_name $in] (${d})"
                      }
                      foreach_in_collection out $notCurrentDomain {
                         set d [get_attr $out power_domain]
                         puts $out_file_nested "    EndPt  : [get_object_name $out] (${d})"
                      }

                   }
                }
            }
         }
         set tmpIn [expr [sizeof $fanins] + $tmpIn]
         set tmpOut [expr [sizeof $fanouts] + $tmpOut]
    
         echo $largefaninPins
         set ln [list [expr $tmpIn + $tmpOut] [get_object_name $hier] $tmpIn $tmpOut $pinCnt "[sizeof $largefaninPins] \([sizeof $largefanin]\)" "[sizeof $largefanoutPins] \([sizeof $largefanout]\)" [sizeof $hetegenousFanin] [sizeof $hetegenousFanout] $modulesize [sizeof $nestedDomainCrossPins]]
         if {$is_socPushDown} { 
            lappend SOCsummary  $ln
         } else {
            lappend summary  $ln
         }
         #echo $ln
    
      }

      ######################################################################################################
      # Print report

      #print header
      echo "Printing report... $rptFile [date]"
      puts $out_file ""
      puts $out_file "###########################################################################################################################################"
      puts $out_file "                                               LEGENDS:"
      puts $out_file "-------------------------------------------------------------------------------------------------------------------------------------------"
      puts $out_file [format "%22s | %50s" "InstCnt" "Instances found within the module" ]
      puts $out_file [format "%22s | %50s" "TotPinCnt" "Total number of IN/OUT module pins at the module boundary" ]
      puts $out_file [format "%22s | %50s" "LrgFanInPinCnt" "Number of INPUT module pins where its startPt counts is greater than 1000" ]
      puts $out_file [format "%22s | %50s" "LrgFanOutPinCnt" "Number of OUTPUT module pins where its endPt counts is greater than 1000" ]
      puts $out_file [format "%22s | %50s" "HeterFanInCnt" "Number of INPUT module pins where its startPts are from different domains" ]
      puts $out_file [format "%22s | %50s" "HeterFanOutCnt" "Number of OUTPUT module pins where its endPts are from different domains" ]
      puts $out_file [format "%22s | %50s" "NestedDmnCrossing" "Number of module pins where its startPt and endPt are in different domains compare to current module domain  (ie (startPt ONO)->AON->(endPt ONO)" ]
      puts $out_file [format "%22s | %50s" "DmnCrossFanIn" "Total number of startPts from all INPUT module pins where the domain is different than current module domain" ]
      puts $out_file [format "%22s | %50s" "DmnCrossFanOut" "Total number of endPts from all INPUT module pins where the domain is different than current module domain" ]
      puts $out_file [format "%22s | %50s" "ModuleName" "Module name" ]
      puts $out_file "* NOTE1: startPt and endPt are referring to flops/macros/ports "
      puts $out_file "* NOTE2: endPt filters out power gate enable pins/isolation enable pins/test scan enable pins"
      puts $out_file "###########################################################################################################################################\n"

      
      #print summary
      puts $out_file "#TILENAME: [get_object_name [get_designs]] [date]"
      puts $out_file "#Total tile stdcell count: $totalInstCnt"
      puts $out_file "#DOMAIN: $domain : sizeof element [sizeof $hierList] \n"

      __dfp_check_domain_report $out_file $summary $totalInstCnt "TOTAL_SUM: NON_SOC_PUSHDOWN"
      if {[llength $SOCsummary]} {
         __dfp_check_domain_report $out_file $SOCsummary $totalInstCnt "TOTAL_SUM: SOC_PUSHDOWN"
      }
    
      puts $out_file ""
      puts $out_file ""
      puts $out_file ""
         
      puts $out_file "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
      puts $out_file "# High Fanin/Fanout Crossing Pins: "
      foreach ll $highFanoutLines {
         puts $out_file $ll
      }
  
      close $out_file
      close $out_file_nested

      echo "DONE: dfp_check_domain_crossing [date]"

    }

    #report isolation counts
    dfp_report_iso_counts $iso_outfile
    
}

proc __dfp_check_domain_report {out_file summary totalInstCnt summaryName } {
      puts $out_file [format "%20s | %17s | %15s | %15s | %15s | %15s | %17s | %15s | %15s | %40s" "InstCnt" "TotPinCnt" "LrgFanInPinCnt" "LrgFanOutPinCnt" "HeterFanInCnt" "HeterFanOutCnt" "NestedDmnCrossing" "DmnCrossFanIn" "DmnCrossFanOut" "ModuleName"]
      puts $out_file [format "%20s | %17s | %15s | %15s | %15s | %15s | %17s | %15s | %15s | %40s" "(InstCnt/TotInstCnt)" "(Pin/Inst ratio)" "PinCnt(Fanin)" "PinCnt(Fanout)" "" "" "" "startPt Only" "endPt Only" ""]
      puts $out_file "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

      ## keywordlist order must match with the $ln from earlier
      set keywordlist [list i o totPinCnt larInCnt larOutCnt hetInCnt hetOutCnt modulesize nestedPinCnt]
      set finalSumm [dict create]
      foreach kk $keywordlist {
         dict set finalSumm $kk 0
      }
      
      foreach x [lsort -decreasing -integer -index 0 $summary] {

         for {set ii 2} {$ii < [llength $x]} {incr ii} {
            set kk [lindex $keywordlist [expr $ii - 2]]
            if {[regexp {lar} $kk]} {
                  lassign [split [lindex $x $ii] "("]  pinCnt dummy
                  dict set finalSumm $kk [expr [dict get $finalSumm $kk] + $pinCnt]
            } else {
                  dict set finalSumm $kk [expr [dict get $finalSumm $kk] + [lindex $x $ii]]
            }
         }

         set n [lindex $x 1]
         set i [lindex $x 2]
         set o [lindex $x 3]
         set totPinCnt [lindex $x 4]
         set larInCnt [lindex $x 5]
         set larOutCnt [lindex $x 6]
         set hetInCnt [lindex $x 7]
         set hetOutCnt [lindex $x 8]
         set modulesize [lindex $x 9]
         set nestedPinCnt [lindex $x 10]


         #set ratio [format "%.2f" [expr (1.0 * $modulesize) / $totPinCnt]]
         set ratio 0.000
         set iRatio 0.000
         if { $modulesize > 0 } { 
            set ratio [format "%.3f" [expr (1.0 * $totPinCnt) / $modulesize]]
            set iRatio [format "%.3f" [expr (1.0 * $modulesize) / $totalInstCnt]]
         }
      
         puts $out_file [format "%20s | %17s | %15s | %15s | %15s | %15s | %17s | %15s | %15d | %40s" "$modulesize ($iRatio)" "$totPinCnt ($ratio)" $larInCnt $larOutCnt $hetInCnt $hetOutCnt $nestedPinCnt $i $o $n]
      }
      puts $out_file "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
      set iRatio [format "%.3f" [expr (1.0 * [dict get $finalSumm modulesize])  / $totalInstCnt]]

      puts $out_file [format "%15s | %17s | %15s | %15s | %15s | %15s | %17s | %15s | %15d | %40s" \
          "[dict get $finalSumm modulesize] ($iRatio)" \
          [dict get $finalSumm totPinCnt] \
          [dict get $finalSumm larInCnt] \
          [dict get $finalSumm larOutCnt] \
          [dict get $finalSumm hetInCnt] \
          [dict get $finalSumm hetOutCnt] \
          [dict get $finalSumm nestedPinCnt] \
          [dict get $finalSumm i] \
          [dict get $finalSumm o] \
          $summaryName ]

      puts $out_file "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
      puts $out_file "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
      puts $out_file ""
      puts $out_file ""

}


########

#$boundary: X Y - this is X & Y extenstion of the rectangle which includes all ports in $ports
#Today we're keeping command's default as "soft bound" with "effort ultra" to minimize impact in QoR
proc boundLogic2Ports { args } {
# Creates a single bound for all given ports' logic
   parse_proc_arguments -args $args results
   foreach el [array names results] { set [string trimleft $el "-"] $results($el) }
   if {![info exists results(-namePrefix)]} { set namePrefix "bnd_Logic2Ports"
                                              for {set i 0} {[sizeof_col [get_bounds -q $namePrefix]]>0} {incr i} { set namePrefix ${namePrefix}_dflt }
   }

   # Ignore global(e.g. clocks) and static ports
   if [info exists keep_global_ports] {
      set ignoredPorts ""
   } else {
      set ignoredPorts [filter_col [get_att [get_clocks] sources] "@object_class==port"]
      append_to_col -uniq ignoredPorts [get_ports "*Gather* Strap* *Scatter*"]
   }

   # Collect output / input logic cones of given ports
   set selPorts [remove_from_col [get_ports $ports] $ignoredPorts]
   set outCone  [all_fanin -quiet -flat -to [filter_col $selPorts "@direction==out"] -only_cells]
   set inCone   [all_fanout -quiet -flat -from [filter_col $selPorts "@direction==in"] -only_cells]
   set outConeR [all_fanin -quiet -flat -to [filter_col $selPorts "@direction==out"] -only_cells -startp]
   set inConeR  [all_fanout -quiet -flat -from [filter_col $selPorts "@direction==in"] -only_cells -endp]

   # Collect i/o logic of the rest of the ports
   set nonSelPorts [remove_from_col [remove_from_col [get_ports] $selPorts] $ignoredPorts]
   set nonCone     [all_fanin -quiet -flat -to [filter_col $nonSelPorts "@direction==out"] -only_cells]
   append_to_col -uniq nonCone [all_fanout -quiet -flat -from [filter_col $nonSelPorts "@direction==in"] -only_cells]

   # Collect output/input-logic-only
   if [sizeof_col $outCone] { set outConeO [remove_from_col [remove_from_col $outCone $nonCone] $inCone]
   } else {                   set outConeO "" }
   if [sizeof_col $inCone]  { set inConeO  [remove_from_col [remove_from_col $inCone $nonCone] $outCone]
   } else {                   set inConeO  "" }

   # Collect bounding cells
   if [info exists include_full_cone] {
      set bndCells $outCone
      append_to_col -uniq bndCells $inCone
   } else {
      set bndCells $outConeO
      append_to_col -uniq bndCells $inConeO
      if [info exists include_regs] { append_to_col -uniq bndCells $outConeR
                                      append_to_col -uniq bndCells $inConeR }
   }

   # Collect input&output common logic from bounding logic
   set inoutConeO [remove_from_col [remove_from_col $outCone $nonCone] $outConeO]

   # Exclude input&output common logic from bounding logic
   #?! if [sizeof_col $inoutConeO] { set bndCells [remove_from_col $bndCells $inoutConeO] }
   # Include input&output common logic to bounding logic
   if [sizeof_col $inoutConeO] { set bndCells [append_to_col -uniq bndCells $inoutConeO] }

   # Exclude ICGs from bounding logic
   if ![info exists include_icg] { set bndCells [filter_col $bndCells "!@is_integrated_clock_gating_cell"] }

   # Cells to be excluded from bound by request
   if [info exists exclude_cell] {
      set exclude_cells [get_cells -phy -q $exclude_cell]
      if [sizeof_col $exclude_cells] { set bndCells [remove_from_col $bndCells $exclude_cells] }
   }

   # Get the bound's shape which will include the selected ports' logic
   set x_ll [lindex [get_att [current_block] bbox] 1 0] ; set y_ll [lindex [get_att [current_block] bbox] 1 1]
   set x_ur 0 ; set y_ur 0
   foreach_in_col p $selPorts {
      if { $x_ll > [lindex [get_att $p bbox] 0 0] } { set x_ll [lindex [get_att $p bbox] 0 0] }
      if { $x_ur < [lindex [get_att $p bbox] 1 0] } { set x_ur [lindex [get_att $p bbox] 1 0] }
      if { $y_ll > [lindex [get_att $p bbox] 0 1] } { set y_ll [lindex [get_att $p bbox] 0 1] }
      if { $y_ur < [lindex [get_att $p bbox] 1 1] } { set y_ur [lindex [get_att $p bbox] 1 1] }
   }
   if { [llength $boundary] == 4 } { set x_ll [lindex $boundary 0] ; set y_ll [lindex $boundary 1]
                                     set x_ur [lindex $boundary 2] ; set y_ur [lindex $boundary 3]
      set shape [create_poly_rect -boundary [list "$x_ll $y_ll" "$x_ur $y_ur"]]
   } elseif { [llength $boundary] == 2 } { set X [lindex $boundary 0] ; set Y [lindex $boundary 1]
      set shape [create_poly_rect -boundary [list "[expr $x_ll-$X] [expr $y_ll-$Y]" "[expr $x_ur+$X] [expr $y_ur+$Y]"]]
   } else { puts "Error(boundLogic2Ports): $boundary not supported" ; return -1 }
                                   
   # Adjust the shape to the block's boundary and build the bound
   set shape [compute_polygon -objects1 [get_att [current_block] boundary] -objects2 $shape -operation AND]
   set cmd "create_bound -name \$namePrefix -boundary \$shape \$bndCells"
   if [info exists type]   { lappend cmd " -type $type" }
   if [info exists effort] { lappend cmd " -effort $effort" }
   return [eval $cmd]
}
define_proc_attributes boundLogic2Ports \
    -info "Bound logic from ports' logic cones, excluding the logic shared with the rest of the ports." \
    -define_args {
       {-ports        "List or collection or string-pattern to identify the ports" "" string required}
       {-boundary     "Boundary spec: {Xll Yll Xur Yur} or {X Y} where X & Y is the extension from left/righ & top/bottom most port placement in the list" "" string required}
       {-namePrefix   "Bound name prefix, default is bnd_Logic2Ports" "" string optional}
       {-type         "Bound type, default is soft" "" one_of_string {optional value_help {values {soft hard}}}}
       {-effort       "Specifies how strongly a bound works to keep cells within the boundary, default is ultra" "" one_of_string {optional value_help {values {low medium high ultra}}}}
       {-keep_global_ports "Keeps global ports(clocks, *Gather*, Strap*, *Scatter*) from -ports list" "" boolean optional}
       {-include_icg  "Include integrated clock gaters(icg) sinks to bound" "" boolean optional}
       {-include_regs "Include logic cones' driver/sink regs even if they are shared w/ non-given-ports logic" "" boolean optional}
       {-include_full_cone "Include full logic cones of ports, it skips icg & global_ports if not specified otherwise" "" boolean optional}
       {-exclude_cell "Cell(s) to be excluded from bounding." "" string optional}
    }


# Report sequential cells output pins / inputs ports with high fanout
proc rptHighFanoutDrivers { args } {
   parse_proc_arguments -args $args results
   foreach el [array names results] { set [string trimleft $el "-"] $results($el) ; puts "$el = $results($el)"}
   if {[info exists results(-list)]} { set myList 1 }
   if { ![info exists myList] && ![info exists output] } { puts "At least one of the options are required: -list -output" ; return 0 }

#FIXME: Avoid buses: ga [gp pie_main/pie_aon_regs/udf_pie_aon_rb/oQ_PwrMgtTmrCtl1_VsocoffBootstrapResetDlyScale_reg_0_/Q] is_bus_bit
                                      append cFilters "is_sequential"
   if [info exists include_icgs] {    append cFilters "&&!is_integrated_clock_gating_cell" }
   if [info exists include_latches] { append cFilters "&&(is_rise_edge_triggered||is_fall_edge_triggered)" }
   if [info exists pattern] {         append pFilters "&&("
        set f 1
        foreach p $pattern { if $f {  append pFilters "full_name=~$p" ; set f 0
                             } else { append pFilters "||full_name=~$p" }
                           }
                                      append pFilters ")"
   } else {                           append pFilters "" }
   set seqCells [sort_col [get_cells -phys -filter $cFilters] full_name]
   foreach_in_col c $seqCells {
      foreach_in_col p [get_pins -filter direction=="out"$pFilters -of $c] {
         set sk [all_fanout -quiet -flat -end -from $p]
         if { [sizeof_col $sk] > $threshold } {
            set oPorts [sizeof_col [get_ports -quiet $sk]]
            set FFin   [sizeof_col [get_pins  -quiet -filter cell.is_rise_edge_triggered||cell.is_fall_edge_triggered $sk]]
            lappend HFDs "[get_att $p full_name] [sizeof_col $sk] $FFin $oPorts"
         }
      }
   }
   if [info exists include_inputs] {
      foreach_in_col p [get_ports -filter direction=="in"$pFilters] {
         set sk [all_fanout -quiet -flat -end -from $p]
         if { [sizeof_col $sk] > $threshold } {
            set oPorts [sizeof_col [get_ports -quiet $sk]]
            set FFin   [sizeof_col [get_pins  -quiet -filter cell.is_rise_edge_triggered||cell.is_fall_edge_triggered $sk]]
            lappend HFDs "[get_att $p full_name] [sizeof_col $sk] $FFin $oPorts"
         }
      }
   }
   if [info exists output] {
      set HFDs [lsort -decreasing -integer -index 2 $HFDs] ; set f [open ${output}.sortFF.rpt w]
      puts $f "PIN\t\t FF_Sinks All_Sinks OutputPorts"
      foreach p $HFDs { puts $f "[lindex $p 0] [lindex $p 2] [lindex $p 1] [lindex $p 3]" }
      close $f ; sh gzip -f ${output}.sortFF.rpt
      set HFDs [lsort -decreasing -integer -index 1 $HFDs] ; set f [open ${output}.sortALL.rpt w]
      puts $f "PIN\t\t All_Sinks FF_Sinks OutputPorts"
      foreach p $HFDs { puts $f $p }
      close $f ; sh gzip -f ${output}.sortALL.rpt
   }
   if [info exists myList] { puts $HFDs }
}
define_proc_attributes rptHighFanoutDrivers \
    -info "Report drivers -sequential cells' outputs & input ports- with high fanout." \
    -define_args {
       {pattern          "Specify high fanout driver pattern, default all are considered." "" string optional}
       {-list            "Return a list of high fanout drivers." "" boolean optional}
       {-output          "Output filename to dump high fanout drivers." "" string optional}
       {-include_icgs    "By default ICGs' outputs are excluded - ICGs are mostly on clock network" "" boolean optional}
       {-include_latches "By default latches' outputs are excluded - latches are mostly coming from lat_arrays" "" boolean optional}
       {-include_inputs  "By default input ports are excluded" "" boolean optional}
       {-threshold       "Defines threshold for high logic cones, default 10000 sinks." "" int {optional {default 10000}}}
       {-blast_busses    "" "" boolean optional}
    }


# Set in/output delay to in/output ports according to the clocks used to capture/release the data from/to these ports.
#FIXME: Only positive_triggered / positive_level_sensitive sequential cells are supported
proc setIOdelay { args } {
   parse_proc_arguments -args $args results
   foreach el [array names results] { set [string trimleft $el "-"] $results($el) }
   if {![info exists results(-percent)]} { set threshold 0.500 }
   suppress_message UIC-040
   foreach_in_col p [get_ports -quiet $ports -filter direction=="in"] {
      set ep    [get_att [get_pins -quiet [all_fanout -quiet -flat -end -from $p]] cell]
      set cks   [lsort -u [get_att [get_pins -filter is_clock_pin -of $ep] clocks.name]]
      #set cks_r [lsort -u [get_att [get_pins -filter is_clock_pin&&(is_rise_edge_triggered_clock_pin||is_positive_level_sensitive_clock_pin) -of $ep] clocks.name]]
      #set cks_f [lsort -u [get_att [get_pins -filter is_clock_pin&&(is_fall_edge_triggered_clock_pin||is_negative_level_sensitive_clock_pin) -of $ep] clocks.name]]
      if { [llength $cks] == 0 } { set cks FCLK ; set cks_r FCLK } ; set f 1
      foreach ck $cks   {
         foreach item_ck $ck {
            if $f {  lappend constrIF($item_ck) [get_att $p name] ; set f 0
            } else { lappend constrI($item_ck)  [get_att $p name] }
            #foreach ck $cks_r { if $f {  lappend constrIF_f($ck) [get_att $p name] ; set f 0
            #                    } else { lappend constrI_f($ck)  [get_att $p name] } }
            #foreach ck $cks_f { if $f {  lappend constrIF_f($ck) [get_att $p name] ; set f 0
            #                    } else { lappend constrI_f($ck)  [get_att $p name] } }
         }
      }
   }
   foreach_in_col p [get_ports -quiet $ports -filter direction=="out"] {
      set sp [get_att [get_pins -quiet [all_fanin -quiet -flat -start -to $p]] cell]
      set cks [lsort -u [get_att [get_pins -filter is_clock_pin -of $sp] clocks.name]]
      #set cks_r [lsort -u [get_att [get_pins -filter is_clock_pin&&(is_rise_edge_triggered_clock_pin||is_positive_level_sensitive_clock_pin) -of $sp] clocks.name]]
      #set cks_f [lsort -u [get_att [get_pins -filter is_clock_pin&&(is_fall_edge_triggered_clock_pin||is_negative_level_sensitive_clock_pin) -of $sp] clocks.name]]
      if { [llength $cks] == 0 } { set cks FCLK ; set cks_r FCLK } ; set f 1
      foreach ck $cks   { 
          foreach item_ck $ck {
            if $f {  lappend constrOF($item_ck) [get_att $p name] ; set f 0
            } else { lappend constrO($item_ck)  [get_att $p name] } }
          }
      #foreach ck $cks_r { if $f {  lappend constrOF_f($ck) [get_att $p name] ; set f 0
      #                    } else { lappend constrO_f($ck)  [get_att $p name] } }
      #foreach ck $cks_f { if $f {  lappend constrOF_f($ck) [get_att $p name] ; set f 0
      #                    } else { lappend constrO_f($ck)  [get_att $p name] } }
   }
   foreach c [array names constrIF] {   set_input_delay  -clock $c -max [expr $percent*[get_att [get_clocks $c] period]] $constrIF($c) }
   foreach c [array names constrOF] {   set_output_delay -clock $c -max [expr $percent*[get_att [get_clocks $c] period]] $constrOF($c) }
#  foreach c [array names constrIF_f] { set_input_delay  -clock $c -clock_fall -max [expr $percent*[get_att [get_clocks $c] period]] $constrIF($c) }
#  foreach c [array names constrOF_f] { set_output_delay -clock $c -clock_fall -max [expr $percent*[get_att [get_clocks $c] period]] $constrOF($c) }
   foreach c [array names constrI] {    set_input_delay  -clock $c -max [expr $percent*[get_att [get_clocks $c] period]] $constrI($c) -add_delay }
   foreach c [array names constrO] {    set_output_delay -clock $c -max [expr $percent*[get_att [get_clocks $c] period]] $constrO($c) -add_delay }
#  foreach c [array names constrI_f] {  set_input_delay  -clock $c -clock_fall -max [expr $percent*[get_att [get_clocks $c] period]] $constrI($c) -add_delay }
#  foreach c [array names constrO_f] {  set_output_delay -clock $c -clock_fall -max [expr $percent*[get_att [get_clocks $c] period]] $constrO($c) -add_delay }
   unsuppress_message UIC-040
}
define_proc_attributes setIOdelay \
    -info "Set in/output delay to in/output ports according to the clocks used to capture/release the data from/to these ports.
                      # Only positive_triggered / positive_level_sensitive sequential cells are supported" \
    -define_args {
       {-ports    "A list, a collection or a pattern for portsi to be constrained." "" string required}
       {-percent  "Defines the percentage from clock period to be used for constraints, default 0.500 (50% of clock period)." "" string optional}
    }

proc rptIOlol { } {
   set f [open "data/IO.lol.rpt" w]
   set ports [remove_from_col [get_ports -filter port_type=="signal"] [get_ports [get_att [get_clocks] sources]]]
   set no [sizeof_col $ports]
   foreach_in_col p $ports {
#CN   puts -nonewline $no ; incr no -1
      redirect /dev/null { set path [get_timing_path -th $p] }
      if [sizeof_col $path] { puts $f "[get_att $p name]: [get_att $path num_logic_gates] ([get_att $path logic_levels])" }
   }
   close $f
}

#########
#CN: Procs to add blockages in the macro channels and over the non-macro areas
proc splitPoly { args } {
   parse_proc_arguments -args $args options
   foreach o [array name options] { set [string trimleft $o "-"] $options($o) }
   set poly [split_poly -objects $poly -output poly_rect -split horizontal]
#  foreach_in_col r [get_att $poly poly_rects] {}
   foreach_in_col r $poly {
      set x0 [get_att $r bbox_llx] ; set y0 [get_att $r bbox_lly]
      set w [get_att $r width] ; set h [get_att $r height]
      unset -nocomplain x y
      for {set i 0} {$i<[expr $w-0.3*$xStep]} {incr i $xStep} { lappend x [expr $x0+$i] } ; if {$i != $w } { lappend x [get_att $r bbox_urx] } ; set x [lrange $x 1 end]
      for {set i 0} {$i<[expr $h-0.3*$yStep]} {incr i $yStep} { lappend y [expr $y0+$i] } ; if {$i != $h } { lappend y [get_att $r bbox_ury] } ; set y [lrange $y 1 end]
      set xi $x0
      foreach i $x {
         set yi $y0
         foreach j $y {
            unset -nocomplain b ; lappend b [list "$xi $yi" "$i $j"]
            lappend sPoly [create_poly_rect -boundary $b]
            set yi $j
         }
         set xi $i
      }
   }
   return $sPoly
}
define_proc_attributes splitPoly \
   -info "# Splits a large polygon into smaller ones" \
   -define_args {
      {-poly   "Polygon to split" "" string required}
      {-xStep  "Horizontal step for spliting" "" string required}
      {-yStep  "Vertical step for spliting" "" string required}
   }

proc df_feint_add_blockages { args } {
   parse_proc_arguments -args $args options
   foreach o [array name options] { set [string trimleft $o "-"] $options($o) }
   if ![info exists myPBprefix] { set myPBprefix "myPB" }
   if ![info exists minChW] {     set minChW 11.000 }
   if ![info exists minChH] {     set minChH 12.000 }
   if ![info exists maxChW] {     set maxChW 28.000 } ;# the narrowest hard_macro must be wider than the $maxChW
   if ![info exists maxChH] {     set maxChH 10.000 } ;# the shortest hard_macro must be taller than the $maxChH
   if ![info exists chBlkPercentage] {        set chBlkPercentage 30 }
   if ![info exists wholeAreaBlkPercentage] { set wholeAreaBlkPercentage 0.000 }

   set bdrVPoly [compute_poly -objects1 [get_att [current_block] boundary] -objects2 [resize_poly -objects [get_att [get_core_area] boundary] -size "0 100"] -operation NOT]
   set bdrHPoly [compute_poly -objects1 [get_att [current_block] boundary] -objects2 [resize_poly -objects [get_att [get_core_area] boundary] -size "100 0"] -operation NOT]

   # Remove existing partial or buffer_only blockages:
   if [sizeof_col [get_placement_blockages -quiet -filter blockage_type=="partial"||blockage_type=="allow_buffer_only"]] {
      remove_placement_blockages [get_placement_blockages -filter blockage_type=="partial"||blockage_type=="allow_buffer_only"]
   }
   # Remove prevous myPB blockages:
   if [sizeof_col [get_placement_blockages -quiet  ${myPBprefix}* ]] {
      remove_placement_blockages [get_placement_blockages  ${myPBprefix}* ]
   }
   # Remove prevous buff only previous blockages:
   if [sizeof_col [get_placement_blockages -quiet  partial_bkg_buf_only_* ]] {
      remove_placement_blockages [get_placement_blockages partial_bkg_buf_only_*]
   }
   # Collect remaining placement blockages & merge those which are closer than 2.9um on X (targeting hard placement blockages emulating power switches or missing logic)
   if [sizeof_col [get_placement_blockages -quiet *]] {
            set plcPoly [resize_poly -objects [resize_poly -objects [get_placement_blockages *] -size {2.9 0}] -size {-2.9 0}]
   } else { set plcPoly [create_poly_rect -boundary {{0 0} {0 0}}] }

   # Collect hard_macros
   set hmCells    [get_cells -phys -filter is_hard_macro] ; list
   # Collect physical cells' poly (tap-cells/power-switches)
   if [sizeof_col [get_cells -phys -filter is_physical_only&&!is_hard_macro&&name==*SPARE*]] {
      set phCellPoly [resize_poly -objects [resize_poly -objects [get_cells -filter is_physical_only&&!is_hard_macro] -size {0.21 1.7}] -size {-0.21 -1.7}]
      #Skip poly w/ height <1.5um
      set phCellPoly [resize_poly -objects $phCellPoly -size {0 -1.5}]
      if ![get_att $phCellPoly is_empty] { set phCellPoly [resize_poly -objects -size {0 1.5}] }
   } else {
      set phCellPoly [create_poly_rect -boundary {{0 0} {0 0}}] }

   #myPBv_00p - Block vertical hard_macro channels narrower than minChW (ignore any existing blockage)
   set hmBlkV [resize_poly -objects [resize_poly -objects $hmCells -size "[expr $minChW/2.000] 0"] -size "-[expr $minChW/2.000] 0"]
   set pbPoly [compute_poly -objects1 $hmBlkV -objects2 $hmCells -operation NOT] 
   if ![get_att $pbPoly is_empty] { set pbPoly [resize_poly -objects [resize_poly -objects $pbPoly -size "0 [expr $minChH/2.000]"] -size "0 -[expr $minChH/2.000]"] ; list }
   if ![get_att $pbPoly is_empty] { create_placement_blockage -name ${myPBprefix}v_00p -boundary $pbPoly ; list }

   #myPBh_00p - Block horizontal hard_macro channels shorter than minChH (ignore any existing blockage)
   set hmBlkH [resize_poly -objects [resize_poly -objects $hmCells -size "0 [expr $minChH/2.000]"] -size "0 -[expr $minChH/2.000]"]
   set pbPoly  [compute_poly -objects1 $hmBlkH -objects2 $hmCells -operation NOT] 
   if ![get_att $pbPoly is_empty] { set pbPoly [resize_poly -objects [resize_poly -objects  $pbPoly -size "[expr $minChW/2.000] 0"] -size "-[expr $minChW/2.000] 0"] ; list }
   if ![get_att $pbPoly is_empty] { create_placement_blockage -name ${myPBprefix}h_00p -boundary $pbPoly ; list }

   #myPBvbdr_00p - Block vertical channels, between hard_macros and core boundary, narrower than minChW (ignore any existing blockage)
   set bdrRng [compute_poly -objects1 [get_att [get_core_area] boundary] -objects2 [resize_poly -objects [get_att [get_core_area] boundary] -size "-$minChW 0"] -operation NOT]
   set pbPoly [compute_poly -objects1 $bdrRng -objects2 [resize_poly -objects $hmCells -size "$minChW 0"] -operation AND]
   set pbPoly [resize_poly -objects [compute_poly -objects1 $pbPoly -objects2 $hmCells -operation NOT] -size "0 $minChH"]
   set pbPolyV [resize_poly -objects $pbPoly -size "0 -$minChH"]
   #Fill gaps between myPBvbdr
   set pbPolyV [resize_poly -objects [resize_poly -objects $pbPolyV -size "0 $maxChH"] -size "0 -$maxChH"]
   if ![get_att $pbPoly is_empty] { create_placement_blockage -name ${myPBprefix}vbdr_00p -boundary $pbPolyV ; list }

   #myPBhbdr_00p - Block horizontal channels, between hard_macros and core boundary, shorter than minChH (ignore any existing blockage)
   set bdrRng [compute_poly -objects1 [get_att [get_core_area] boundary] -objects2 [resize_poly -objects [get_att [get_core_area] boundary] -size "0 -$minChH"] -operation NOT]
   set pbPoly [compute_poly -objects1 $bdrRng -objects2 [resize_poly -objects $hmCells -size "0 $minChH"] -operation AND]
   set pbPoly [resize_poly -objects [compute_poly -objects1 $pbPoly -objects2 $hmCells -operation NOT] -size "$minChW 0"]
   set pbPolyH [resize_poly -objects $pbPoly -size "-$minChW 0"]
   #Fill gaps between myPBhbdr
   set pbPolyH [resize_poly -objects [resize_poly -objects $pbPolyH -size "$maxChW 0"] -size "-$maxChW 0"]
   if ![get_att $pbPolyH is_empty] { create_placement_blockage -name ${myPBprefix}hbdr_00p -boundary $pbPolyH ; list }

   #myPBcbdr_00p - Block corner gaps, between hard_macros and core boundary, narrower than minChV respective shorter than minChH (ignore any existing blockage)
   set pbPoly [compute_poly -objects1 [resize_poly -objects $pbPolyV -size "0 $minChH"] -objects2 [resize_poly -objects $pbPolyH -size "$minChW 0"] -operation AND]
   if ![get_att $pbPoly is_empty] { create_placement_blockage -name ${myPBprefix}cbdr_00p -boundary $pbPoly ; list }

   #myPBv_30p - Partial block vertical channels w/ width between minChW & maxChW
   set hmBlkV2 [resize_poly -objects [resize_poly -objects $hmCells -size "[expr $maxChW/2.000] [expr $maxChH/2.000]"] -size "-[expr $maxChW/2.000] -[expr $maxChH/2.000]"]
   set hmBlkV2 [compute_poly -objects1 $hmBlkV2 -objects2 [resize_poly -objects [resize_poly -objects $hmCells -size "[expr $minChW/2.000] [expr $minChH/2.000]"] -size "-[expr $minChW/2.000] -[expr $minChH/2.000]"] -operation NOT]
   set pbPoly [compute_poly -objects1 $hmBlkV2 -objects2 $plcPoly -operation NOT]
   #if ![get_att $pbPoly is_empty] { create_placement_blockage -name myPBv_30p -blocked_percentage 30 -type allow_buffer_only -boundary $pbPoly }
   set XpbPoly [splitPoly -poly $pbPoly -xStep 30 -yStep 30]
   set i 0
   foreach_in_col p $XpbPoly {
      while { [sizeof_col [get_placement_blockage -quiet ${myPBprefix}v_30p_$i]] } { incr i }
      create_placement_blockage -name ${myPBprefix}v_30p_$i -blocked_percentage 30 -type allow_buffer_only -boundary $p ; incr i
   }

   #myPB_70p: $wholeAreaBlkPercentage
   if { $wholeAreaBlkPercentage > 0.000 } {
      set pbPoly [compute_poly -objects1 [get_att [get_core_area] boundary] -objects2 [compute_poly -objects1 $hmCells -objects2 [get_placement_blockages myPB*] -operation OR] -operation NOT]
      set XpbPoly [splitPoly -poly $pbPoly -xStep 50 -yStep 50]
      set i 0
      foreach_in_col p $XpbPoly {
         while { [sizeof_col [get_placement_blockage -quiet ${myPBprefix}_${wholeAreaBlkPercentage}p_$i]] } { incr i }
         create_placement_blockage -name ${myPBprefix}_${wholeAreaBlkPercentage}p_$i -blocked_percentage $wholeAreaBlkPercentage -type partial -boundary $p ; incr i
     }
  }
}
define_proc_attributes df_feint_add_blockages\
   -info "# Add placement blockages in the channels(including between macros & boundary) and over the whole area.
          # All channels smaller than minChH/W will be 100% blocked.
          # All channels between minChH/W & maxChH/W will be 30% blocked.
          # The rest of the area can be blocked" \
   -define_args {
      {-myPBprefix "Placement blockages prefix, defauly myPB" "" string optional}
      {-minChW "Minimum channel width, default 11.00" "" float optional}
      {-minChH "Minimum channel height, default 12.00" "" float optional}
      {-maxChW "Maximum channel width, default 28.00" "" float optional}
      {-maxChH "Maximum channel height, default 11.00" "" float optional}
      {-chBlkPercentage "Placement blockage percentage for channels, default 30" "" int optional}
      {-wholeAreaBlkPercentage "Placement blockage percentage for the rest of the area, default 0" "" int optional}
   }
#df_feint_add_blockages -chBlkPercentage 30

#########
#CN: Procs to emulatePG with metals shapes|blockages
### Emulate PG structure @ IP-lvel synthesis: df_feint_pgStackN6, df_feint_pgStackN4, df_feint_emulatePG
#PGname     ly:layer_name  o:offset(from left/bottom most edge)  w:width  st:step  sl:segment_length  ss:segment_space  so:segment_offset  bn:blkname  d:direction  c:comment
# For nets w/ st:SiteRow or st:CellRow, o:offset is horizontal offset{left,right} relative to core_area, instead of layer's non-prefered-direction offset
# sl, ss and so are used when PG is made from segments instead of a continuous stripe. In this case o:offset can come as a list {ox,oy}.
# Multiple layers accepted to reduce database "polution"
# Elements starting with "#" are considered comment line.
# Warrn: watch out to offsets(o), widths(w), segment_steps(st), segment_lenghts(sl), segment_spaces(ss) and segment_offsets values - stripes shoud be alligned to tracks to save routing resources
# WIP to allign o, st, so to track.
set df_feint_pgStackN6 {
{#pg:VDDCR_SOC ly:M13  o:0.684  w:0.360  st:2.736  bn:myRB_m11vdd  "c:M13 PG is missing"}
{#pg:VDDCR_SOC ly:M12  o:0.684  w:0.360  st:2.736  bn:myRB_m11vdd  "c:M12 PG is missing"}
{pg:VDDCR_SOC ly:M11  o:0.684  w:0.360  st:2.736  bn:myRB_m11vdd}
{pg:VSS       ly:M11  o:2.052  w:0.360  st:2.736  bn:myRB_m11vss}
{pg:VDDCR_SOC ly:M10  o:1.008  w:0.062  st:0.882  bn:myRB_m10vdd}
{pg:VSS       ly:M10  o:1.134  w:0.062  st:0.882  bn:myRB_m10vss}
{pg:VSS       ly:M9,M7,M5  o:0.684  w:0.038  st:1.368  bn:myRB_m9m7m5vss  "c:M9 PG is missing from Tile-level nlib"}
{pg:VDDCR_SOC ly:M9,M7,M5  o:1.368  w:0.038  st:1.368  bn:myRB_m9m7m5vdd  "c:M9 PG is missing from Tile-level nlib"}
{pg:VSS       ly:M8,M6,M4  o:{0.4965,1.120}  w:0.040  st:0.960  sl:0.375  ss:0.993  so:0.4965  bn:myRB_m8m6m4vss}
{pg:VDDCR_SOC ly:M8,M6,M4  o:{1.1805,1.120}  w:0.040  st:0.960  sl:0.375  ss:0.993  so:1.1805  bn:myRB_m8m6m4vdd}
{pg:VSS       ly:M3   o:0.572  w:0.024  st:1.364  bn:myRB_m3vss1}
{pg:VSS       ly:M3   o:0.704  w:0.024  st:1.364  bn:myRB_m3vss2}
{pg:VDDCR_SOC ly:M3   o:1.276  w:0.024  st:1.364  bn:myRB_m3vdd1}
{pg:VDDCR_SOC ly:M3   o:1.408  w:0.024  st:1.364  bn:myRB_m3vdd2}
{pg:VSS       ly:M2   o:{0.532,0.580}  w:0.020  st:0.480  sl:0.212  ss:1.152  so:0.532  bn:myRB_m2vss  "c:ON TOP OF M0 followpins"}
{pg:VDDCR_SOC ly:M2   o:{1.236,0.820}  w:0.020  st:0.480  sl:0.212  ss:1.152  so:1.236  bn:myRB_m2vdd  "c:ON TOP OF M0 followpins"}
{pg:VSS       ly:M1   o:0.5985  w:0.034  st:1.368  bn:myRB_m1vss }
{pg:VDDCR_SOC ly:M1   o:1.2825  w:0.034  st:1.368  bn:myRB_m1vdd }
{pg:FOLLOWPIN ly:M0   o:{-0.287,-0.287}  w:0.060  st:SiteRow  bn:myRB_fp  vdd:VDDCR_SOC  vss:VSS  "c:Folowing site-rows"}
}

set df_feint_pgStackN4_AON {
{pg:VSS       ly:M13  o:0.9640  w:0.550  st:3.876  bn:myRB_m13vss}
{pg:VDDCR_SOC ly:M13  o:1.9330  w:0.550  st:3.876  bn:myRB_m13vdd}
{pg:VDDCR_SOC ly:M13  o:2.9020  w:0.550  st:3.876  bn:myRB_m13vddc  "c: This is replacing VDDCR_SOC which doesn't exists at IP-level."}
{pg:VSS       ly:M12  o:2.2520  w:0.062  st:1.260  bn:myRB_m12vss}
{pg:VDDCR_SOC ly:M12  o:1.4960  w:0.062  st:1.260  bn:myRB_m12vdd}
{pg:VDDCR_SOC ly:M11  o:1.0765  w:0.076  st:1.444  bn:myRB_m11vdd           "c:(VSS over M12-VSS; VDDCR_SOC over M12-VDDCR_SOC)"}
{pg:VSS       ly:M10,M8,M6  o:2.0800  w:0.038  st:1.292  bn:myRB_m10m8m6vss "c:M10,M8,M6 compressed version"}
{pg:VDDCR_SOC ly:M10,M8,M6  o:1.4720  w:0.038  st:1.292  bn:myRB_m10m8m6vdd "c:M10,M8,M6 compressed version"}
{pg:VSS       ly:M9,M7,M5   o:0.9625  w:0.038  st:1.428  bn:myRB_m9m7m5vss  "c:M9,M7,M5 compressed version"}
{pg:VDDCR_SOC ly:M9,M7,M5   o:1.1905  w:0.038  st:1.428  bn:myRB_m9m7m5vdd  "c:M9,M7,M5 compressed version"}
{pg:VSS       ly:M4,M2   o:{0.9025,1.4700}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4m2vss  "c:ON TOP OF M0 followpins; M4,M2 compressed version"}
{pg:VDDCR_SOC ly:M4,M2   o:{0.9025,0.8400}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4m2vdd  "c:ON TOP OF M0 followpins; M4,M2 compressed version"}
{pg:VSS       ly:M4   o:{0.9025,1.3440}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4vssb}
{pg:VSS       ly:M4   o:{0.9025,1.5960}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4vssu}
{pg:VDDCR_SOC ly:M4   o:{0.9025,0.7140}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4vddb}
{pg:VDDCR_SOC ly:M4   o:{0.9025,0.9660}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4vddu}
{pg:VSS       ly:M2   o:{0.9025,0.6300}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m2vss1}
{pg:VSS       ly:M2   o:{0.9025,1.0500}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m2vss2}
{pg:VDDCR_SOC ly:M2   o:{0.9025,0.4200}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m2vdd1}
{pg:VDDCR_SOC ly:M2   o:{0.9025,1.2600}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m2vdd2}
{pg:VSS       ly:M3   o:0.9325  w:0.020  st:1.428  bn:myRB_m3vss1}
{pg:VSS       ly:M3   o:1.0585  w:0.020  st:1.428  bn:myRB_m3vss2}
{pg:VSS       ly:M3   o:1.1845  w:0.020  st:1.428  bn:myRB_m3vss3}
{pg:VDDCR_SOC ly:M3   o:0.9745  w:0.020  st:1.428  bn:myRB_m3vdd1}
{pg:VDDCR_SOC ly:M3   o:1.1005  w:0.020  st:1.428  bn:myRB_m3vdd2}
{pg:VDDCR_SOC ly:M3   o:1.2265  w:0.020  st:1.428  bn:myRB_m3vdd3}
{pg:VSS       ly:M1   o:0.9945  w:0.020  st:1.428  bn:myRB_m1vss}
{pg:VDDCR_SOC ly:M1   o:1.1985  w:0.020  st:1.428  bn:myRB_m1vdd}
{pg:FOLLOWPIN ly:M0   o:{-0.0485,-0.0485}  w:0.056  st:SiteRow  bn:myRB_fp  vdd:VDDCR_SOC  vss:VSS  "c:Folowing site-rows"}
}

set df_feint_pgStackN4 {
{pg:VSS       ly:M13  o:0.9640  w:0.550  st:3.876  bn:myRB_m13vss}
{pg:VDDINT_P1 ly:M13  o:1.9330  w:0.550  st:3.876  bn:myRB_m13vddi}
{#pg:VDDCR_SOC ly:M13  o:2.9020  w:0.550  st:3.876  bn:myRB_m13vddc}
{pg:VDDINT_P1 ly:M13  o:2.9020  w:0.550  st:3.876  bn:myRB_m13vddc  "c: This is replacing VDDCR_SOC which doesn't exists at IP-level."}
{pg:VSS       ly:M12  o:2.2520  w:0.062  st:1.260  bn:myRB_m12vss}
{pg:VDDINT_P1 ly:M12  o:1.4960  w:0.062  st:1.260  bn:myRB_m12vddi}
{pg:VDDINT_P1 ly:M11  o:1.0765  w:0.076  st:1.444  bn:myRB_m11vddi           "c:(VSS over M12-VSS; VDDINT_P1 over M12-VDDINT_P1)"}
{pg:VSS       ly:M10,M8,M6  o:2.0800  w:0.038  st:1.292  bn:myRB_m10m8m6vss  "c:M10,M8,M6 compressed version"}
{pg:VDDINT_P1 ly:M10,M8,M6  o:1.4720  w:0.038  st:1.292  bn:myRB_m10m8m6vddi "c:M10,M8,M6 compressed version"}
{pg:VSS       ly:M9,M7,M5   o:0.9625  w:0.038  st:1.428  bn:myRB_m9m7m5vss   "c:M9,M7,M5 compressed version"}
{pg:VDDINT_P1 ly:M9,M7,M5   o:1.1905  w:0.038  st:1.428  bn:myRB_m9m7m5vddi  "c:M9,M7,M5 compressed version"}
{pg:VSS       ly:M4,M2   o:{0.9025,1.4700}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4m2vss   "c:ON TOP OF M0 followpins; M4,M2 compressed version"}
{pg:VDDINT_P1 ly:M4,M2   o:{0.9025,0.8400}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4m2vddi  "c:ON TOP OF M0 followpins; M4,M2 compressed version"}
{pg:VSS       ly:M4   o:{0.9025,1.3440}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4vssb}
{pg:VSS       ly:M4   o:{0.9025,1.5960}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4vssu}
{pg:VDDINT_P1 ly:M4   o:{0.9025,0.7140}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4vddib}
{pg:VDDINT_P1 ly:M4   o:{0.9025,0.9660}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m4vddiu}
{pg:VSS       ly:M2   o:{0.9025,0.6300}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m2vss1}
{pg:VSS       ly:M2   o:{0.9025,1.0500}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m2vss2}
{pg:VDDINT_P1 ly:M2   o:{0.9025,0.4200}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m2vddi1}
{pg:VDDINT_P1 ly:M2   o:{0.9025,1.2600}  w:0.020  st:1.260  sl:0.354  ss:1.074  so:0.9025  bn:myRB_m2vddi2}
{pg:VSS       ly:M3   o:0.9325  w:0.020  st:1.428  bn:myRB_m3vss1}
{pg:VSS       ly:M3   o:1.0585  w:0.020  st:1.428  bn:myRB_m3vss2}
{pg:VSS       ly:M3   o:1.1845  w:0.020  st:1.428  bn:myRB_m3vss3}
{pg:VDDINT_P1 ly:M3   o:0.9745  w:0.020  st:1.428  bn:myRB_m3vddi1}
{pg:VDDINT_P1 ly:M3   o:1.1005  w:0.020  st:1.428  bn:myRB_m3vddi2}
{pg:VDDINT_P1 ly:M3   o:1.2265  w:0.020  st:1.428  bn:myRB_m3vddi3}
{pg:VSS       ly:M1   o:0.9945  w:0.020  st:1.428  bn:myRB_m1vss}
{pg:VDDINT_P1 ly:M1   o:1.1985  w:0.020  st:1.428  bn:myRB_m1vddi}
{pg:FOLLOWPIN ly:M0   o:{-0.0485,-0.0485}  w:0.056  st:SiteRow  bn:myRB_fp  vdd:VDDINT_P1  vss:VSS  "c:Folowing site-rows"}
}
#CN WIP... PG strack for power switches
#set pgPSstackN4 {
#{pg:VDDCR_SOC ly:M12  o:0.1900  w:0.062  st:0.126  "c:6 stripes over pwrSwitches"}
#{pg:VDDCR_SOC ly:M11  o:1.7225  w:0.076  st:1.444}
#{pg:VDDCR_SOC ly:M10  o:0.1900  w:0.038  st:0.076  "c:10 stripes over pwrSwitches"}
#{pg:VDDCR_SOC ly:M9   o:0.9435  w:0.038  st:0.228  "c:every 2nd track"}
#{pg:VDDCR_SOC ly:M8   o:0.1900  w:0.038  st:0.076  "c:10 stripes over pwrSwitches"}
#{pg:VDDCR_SOC ly:M7   o:0.9435  w:0.038  st:0.228  "c:every 2nd track"}
#{pg:VDDCR_SOC ly:M6   o:0.1900  w:0.038  st:0.076  "c:10 stripes over pwrSwitches"}
#{pg:VDDCR_SOC ly:M5   o:0.9435  w:0.038  st:0.228  "c:every 2nd track"}
#{pg:VDDCR_SOC ly:M4   o:0.1900  w:0.020  st:0.076  "c:15 stripes over pwrSwitches"}
#{pg:VDDCR_SOC ly:M3   o:0.9435  w:0.020  st:0.228  "c:every 2nd track"}
#{pg:VDDCR_SOC ly:M2   o:0.1900  w:0.020  st:0.076  "c:15 stripes over pwrSwitches"}
#{pg:VDDCR_SOC ly:M1   o:0.9435  w:0.020  st:0.048  "c:every track"}
#}

# Emulate PG structure through routing blockages for clock/reset/scan/data signals using above df_feint_pgStack (df_feint_pgStackN4 used for regular ip/tile)
# df_feint_emulatePG -pgStack $df_feint_pgStackN4 -use shape
# df_feint_emulatePG -pgStack $df_feint_pgStackN6 -use shape
proc df_feint_emulatePG { args } {
   suppress_message {ATTR-11}
   set_message_info -id {SEL-003} -limit 5
   global P
   parse_proc_arguments -args $args results
   foreach el [array names results] { set [string trimleft $el "-"] $results($el) }
   if  [info exists pwrSwitchLibCell] { puts "Error: pwrSwitchLibCell Not implemented." }
   if ![info exists pwrSwitchWidth] {   set pwrSwitchWidth  2.000 }
   if ![info exists pwrSwitchHeight] {  set pwrSwitchHeight 1.260 }
   if ![info exists pwrSwitchYDist] {   set pwrSwitchYDist 25.000 }
   if ![info exists hmHigestLayer] {    set hmHigestLayer  33 }
   if ![info exists use] {              set use            "blockage" }
   set dab [get_att [current_block] boundary] ;                    set cab [get_att [get_core_area] boundary]
   set blx [lindex [get_att [current_block] bbox] 0 0] ;           set bly [lindex [get_att [current_block] bbox] 0 1]
   set bux [lindex [get_att [current_block] bbox] 1 0] ;           set buy [lindex [get_att [current_block] bbox] 1 1]
   set siteH [get_att [index_col [get_site_rows] 0] site_height] ; set siteW [get_att [index_col [get_site_rows] 0] site_width]
   # Collect hard_macros as PG blockages for M0-M3
   if [sizeof_col [set m [get_cells -quiet -phys -filter is_hard_macro]]] { set hmBlkPoly [resize_poly -objects $m -size "[expr 9*$siteW] [expr $siteH-0.028]"] }

   foreach item $pgStack {
      if [regexp {^#}   $item n] {                   continue }
      if [regexp {pg:([a-zA-Z_0-9]*)}    $item pg] { set pg [lindex [split $pg ":"] 1] }                 else { puts "Error: Missing pg name in $item" ; return -1 }
      if [regexp {ly:(M[0-9M,]*)}        $item ly] { set ly [split [lindex [split $ly ":"] 1] ","] }     else { puts "Error: Mising layer in $item" ; return -1 }
      if [regexp {o:([0-9,\.\-\{\}]*)}   $item o] {  set o  [join [split [lindex [split $o ":"] 1] ,]] } else { set o 0.0000 }
      if [regexp {w:([0-9\.]*)}          $item w] {  set w  [lindex [split $w ":"] 1] }                  else { puts "Error: Missing width in $item" ; return -1 }
      if [regexp {st:([a-zA-Z0-9\.]*)}   $item st] { set st [lindex [split $st ":"] 1] }                 else { puts "Error: Missing step in $item" ; return -1 }
      if [regexp {sl:([0-9\.]*)}         $item sl] { set sl [lindex [split $sl ":"] 1] }                 else { unset -nocomplain sl }
      if [regexp {\ ss:([0-9\.]*)}       $item ss] { set ss [lindex [split $ss ":"] 1] }                 else { unset -nocomplain ss }
      if [regexp {c:(.*)}                $item c] {  set c  [lindex [split $c ":"] 1] }                  else { unset -nocomplain c }
      if [regexp {bn:([0-9a-zA-z_\.]*)}  $item bn] { set bn [lindex [split $bn ":"] 1] }                 else { unset -nocomplain bn }
      if [regexp {vss:([0-9a-zA-Z_\.]*)} $item vs] { set vs [lindex [split $vs ":"] 1] }                 else { unset -nocomplain vs }
      if [regexp {vdd:([0-9a-zA-Z_\.]*)} $item vd] { set vd [lindex [split $vd ":"] 1] }                 else { unset -nocomplain vd }
      #
      if { ([info exists sl] && ![info exists ss]) || (![info exists sl] && [info exists ss]) } { puts "Error: sl & ss must be used together: $item - ss=$ss ; sl=" ; continue }
      if { [llength [join $o]] == 1 } {      set o1 $o ;                   set o2 $o
      } elseif { [llength [join $o]] > 1 } { set o1 [lindex [join $o] 0] ; set o2 [lindex [join $o] 1]
      } else {                               puts "Error: Wrong offset $o." ; continue }

      foreach l $ly {
         if { [sizeof_col [get_layers -quiet $l]] == 0 } { puts "Error: Layer $l doesn't exist - skip it." ; continue }
         puts "Creating $l:$pg ${use}s..." ; unset -nocomplain rbPoly
         # Collect PG blockages for $l
         if [sizeof_col [set pgBlks [get_routing_blockages -quiet -filter layer.name==$l]]] {
            if { [info exists hmBlkPoly] && [get_att [get_layers $l] layer_number]<=$hmHigestLayer } {    set pgBlkPolyL [compute_poly -objects1 $hmBlkPoly -objects2 $pgBlks -operation OR]
            } else {                                                                                      set pgBlkPolyL [create_poly_rect -boundary [get_att $pgBlks boundary]] }
         } elseif { [info exists hmBlkPoly] && [get_att [get_layers $l] layer_number]<=$hmHigestLayer } { set pgBlkPolyL $hmBlkPoly
         } else {                                                                                         unset -nocomplain pgBlkPolyL }

         # PG-Followpins:
         if [regexp -nocase {^CellRow$|^SiteRow$} $st] {
            if { [info exists fpPolyG] || [info exists fpPolyP] } { puts "Warning: Only first site_rows/cell_rows is accepted." ; continue }
            if { [sizeof_col [get_site_rows]] == 0 } {              puts "Warning: No site_rows/cell_rows are present." ; continue }
            # Collect power
            foreach_in_col r [get_site_rows -filter site_orientation=="R0"] {
               set poly [resize_poly -objects $r -size "0 [expr $w/2.000-[get_att $r site_height]] 0 [expr $w/2.0000]"]
               if [info exists fpPolyP] { set fpPolyP [compute_poly -objects1 $fpPolyP -objects2 $poly -operation OR]
               } else {                   set fpPolyP $poly }
            }
            if ![info exists fpPolyP] {   puts "Error: Missing R0 site_rows/cell_rows." ; continue }
            # Collect ground
            foreach_in_col r [get_site_rows -filter site_orientation=="MX"] {
               set poly [resize_poly -objects $r -size "0 [expr $w/2.0000-[get_att $r site_height]] 0 [expr $w/2.0000]"]
               if [info exists fpPolyG] { set fpPolyG [compute_poly -objects1 $fpPolyG -objects2 $poly -operation OR]
               } else {                   set fpPolyG $poly }
            }
            if ![info exists fpPolyG] {   puts "Error: Missing MX site_rows/cell_rows." ; continue }
            # Stay inside core area
            set fpPolyP [compute_poly -objects1 $fpPolyP -objects2 [resize_poly -objects $cab -size "$o1 [expr -$siteW/2.000] $o2 [expr -$siteH/2.000]"] -operation AND]
            set fpPolyG [compute_poly -objects1 $fpPolyG -objects2 [resize_poly -objects $cab -size "$o1 [expr -$siteH/2.000] $o2 [expr -$siteH/2.000]"] -operation AND]
            # Avoid followpins PG blockages if any
            if [info exists pgBlkPolyL] { set fpPolyP [compute_poly -objects1 $fpPolyP -objects2 $pgBlkPolyL -operation NOT]
                                          set fpPolyG [compute_poly -objects1 $fpPolyG -objects2 $pgBlkPolyL -operation NOT]
            }
            if { $use == "blockage" } {
                                                                    create_routing_blockage       -layers $l -boundary $fpPolyP -net_types "clock reset scan signal" -name_prefix ${bn}_${vd}
                                                                    create_routing_blockage       -layers $l -boundary $fpPolyG -net_types "clock reset scan signal" -name_prefix ${bn}_${vs}
            } else { foreach r [get_att $fpPolyP poly_rects.bbox] { create_shape -shape_type rect -layer  $l -boundary $r -net $vd -shape_use follow_pin }
                     foreach r [get_att $fpPolyG poly_rects.bbox] { create_shape -shape_type rect -layer  $l -boundary $r -net $vs -shape_use follow_pin } }
            continue
         }

         # PG-Stripes:
         if { [get_att [get_layers $l] routing_direction] == "vertical" } {
         # Vertical PG
            if [info exists sl] {
               # Non-continous PG from $o to the right-most edge
               unset -nocomplain colPoly rowPoly
               for { set j $o2 } { [expr $j+$sl]<$buy } { set j [expr $j+$sl+$ss] } {
                  unset -nocomplain b ; lappend b [list $j $bly] ; lappend b "[expr $j+$sl] $bux"
                  if [info exists rowPoly] { set rowPoly [compute_poly -objects1 $rowPoly -objects2 [create_poly_rect -boundary $b] -operation OR]
                  } else {                   set rowPoly [create_poly_rect -boundary $b] }
               }
               for { set i $o1 } { [expr $i+2*$w]<$bux } { set i [expr $i+$st] } {
                  unset -nocomplain b ; lappend b [list $blx [expr $i-$w/2.000]] ; lappend b "$buy [expr $i+$w/2.000]"
                  if [info exists colPoly] { set colPoly [compute_poly -objects1 $colPoly -objects2 [create_poly_rect -boundary $b] -operation OR]
                  } else {                   set colPoly [create_poly_rect -boundary $b] }
               }
               set rbPoly [compute_poly -objects1 $rowPoly -objects2 $colPoly -operation AND]
            } else {
               # Continous PG from $o to the right-most edge
               for { set i $o } { [expr $i+2*$w]<$bux } { set i [expr $i+$st] } {
                  unset -nocomplain b ; lappend b "[expr $i-$w/2.000] $bly" ; lappend b "[expr $i+$w/2.000] $buy"
                  if [info exists rbPoly] { set rbPoly [compute_poly -objects1 $rbPoly -objects2 [create_poly_rect -boundary $b] -operation OR]
                  } else {                  set rbPoly [create_poly_rect -boundary $b] }
               } ;# right-most edge
            }
         } elseif { [get_att [get_layers $l] routing_direction] == "horizontal" } {
         # Horizontal PG
            if [info exists sl] {
               # Non-continous PG from $o to top-most edge
               unset -nocomplain colPoly rowPoly
               for { set j $o1 } { [expr $j+$sl]<$bux } { set j [expr $j+$sl+$ss] } {
                  unset -nocomplain b ; lappend b [list $j $bly] ; lappend b "[expr $j+$sl] $buy"
                  if [info exists colPoly] { set colPoly [compute_poly -objects1 $colPoly -objects2 [create_poly_rect -boundary $b] -operation OR]
                  } else {                   set colPoly [create_poly_rect -boundary $b] }
               }
               for { set i $o2 } { [expr $i+2*$w]<$buy } { set i [expr $i+$st] } {
                  unset -nocomplain b ; lappend b [list $blx [expr $i-$w/2.000]] ; lappend b "$bux [expr $i+$w/2.000]"
                  if [info exists rowPoly] { set rowPoly [compute_poly -objects1 $rowPoly -objects2 [create_poly_rect -boundary $b] -operation OR]
                  } else {                   set rowPoly [create_poly_rect -boundary $b] }
               }
               set rbPoly [compute_poly -objects1 $rowPoly -objects2 $colPoly -operation AND]
            } else {
               # Continous PG from $o to top-most edge
               for { set i $o } { [expr $i+2*$w]<$buy } { set i [expr $i+$st] } {
                  unset -nocomplain b ; lappend b [list $blx [expr $i-$w/2.000]] ; lappend b "$bux [expr $i+$w/2.000]"
                  if [info exists rbPoly] { set rbPoly [compute_poly -objects1 $rbPoly -objects2 [create_poly_rect -boundary $b] -operation OR]
                  } else {                  set rbPoly [create_poly_rect -boundary $b] }
               } ;# top-most edge
            }
         } else { puts "Error: Routing direction [get_att [get_layers $l] routing_direction] not supported" ; continue }
         # Avoid PG under macros
         if [info exists pgBlkPolyL] { set rbPoly [compute_poly -objects1 $rbPoly -objects2 $pgBlkPolyL -operation NOT] }
         # Stay inside core area
         if { $P(TECHNO_NAME) == "N6" } {
            set rbPoly [compute_poly -objects1 $rbPoly -objects2 [resize_poly -objects $cab -size "[expr -8*$siteW] [expr -$siteH/2.000]"] -operation AND]
         } else {
            set rbPoly [compute_poly -objects1 $rbPoly -objects2 [resize_poly -objects $cab -size "[expr -10*$siteW] [expr -$siteH/2.000]"] -operation AND]
         }
         if { $use == "blockage" } {                                               create_routing_blockage       -layers $l -boundary $rbPoly -net_types "clock reset scan signal" -name_prefix $bn
         } else {                    foreach b [get_att $rbPoly poly_rects.bbox] { create_shape -shape_type rect -layer  $l -boundary $b -net $pg -shape_use stripe } }
      } ;# end looping through $ly
   } ;# end looping through PG metal stack
   unsuppress_message {ATTR-11}
}
define_proc_attributes df_feint_emulatePG \
    -info "Emulate PG structure through routing blockages for clock/reset/scan/data signals or metal shapes using above df_feint_pgStack (df_feint_pgStackN4 used for regular ip/tile)." \
    -define_args {
       {-pgStack          "PG metals stack definition" "" string required}
       {-use              "Use routing blockages or metal shapes" "" one_of_string {optional value_help {values {blockage shape}}}}
       {-pwrSwitchLibCell "WIP... If exists it has a higher priority than pwrSwitchWidth/Height" "" string optional}
       {-pwrSwitchWidth   "WIP... Default power switch width 2.0um" "" float optional}
       {-pwrSwitchHeight  "WIP... Default power switch height 1.26um" "" float optional}
       {-pwrSwitchYDist   "WIP... Default power switch row vertical distance is 25um" "" float optional}
       {-hmHigestLayer    "Default maximum layer no used for hard macros is 33" "" float optional}
    }
#      {-pgPSstack        "" "" string required}


# AI begin procs

########################################################################################
########################################################################################
# AI 
# Usage: reporting levels of logic in the design for paths from/to IOs and R2R
# Arguments used: please see below define_proc_attributes df_feint_reportLOL
# Output files
#     $reports_dir_path/lol.bit.rpt     -> max logic levels foreach I/O port 
#     $reports_dir_path/lol.bus.rpt     -> max of logic levels foreach I/O bus
#     $reports_dir_path/lol.bus_bit.rpt -> max logic levels foreach I/O port from
#                                           each bus
#     $report_dir_path/lol.r2r.rpt      -> max logic levels R2R     
# Exemples of usage
#     df_feint_report_lol
#     df_feint_report_lol -inc_CK_to_Q_arc -inc_buff_inv
#     df_feint_report_lol -r2r_paths_no 10 
#     df_feint_report_lol -reports_dir_path rpts
# Also counts comb cells like SPN* 
########################################################################################
########################################################################################
proc df_feint_reportLOL { args } {
  parse_proc_arguments -args $args callArgs
  foreach item [array names callArgs] { set [string trimleft $item "-"] $callArgs($item) }

  if ![info exists inc_buff_inv]      { set inc_buff_inv       0        } 
  if ![info exists work_on_crt_block] { set work_on_crt_block  0        }
  if ![info exists inc_CK_to_Q_arc]   { set inc_CK_to_Q_arc    0        }
  if ![info exists skip_IO_paths]     { set skip_IO_paths      0        } 
  if ![info exists skip_r2r_paths]    { set skip_r2r_paths     0        }
  if ![info exists debug_mode]        { set debug_mode         0        }

  if $debug_mode { 
    puts "INFO: df_feint_reportLOL START [clock format [clock seconds] -format "%y-%m-%d %H:%M:%S"] "
    puts "INFO: df_feint_reportLOL proc started to run with to following args:"
    puts "Args used: "
    puts "inc_buff_inv = $inc_buff_inv"
    puts "work_on_crt_block = $work_on_crt_block"
    puts "inc_CK_to_Q_arc = $inc_CK_to_Q_arc"
    puts "skip_IO_paths = $skip_IO_paths"
    puts "skip_r2r_paths = $skip_r2r_paths"
    puts "reports_dir_path = $reports_dir_path"
    puts "prefix = $prefix"
    puts "lol_period = $lol_period"
    puts "r2r_paths_no = $r2r_paths_no"
    puts "cell_delay = $cell_delay"
  }

  if [catch { if !$skip_IO_paths {
                                    set fo_lol_bit      [open "${reports_dir_path}/${prefix}.bit.rpt" w]
                                    set fo_lol_bus      [open "${reports_dir_path}/${prefix}.bus.rpt" w]
                                    set fo_lol_bus_bit  [open "${reports_dir_path}/${prefix}.bus_bit.rpt" w]
              }
              
              if !$skip_r2r_paths {   set fo_lol_r2r      [open "${reports_dir_path}/${prefix}.r2r.rpt" w] }
            } ] { puts "Error: Can't open files for writing in ${reports_dir_path}" ; return -1 }


  suppress_message POW-034
  # create a temporary block where to work 
  if !$work_on_crt_block {
    set goldenBlock [current_block]
    if [ sizeof_col [get_block -quiet tmpBlock] ] { remove_block -force tmpBlock }
    copy_block -from $goldenBlock -to tmpBlock
    current_block tmpBlock
  }
  
  # Redefine clocks which should have been redefined in FxSynthesize.I2Place.Constraints32.sdc
  foreach_in_col clk [get_clocks] {
     set src [get_att -quiet $clk sources]
     set nme [get_att -quiet $clk name]
     if { [sizeof_col $src]==0 } { create_clock -name $nme -period $lol_period -waveform "0 [expr $lol_period/2.000]"
     } else {                      create_clock -name $nme -period $lol_period -waveform "0 [expr $lol_period/2.000]" $src }
  }
  unsuppress_message UIC-034

  # Cleaning up database from any unwanted values that could have an impact on counting logic levels
  remove_clock_latency -clock [get_clocks] [get_pins -of_objects [get_cells -hierarchical -filter is_sequential] -f is_clock_pin ]
  remove_clock_uncertainty -from [get_clocks] -to [get_clocks] ; #AI  
  set_clock_transition 0 [all_clocks] ; #AI 
  reset_timing_derate
  set_ideal_network -no_propagate [get_nets -hierarchical *]
  set_pocvm_corner_sigma 0

  #
  update_timing -full
  #  
  unset -nocomplain sid sod
  foreach_in_col p [remove_from_col [get_ports -filter port_direction=="in"&&port_type=="signal"] [get_ports -quiet [get_att -quiet [get_clocks] sources]]] {
#    Set I/O delay foreach clock
     set arrW [get_att $p arrival_window]
     set first 1
     foreach c [lindex $arrW 0] {
        set clk [lindex $c 0] ; set edge [lindex $c 1]
        if { $clk=="" } {        set clk [lindex [get_att -quiet [get_clocks] name] 0] }
                                 set cmd "set_input_delay -clock $clk"
        if {$edge=="neg_edge"} { append cmd " -clock_fall" }
        if {$first} {            set first 0
        } else {                 append cmd " -add_delay" }
                                 append cmd " 0.0 [get_att $p name]"
        lappend sid $cmd
     }
  }
  foreach_in_col p [get_ports -filter port_direction=="out"&&port_type=="signal"] {
#    Set I/O delay foreach clock
     set arrW [get_att $p arrival_window]
     set first 1
     foreach c [lindex $arrW 0] {
        set clk [lindex $c 0] ;  set edge [lindex $c 1]
        if { $clk=="" } {        set clk [lindex [get_att [get_att -quiet [get_clocks] sources] name] 0] }
                                 set cmd "set_output_delay -clock $clk"
        if {$edge=="neg_edge"} { append cmd " -clock_fall" }
        if {$first} {            set first 0
        } else {                 append cmd " -add_delay" }
                                 append cmd " 0.0 [get_att $p name]"
        lappend sod $cmd
     }
  }
  # 
  set ports [get_ports -filter port_type=="signal"] ; list
  set ports [remove_from_col $ports [get_ports -quiet [get_att [get_clocks] sources]]] ; list 

  #AI: ICGs are placed in setupCells to ensure that library setup time for them is 0. 
  set mySeqInstances  [get_cells -quiet -hierarchical -filter !is_hierarchical&&is_sequential&&!is_integrated_clock_gating_cell&&name!~"*MEM*mem*SRAM*"&&name!~"*d0nt_sync*"] ; list
  set myCombInstances [get_cells -quiet -hierarchical -filter !is_hierarchical&&!is_sequential] ; list
  #AI: Warning: There is no 'setup' check arc between pins 'spf_pg/SPFBANK7/LPFMEM_QUAD11_mem_0_0_SRAM/RSCLK' and 'spf_pg/SPFBANK7/LPFMEM_QUAD11_mem_0_0_SRAM/RM0'.
  set setupCells      [get_cells -quiet -hierarchical -filter !is_hierarchical&&is_sequential&&name!~"*MEM*mem*SRAM*"] ; list
  #AI: There is neccesary to disable timing arcs from D inputs to outputs of latches to make D endpoints 
  set myLatInstances  [get_cells -quiet -hierarchical -filter !is_hierarchical&&is_sequential&&is_positive_level_sensitive] ; list 
  
  # Add a unit delay on all of the comb cells (skip comb clock cells like CKNR2D2AMDBWP143M169H3P48CPD which are defined as seq ICGs)
  foreach_in_collection instance $myCombInstances {
     #set myInPins [get_pins -of_objects $instance -filter @pin_direction==in&&@name!=VSS&&@name!=VDD&&@name!=VBP&&@name!=VBN]
     set myInPins  [get_pins -of_objects $instance -filter pin_direction=="in"&&port_type=="signal"] ; list 
     set myOutPins [get_pins -of_objects $instance -filter pin_direction=="out"] ; list 
     #Tie-off cells & other physical cells need to be excluded as they might not have inputs.
     if { [sizeof_collection $myInPins] != 0 && [sizeof_collection $myOutPins] != 0} {
        #To avoid warning about missing timing arcs of some "multi-bit one-hot muxes" in the library.
        foreach_in_col myInPin $myInPins {
           foreach_in_col myOutPin $myOutPins {
              if { !$inc_buff_inv && ([get_att $instance ref_block.is_buffer] || [get_att $instance ref_block.is_inverter]) } {
                 if [sizeof_col [get_timing_arcs -quiet -from $myInPin -to $myOutPin]] { set_annotated_delay -cell 0.00 -from $myInPin -to $myOutPin }
              } else {
                 if [sizeof_col [get_timing_arcs -quiet -from $myInPin -to $myOutPin]] { set_annotated_delay -cell $cell_delay -from $myInPin -to $myOutPin }
              }
           }
        }
     }
  }

  
  # Add a unit delay on all of the seq cells' async-inputs to output timing arc
  foreach_in_collection instance $mySeqInstances {
     set myInPins [get_pins -of_objects $instance -filter pin_direction=="in"&&port_type=="signal"&&(is_async_pin||lib_pin.is_async_pin||lib_pin.is_clock_pin||is_clock_pin||is_clock_gating_clock||is_clock_used_as_clock)] ; list
     set myOutPins [get_pins -of_objects $instance -filter pin_direction=="out"] ; list
     if [sizeof_col $myInPins] { set_annotated_delay -cell [ expr { $inc_CK_to_Q_arc ? $cell_delay : 0 } ] -from $myInPins -to $myOutPins }
  }
  
  # No delay between setup and output. (FF & latches; excluding async inputs: Warning: There is no 'setup' check arc between pins 'ncm_pg/FtiRdRspDatBuf07/I_d0nt_sse_en_X/CP' and 'ncm_pg/FtiRdRspDatBuf07/I_d0nt_sse_en_X/CDN'.)
  #remove_output_delay [get_pins -of_objects $setupCells -filter @pin_direction==in&&@name!=CLK&&@name!=CK&&@name!=CP]
  remove_output_delay [get_pins -of_objects $setupCells -filter pin_direction=="in"&&(!lib_pin.is_clock_pin&&!is_clock_pin&&!is_clock_used_as_clock)]
  foreach_in_collection mCell $setupCells {
     #set mClkPins [get_pins -of_objects $mCell -filter @pin_direction==in&&(@name==CLK||@name==CK||@name==CP)]
     set mClkPins  [get_pins -of_objects $mCell -filter pin_direction=="in"&&(lib_pin.is_clock_pin||is_clock_pin||is_clock_used_as_clock)] ; list 
     #set mDataPins [get_pins -of_objects $mCell -filter @pin_direction==in&&@name!=CLK&&@name!=CK&&name!=CP]
     set mDataPins  [get_pins -of_objects $mCell -filter pin_direction=="in"&&port_type=="signal"&&(!lib_pin.is_clock_pin&&!is_clock_pin&&!lib_pin.is_async_pin&&!is_async_pin&&!is_clock_used_as_clock)] ; list 
#    There is no setup check timing arc between gate and "mux's output selection of AOI seq cell".
#                N6:        |N5          |N5/N3: (S0/S1 are clock/gate-enable pins for these latches)
     if [regexp {LDPQM8AOI22|MB8LHQ2AOI22|MB8LHQAOI22} [get_attribute $mCell ref_name]] { set mDataPins [remove_from_col $mDataPins [get_pins -phys -of $mCell -filter name=="S0"||name=="S1"]] }
     if { [sizeof_collection $mClkPins] != 0 && [sizeof_collection $mDataPins] != 0 } {    set_annotated_check -setup -from $mClkPins -to $mDataPins 0 }
  }

  unset -nocomplain timArcs

  foreach_in_collection lat $myLatInstances {
    set myInPins  [get_pins -of_objects $lat -filter pin_direction=="in"&&port_type=="signal"&&(!lib_pin.is_clock_pin&&!is_clock_pin&&!lib_pin.is_async_pin&&!is_async_pin&&!is_clock_used_as_clock)] ; list
    set myInPins  [filter_collection $myInPins name=~"D?"||name=~"S?" ]
    set myOutPins [get_pins -of_objects $lat -filter pin_direction=="out"&&port_type=="signal"] ; list

    if [sizeof_col $myInPins] {
      set myTm      [get_timing_arcs -quiet -from $myInPins -to $myOutPins -filter !is_invalid&&!is_disabled]  ; list
      if [sizeof_col $myTm]  { append_to_collection timArcs $myTm } 
    } 
  }
  
  if $debug_mode {  puts "start set_disable_timing: [clock format [clock seconds] -format "%y-%m-%d %H:%M:%S"]"   }
  set_disable_timing $timArcs
  if $debug_mode {  puts "end command: [clock format [clock seconds] -format "%y-%m-%d %H:%M:%S"]"  }

  foreach cmd $sid { eval $cmd }
  foreach cmd $sod { eval $cmd }

  # this part will find out the max LOL on all paths: FF -> port ; port -> FF
  if !$skip_IO_paths {
    set ports [get_ports -filter port_type==signal]
    set ports [remove_from_col $ports [get_ports -quiet [get_att [get_clocks] sources]]] 
    
    unset -nocomplain timing_paths_coll 
    # extracting timing paths data 
    # more efficient this way in order to sort collections 
    # further than to sort any other type of data structure

    set ports_to_analyze [sizeof_col $ports]
    puts "There are $ports_to_analyze ports from which timing paths will be extracted"

    foreach_in_col p $ports { 
      if { [get_att $p pin_direction] eq "in" } { 
        redirect "/dev/null" { append_to_coll timing_paths_coll [get_timing_path -from $p] }
      } else { 
        redirect "/dev/null" { append_to_coll timing_paths_coll [get_timing_path -to $p]   }
      }
      incr ports_to_analyze -1
      if [expr {$ports_to_analyze % 100 == 0}] { puts "Remaining ports: $ports_to_analyze" }  
    }
 
    # writing lol_bit.rpt - all ports sorted descending by lol
    set timing_paths_sorted_coll [sort_collection -descending $timing_paths_coll total_cell_delay] ; list  
    set visited_bus_coll ""

    foreach_in_col tp $timing_paths_sorted_coll { 
      # test wich point is a port in order to know if startpoint or endpoint is gonna give infos about name, pin no etc
      if { [get_attribute -quiet [get_attribute $tp startpoint] port_direction] eq "in" } {
        set point [get_attribute $tp startpoint] ; list
        set full_name [get_attribute $point full_name] ; list
        set lol [expr { int( int(ceil( [get_attribute $tp total_cell_delay] )) / $cell_delay)}] ; list
        puts $fo_lol_bit "$full_name ([get_attribute $point direction]): $lol"
     
        if { ([get_attribute -quiet $point is_bus_bit] eq "true") && ([sizeof_col [filter_collection $visited_bus_coll name==[get_object_name [get_attribute -quiet $point bus]] ]] eq "0") } {
          set bus_name [get_object_name [get_attribute -quiet $point bus]] ; list   
          set bus_tp [filter_collection $timing_paths_sorted_coll startpoint.name=~"${bus_name}*"] ; list
          set bus_lol [expr { int( int(ceil([get_attribute [index_col $bus_tp 0] total_cell_delay])) / $cell_delay) } ]  ; list
          puts $fo_lol_bus "${bus_name} ([get_attribute $point direction]): ${bus_lol}" 
          foreach_in_col pin_tp $bus_tp {
            set pin_name [get_attribute $pin_tp startpoint.full_name] ; list
            set pin_lol [expr { int( int(ceil( [get_attribute $pin_tp total_cell_delay] )) / $cell_delay)}] ; list
            puts $fo_lol_bus_bit "${pin_name} ([get_attribute [get_attribute $pin_tp startpoint] direction]): ${pin_lol}" 
          }
          set visited_bus_coll [add_to_collection -unique $visited_bus_coll [get_attribute $point bus]] ; list
        }

      } else {
        if { [get_attribute -quiet [get_attribute $tp endpoint] port_direction] eq "out" } {
          set point [get_attribute $tp endpoint] ; list
          set full_name [get_attribute $point full_name] ; list
          set lol [expr { int( int(ceil( [get_attribute $tp total_cell_delay] )) / $cell_delay) }] ; list
          puts $fo_lol_bit "$full_name ([get_attribute $point direction]): $lol"
        }

        if { ([get_attribute -quiet $point is_bus_bit] eq "true") && ([sizeof_col [filter_collection $visited_bus_coll name==[get_object_name [get_attribute -quiet $point bus]] ]] eq "0") } {
          set bus_name [get_object_name [get_attribute -quiet $point bus]] ; list   
          set bus_tp [filter_collection $timing_paths_sorted_coll endpoint.name=~"${bus_name}*"] ; list
          set bus_lol [expr { int( int(ceil([get_attribute [index_col $bus_tp 0] total_cell_delay])) / $cell_delay) } ]  ; list
          puts $fo_lol_bus "${bus_name} ([get_attribute $point direction]): ${bus_lol}" 
          foreach_in_col pin_tp $bus_tp {
            set pin_name [get_attribute $pin_tp endpoint.full_name] ; list
#           set pin_lol [expr { int(ceil( [get_attribute $pin_tp total_cell_delay] )) }] ; list
            set pin_lol [expr { int( int(ceil( [get_attribute $pin_tp total_cell_delay] )) ) / $cell_delay}] ; list
            puts $fo_lol_bus_bit "${pin_name} ([get_attribute [get_attribute $pin_tp endpoint] direction]): ${pin_lol}" 
          }
          set visited_bus_coll [add_to_collection -unique $visited_bus_coll [get_attribute $point bus]] ; list
        }
      }
    }
    close $fo_lol_bus
    close $fo_lol_bit
    close $fo_lol_bus_bit
  } 
  # analyze r2r paths to extract lol_number 
  if !$skip_r2r_paths {
    unset -nocomplain r2r_tp_col  
    set my_clocks [all_clocks]
    puts "There will be analyzed $r2r_paths_no between next clock domains: [get_object_name $my_clocks]"
    set iteration_count [expr { [sizeof_col $my_clocks] * [sizeof_col $my_clocks] }]  
    puts "Total number of interations: $iteration_count"

    # extract R2R timing paths
    foreach_in_col sourceClk $my_clocks {
      set start_regs [filter_collection [all_registers -clock [get_object_name $sourceClk]] !is_integrated_clock_gating_cell&&name!~"*d0nt_sync*"]
      foreach_in_col destClk $my_clocks {
        puts "[get_object_name $sourceClk]->[get_object_name $destClk]"
        set end_regs [filter_collection [all_registers -clock [get_object_name $destClk]] name!~"*d0nt_sync*"]
        if { ![sizeof_col $end_regs] || ![sizeof_col $start_regs] } { incr iteration_count -1 ; puts "Remaining iterations: $iteration_count" ; continue }
        redirect "/dev/null" { 
           set timing_paths_coll [get_timing_path -from $start_regs -to $end_regs -max $r2r_paths_no]  
        } 
        if [sizeof_col $timing_paths_coll] { 
          if $debug_mode {
            puts [get_attribute $timing_paths_coll startpoint_clock.name] 
            puts [get_attribute $timing_paths_coll endpoint_clock.name]
          }
          set timing_paths_coll [sort_collection -descending $timing_paths_coll total_cell_delay]
          lappend r2r_tp_col $timing_paths_coll
        }
        incr iteration_count -1
        puts "Remaining iterations: $iteration_count"
      }
    }
  
    # print data 
    foreach timing_path_coll $r2r_tp_col {
      set sourceClk [get_attribute [index_col $timing_path_coll 0] startpoint_clock.name]
      set destClk   [get_attribute [index_col $timing_path_coll 0] endpoint_clock.name  ]
      puts $fo_lol_r2r "Top $r2r_paths_no paths from $sourceClk to $destClk sorted descending by levels of logic"
      set id 1
      foreach_in_col tp $timing_path_coll {
        set startpoint  [get_attribute $tp startpoint.full_name]
        set endpoint    [get_attribute $tp endpoint.full_name]
        set lol_no      [expr { int( int(ceil( [get_attribute $tp total_cell_delay] )) / $cell_delay) } ] 
      
        puts $fo_lol_r2r "#$id"
        puts $fo_lol_r2r "$lol_no\t$startpoint\n\t\t$endpoint\n"
        
        incr id
      }
    }
    
    close $fo_lol_r2r
  }
 
  if $debug_mode { 
    if [file exists "$reports_dir_path/DEBUG_LOL.nlib" ] {
      exec rm -rf "$reports_dir_path/DEBUG_LOL.nlib" 
    }
    copy_block -from_block [current_block] -to "$reports_dir_path/DEBUG_LOL.nlib:DEBUG_LOL_[get_attribute [current_block] name]"
    save_block "$reports_dir_path/DEBUG_LOL.nlib:DEBUG_LOL_[get_attribute [current_block] name]"
    close_lib -force "$reports_dir_path/DEBUG_LOL.nlib" 
  }

  if !$work_on_crt_block {
    if [sizeof_col [get_blocks tmpBlock]] { 
       close_block -force tmpBlock
       # remove_blocks -force tmpBlock 
    }   
    current_block $goldenBlock
  }
  
  unsuppress_message POW-034
  if $debug_mode {  puts "INFO: df_feint_reportLOL END [clock format [clock seconds] -format "%y-%m-%d %H:%M:%S"] " }
}

define_proc_attributes df_feint_reportLOL \
  -info "Report levels of logic. " \
  -define_args {
    {-reports_dir_path "Directory where all files will be written - Default: data" "" string {optional {default "./data/"}} } 
    {-prefix "Prefix for generated files - Default: lol" "prefix" string {optional {default "lol"} }}
    {-inc_buff_inv "Counting buff/inv - Default: false" "" boolean optional }
    {-work_on_crt_block "Work on copy instead of current block - Default: true" "" boolean optional }
    {-inc_CK_to_Q_arc "Count CK->Q timing arc as 1 LOL - Default: false" "" boolean optional } 
    {-skip_IO_paths "Skip IO paths reporting - Default: false" "" boolean optional }
    {-skip_r2r_paths "Skip r2r paths reporting - Default: false" "" boolean optional }
    {-r2r_paths_no  "No of r2r paths to report - Default: 100" "" int {optional {default 100} } }
    {-lol_period "Define a LOL period against which LOL slack will be reported - Default: 32" "" int {optional {default 32}} }
    {-cell_delay "Define value of delay foreach cell - Default: 1" "" int {optional {default 1}} }
    {-debug_mode "Keep modified block in reports_dir_path/DEBUG_LOL.nlib - Default: false" "" boolean optional }
  }



# end AI
