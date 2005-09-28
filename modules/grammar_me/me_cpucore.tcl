# -*- tcl -*-
# ### ### ### ######### ######### #########
## Package description

## Implementation of ME virtual machines based on state values
## manipulated by the commands according to the match
## instructions. Allows for implementation in C.

# ### ### ### ######### ######### #########
## Requisites

namespace eval grammar::me::cpu::core {}

# ### ### ### ######### ######### #########
## Implementation, API. Ensemble command.

proc ::grammar::me::cpu::core {cmd args} {
    # Dispatcher for the ensemble command.
    variable core::cmds
    return [uplevel 1 [linsert $args 0 $cmds($cmd)]]
}

namespace eval grammar::me::cpu::core {
    variable cmds

    # Mapping from cmd names to procedures for quick dispatch. The
    # objects will shimmer into resolved command references.

    array set cmds {
	disasm ::grammar::me::cpu::core::disasm
	asm    ::grammar::me::cpu::core::asm
	new    ::grammar::me::cpu::core::new
	lc     ::grammar::me::cpu::core::lc
	tok    ::grammar::me::cpu::core::tok
	sv     ::grammar::me::cpu::core::sv
	ok     ::grammar::me::cpu::core::ok
	error  ::grammar::me::cpu::core::error
	ast    ::grammar::me::cpu::core::ast
	halted ::grammar::me::cpu::core::halted
	code   ::grammar::me::cpu::core::code
	eof    ::grammar::me::cpu::core::eof
	put    ::grammar::me::cpu::core::put
	run    ::grammar::me::cpu::core::run
    }
}

# ### ### ### ######### ######### #########
## Ensemble implementation

proc ::grammar::me::cpu::core::disasm {code} {
    variable iname
    variable tclass

    Validate $code ord dst jmp

    set label 0
    foreach k [array names jmp] {
	set jmp($k) bra$label
	incr label
    }
    foreach k [array names dst] {
	if {![info exists jmp($k)]} {
	    set jmp($k) {}
	}
    }

    set result {}

    foreach {asm pool tokmap} $code break

    set pc    0
    set pcend [llength $asm]

    while {$pc < $pcend} {
	set base $pc
	set insn [lindex $asm $pc] ; incr pc
	set an   [lindex $anum $insn]

	if {$an == 1} {
	    set a [lindex $asm $pc] ; incr pc
	} elseif {$an == 2} {
	    set a [lindex $asm $pc] ; incr pc
	    set b [lindex $asm $pc] ; incr pc
	} elseif {$an == 3} {
	    set a [lindex $asm $pc] ; incr pc
	    set b [lindex $asm $pc] ; incr pc
	    set c [lindex $asm $pc] ; incr pc
	}

	set     instruction {}
	lappend instruction $jmp($base)
	lappend instruction $iname($insn)

	switch -exact $insn {
	    0 - 5 - 20 - 24 - 25 - 26 -
	    a/string {
		lappend instruction [lindex $pool $a]
	    }
	    1 {
		# a/tok b/string
		if {![llength $tokmap]} {
		    lappend instruction [lindex $pool $a]
		} else {
		    lappend instruction ${a}:$ord($a)
		}
		lappend instruction [lindex $pool $b]
	    }
	    2 {
		# a/tokstart b/tokend c/string
		if {![llength $tokmap]} {
		    lappend instruction [lindex $pool $a]
		    lappend instruction [lindex $pool $b]
		} else {
		    # tokmap defined: a = b = order rank.
		    lappend instruction ${a}:$ord($a)
		    lappend instruction ${b}:$ord($b)
		}
		lappend instruction [lindex $pool $c]
	    }
	    3 {
		# a/class(0-5) b/string
		lappend instruction [lindex $tclass $a]
		lappend instruction [lindex $pool $b]
	    }
	    4 {
		# a/branch b/string
		lappend instruction $jmp($a)
		lappend instruction [lindex $pool $b]
	    }
	    6 - 11 - 12 - 13 -
	    a/branch {
		lappend instruction $jmp($a)
	    }
	    default {}
	}

	lappend result $instruction
    }

    return $result
}

proc ::grammar::me::cpu::core::asm {code} {
    variable iname
    variable anum
    variable tccode

    # code = list(insn), insn = list (label insn-name ...)

    # I. Indices for the labels, based on instruction sizes.

    array set jmp {}
    set off 0
    foreach insn $code {
	foreach {label name} $insn break
	set an [lindex $anum $iname($name)]
	if {[llength $insn] != ($an+2)} {
	    return -code error "Bad instruction \"$insn\", expected $an arguments"    
	}
	if {$label ne ""} {
	    set jmp($label) $off
	}
	incr off
	incr off [lindex $anum $iname($name)]
    }

    set asm          {}
    set pool         {}
    array set poolh  {}
    array set tokmap {}
    array set ord    {}
    set plain        0

    foreach insn $code {
	foreach {label name} $insn break
	set an [lindex $anum $iname($name)]

	# Instruction code to assembly ...
	lappend asm $iname($name)

	# Encode arguments ...
	switch -exact- $name {
	    ict_advance            -
	    inc_save               -
	    ier_nonterminal        -
	    isv_nonterminal_leaf   -
	    isv_nonterminal_range  -
	    isv_nonterminal_reduce {
		lappend asm [Str [lindex $insn 2]]
	    }
	    ict_match_token {
		lappend asm [Tok [lindex $insn 2]]
		lappend asm [Str [lindex $insn 3]]
	    }
	    ict_match_tokrange {
		lappend asm [Tok [lindex $insn 2]]
		lappend asm [Tok [lindex $insn 3]]
		lappend asm [Str [lindex $insn 4]]
	    }
	    ict_match_tokclass {
		lappend asm $tccode([lindex $insn 2])
		lappend asm [Str [lindex $insn 3]]

	    }
	    inc_restore {
		lappend asm $jmp([lindex $insn 2])
		lappend asm [Str [lindex $insn 3]]
	    }
	    icf_ntcall  -
	    icf_jalways -
	    icf_jok     -
	    icf_jfail   {
		lappend asm $jmp([lindex $insn 2])
	    }
	}
    }

    return [list $asm $pool [array get tokmap]]
}

proc ::grammar::me::cpu::core::new {code} {
    # The code generating the state is drawn out to integrate a
    # specification of how the machine state is mapped to Tcl as well.

    Validate $code

    set     state {}   ; # The state is representend as a Tcl list.
    # ### ### ### ######### ######### #########
    lappend state $code ; # [_0] code  - list  - code to run (-)
    lappend state 0     ; # [_1] pc    - int   - Program counter
    lappend state 0     ; # [_2] halt  - bool  - Flag, set (internal) when machine was halted (icf_halt).
    lappend state 0     ; # [_3] eof   - bool  - Flag, set (external) when where will be no more input.
    lappend state {}    ; # [_4] tc    - list  - Terminal cache, pending and processed tokens.
    lappend state 0     ; # [_5] cl    - int   - Current Location
    lappend state {}    ; # [_6] ct    - token - Current Character
    lappend state 0     ; # [_7] ok    - bool  - Match Status
    lappend state {}    ; # [_8] sv    - any   - Semantic Value
    lappend state {}    ; # [_9] er    - list  - Error status (*)
    lappend state {}    ; # [10] ls    - list  - Location Stack (x)
    lappend state {}    ; # [11] as    - list  - Ast Stack
    lappend state {}    ; # [12] ms    - list  - Ast Marker Stack
    lappend state {}    ; # [13] es    - list  - Error Stack
    lappend state {}    ; # [14] rs    - list  - Return Stack
    lappend state {}    ; # [15] nc    - dict  - Nonterminal Cache (backtracking)
    # ### ### ### ######### ######### #########

    # (-) See manpage of this package for the representation.

    # (*) 2 elements, first is error location, second is list of 
    # ... strings, the error messages. The strings are actually
    # ... represented by references into the pool element of the code.

    # (x) Regarding the various stacks maintained in the state, their
    #     top element is always at the right end, i.e. the last
    #     element in the list representing it.

    return $state
}

proc ::grammar::mengine::cpu::lc {state loc} {
    return [lrange [lindex $state 4 $loc] 2 3]
}

proc ::grammar::mengine::cpu::tok {state from {to {}}} {
    if {$to == {}} {set to $from}
    return [lrange [lindex $state 4] $from $to]
}

proc ::grammar::mengine::cpu::sv {state} {
    return [lindex $state 8]
}

proc ::grammar::mengine::cpu::ok {state} {
    return [lindex $state 7]
}

proc ::grammar::mengine::cpu::error {state} {
    set er [lindex $state 9]
    if {[llength $er]} {
	foreach {l m} $er break

	set pool [lindex $state 0 1]
	set mx   {}
	foreach id $m {
	    lappend mx [lindex $pool $id]
	}
	set er [list $l mx]
    }
    return $er
}

proc ::grammar::mengine::cpu::ast {state} {
    return [lindex $state 11 end]
}

proc ::grammar::mengine::cpu::halted {state} {
    return [lindex $state 2]
}

proc ::grammar::mengine::cpu::code {state} {
    return [lindex $state 0]
}

proc ::grammar::mengine::cpu::eof {statevar} {
    upvar 1 $statevar state
    lset state 3 1
    return
}

proc ::grammar::mengine::cpu::put {statevar tok lex line col} {
    upvar 1 $statevar state
    if {[lindex $state 3]} {
	return -code error "Cannot add input data after eof"
    }
    set     tc [K [lindex $state 4] [lset state 4 {}]]
    lappend tc [list $tok $lex $line $col]
    lset state 4 $tc
    return
}

proc ::grammar::mengine::cpu::run {statevar {n -1}} {
    # Execution loop. Should be instrumented for statistics about
    # dynamic instruction frequency. I.e. which instructions are
    # executed the most => put them at the front of the if/switch for
    # quicker selection. I.e. frequency coding of the branches for
    # speed.

    # A C implementation can shimmer the state into a directly
    # accessible data structure. And the asm instructions can shimmer
    # into an integer index upon which we can switch fast.

    variable anum
    variable tclass
    upvar 1 $statevar state

    # Do nothing for a stopped machine (halt flag set).
    if {[lindex $state 2]} {return $state}

    # Unpack state into locally accessible variables
    #        0    1  2    3   4  5  6  7  8  9  10 11 12 13 14 15 16 17 18  19  20
    foreach {code pc halt eof tc cl ct ok sv er ls as ms es rs nc} $state break

    # Unpack match program for easy access as well.
    #        0   1    2
    foreach {asm pool tokmap} $code break

    # Ensure that the unpacked information is not shared
    unset state

    # Internal flags for optimal handling of the nonterminal
    # cache. Avoid multiple unpacking of the dictionary, and avoid
    # repacking if it was not modified.

    set ncunpacked 0
    set ncmodified 0
    set tmunpacked 0

    while {1} {
	# Stop execution if the specified number of instructions have
	# been executed. Ignore if infinity was specified.
	if {$n == 0} break
	if {$n > 0} {incr n -1}

	# Get current instruction ...

	set insn [lindex $asm $pc] ; incr pc

	# And its arguments ...

	set an [lindex $anum $insn]
	if {$an == 1} {
	    set a [lindex $asm $pc] ; incr pc
	} elseif {$an == 2} {
	    set a [lindex $asm $pc] ; incr pc
	    set b [lindex $asm $pc] ; incr pc
	} elseif {$an == 3} {
	    set a [lindex $asm $pc] ; incr pc
	    set b [lindex $asm $pc] ; incr pc
	    set c [lindex $asm $pc] ; incr pc
	}

	# Dispatch to implementation of the instruction ...

	# Separate if commands are used for easier ordering of the
	# dispatch. The order of the branches should be frequency
	# coded to have the most-used instructions first.

	# ict_advance <a:message>
	if {$insn == 0} {
	    incr cl
	    if {$cl < [llength $tc]} {
		set ct [lindex $tc $cl 0]
		set ok 1
		set er {}
	    } elseif {$eof} {
		# We have no input, and there won't be more coming in
		# either. Fail the advance. We do _not_ stop the match
		# loop, the program has to complete. The failure might
		# be no such, revealed during backtracking.

		set er  [list $cl [list $a]]
		set ok  0
	    } else {
		# We have no input, stop matching and wait for
		# more. We reset the machine into a state
		# which will restart this instruction when
		# execution resumes.

		incr cl -1
		incr pc -1
		break
	    }
	    continue
	}

	# ict_match_token <a:token> <b:message>
	if {$insn == 1} {
	    set xch [lindex $pool $a]
	    set ok  [expr {$xch eq $ct}]
	    if {!$ok} {
		set er [list $cl [list $b]]
	    } else {
		set er {}
	    }
	    continue
	}

	# ict_match_tokrange <a:tokstart> <b:tokend> <c:message>
	if {$insn == 2} {
	    if {[llength $tokmap]} {
		if {!$tmunpacked} {
		    array set tm $tokmap
		    set tmunpacked 1
		}
		set x $tm($ct)
		set ok [expr {($a <= $x) && ($x <= $b)}]
	    } else {
		set a [lindex $pool $a]
		set b [lindex $pool $b]
		set ok [expr {
		    ([string compare $a $ct] <= 0) &&
		    ([string compare $ct $b] <= 0)
		}] ; # {}
	    }
	    if {!$ok} {
		set er [list $cl [list $c]]
	    } else {
		set er {}
	    }
	    continue
	}

	# ict_match_tokclass <a:code> <b:message>
	if {$insn == 3} {
	    set code [lindex $tclass $a]
	    set ok   [string is $code -strict $ct]
	    if {!$ok} {
		set er [list $cl [list $b]]
	    } else {
		set er {}
	    }
	    continue
	}

	# inc_restore <a:branchtarget> <b:nonterminal>
	if {$insn == 4} {
	    set sym [lindex $pool $b]

	    # Unpack the cache dict, only here.
	    # 8.5 - Use dict operations instead.

	    if {!$ncunpacked} {
		array set ncc $nc
		set ncunpacked 1
	    }

	    if {[info exists ncc($cl,$sym)]} {
		foreach {go ok error sv} $ncc($cl,$sym) break

		# Go forward, as the nonterminal matches (or not).
		set cl $go
		set pc $a
	    }
	    continue
	}

	# inc_save <a:nonterminal>
	if {$insn == 5} {
	    set sym [lindex $pool $a]
	    set at  [lindex $ls end]
	    set ls  [lrange $ls 0 end-1]

	    # Unpack, modify, only here.
	    # 8.5 - Use dict operations instead.

	    if {!$ncunpacked} {
		array set ncc $nc
		set ncunpacked 1
	    }

	    set ncc($at,$sym) [list $cl $ok $er $sv]
	    set ncmodified 1
	    continue
	}

	# icf_ntcall <a:branchtarget>
	if {$insn == 6} {
	    lappend rs $pc
	    set     pc $a
	    continue
	}

	# icf_ntreturn
	if {$insn == 7} {
	    set pc [lindex $rs end]
	    set rs [lrange $rs 0 end-1]
	    continue
	}

	# iok_ok
	if {$insn == 8} {
	    set ok 1
	    continue
	}

	# iok_fail
	if {$insn == 9} {
	    set ok 0
	    continue
	}

	# iok_negate
	if {$insn == 10} {
	    set ok [expr {!$ok}]
	    continue
	}

	# icf_jalways <a:branchtarget>
	if {$insn == 11} {
	    set pc $a
	    continue
	}

	# icf_jok <a:branchtarget>
	if {$insn == 12} {
	    if {$ok} {set pc $a}
	    # !ok => pc is already on next instruction.
	    continue
	}

	# icf_jfail <a:branchtarget>
	if {$insn == 13} {
	    if {!$ok} {set pc $a}
	    # ok => pc is already on next instruction.
	    continue
	}

	# icf_halt
	if {$insn == 14} {
	    set halt 1
	    break
	}

	# icl_push
	if {$insn == 15} {
	    lappend ls $cl
	    continue
	}

	# icl_rewind
	if {$insn == 16} {
	    set cl [lindex $ls end]
	    set ls [lrange $ls 0 end-1]
	    continue
	}

	# icl_pop
	if {$insn == 17} {
	    set ls [lrange $ls 0 end-1]
	    continue
	}

	# ier_push
	if {$insn == 18} {
	    lappend es $er
	    continue
	}

	# ier_clear
	if {$insn == 19} {
	    set er {}
	    continue
	}

	# ier_nonterminal <a:nonterminal>
	if {$insn == 20} {
	    if {[llength $er]} {
		set  pos [lindex $ls end]
		incr pos
		set eloc [lindex $er 0]
		if {$eloc == pos} {
		    set er [list $eloc [list $a]]
		}
	    }
	}

	# ier_merge
	if {$insn == 21} {
	    set old [lindex $es end]
	    set es  [lrange $es 0 end-1]

	    # We have either old or current error data, keep
	    # it.

	    if {![llength $er]} {
		# No current data, keep old
		set er $old
	    } elseif {[llength $old]} {
		# If one of the errors is further on in the
		# input choose that as the information to
		# propagate.

		foreach {loe msgse} $er  break
		foreach {lon msgsn} $old break

		if {$lon > $loe} {
		    set er $old
		} elseif {$loe == $lon} {
		    # Equal locations, merge the message
		    # lists.

		    foreach m $msgsn {lappend msgse $m}
		    set er [list $loe [lsort -uniq $msgse]]
		}
		# else lon < loe - er is better - nothing
	    }
	    # else - !old, but er - nothing

	    continue
	}

	# isv_clear
	if {$insn == 22} {
	    set sv {}
	    continue
	}

	# isv_terminal
	if {$insn == 23} {
	    set sv [list {} $cl $cl]
	    lappend as $sv
	    continue
	}

	# isv_nonterminal_leaf <a:nonterminal>
	if {$insn == 24} {
	    set pos [lindex $ls end]
	    set sv  [list $a $pos $cl]
	    continue
	}

	# isv_nonterminal_range <a:nonterminal>
	if {$insn == 25} {
	    set pos [lindex $ls end]
	    set sv  [list $a $pos $cl [list {} $pos $cl]]
	    continue
	}

	# isv_nonterminal_reduce <a:nonterminal>
	if {$insn == 26} {
	    set pos [lindex $ls end]
	    if {[llength $ms]} {
		set  mrk [lindex $ms end]
		incr mrk
	    } else {
		set mrk 0
	    }
	    set sv [lrange $as $mrk end]
	    set sv [linsert $sv 0 $a $pos $cl]
	    continue
	}

	# ias_push
	if {$insn == 27} {
	    lappend as $sv
	    continue
	}

	# ias_mark
	if {$insn == 28} {
	    set  mark [llength $as]
	    incr mark -1
	    lappend ms $mark
	    continue
	}

	# ias_mrewind
	if {$insn == 29} {
	    set mark [lindex $ms end]
	    set ms   [lrange $ms 0 end-1]
	    set as   [lrange $as 0 $mark]
	    continue
	}

	# ias_mpop
	if {$insn == 30} {
	    set ms [lrange $ms 0 end-1]
	    continue
	}

	return -code error "Illegal instruction $insn"
    }

    # Repack a modified cache dictionary, then repack and store the
    # updated state value.

    if {$ncmodified} {set nc [array get ncc]}
    set state [list $code $pc $halt $eof $tc $cl $ct $ok $sv $er $ls $as $ms $es $rs $nc]
    return
}

namespace eval grammar::me::cpu::core {
    # Map between class codes and names
    variable tclass {}
    variable tccode

    foreach {x code} {
	0 alnum
	1 alpha
	2 digit
	3 xdigit
	4 punct
	5 space
    } {
	lappend tclass $code
	set tccode($code) $x
    }

    # Number of arguments per ME instruction.
    # Indexed by instruction code.
    variable anum {}

    # Mapping between instruction codes and names.
    variable iname

    foreach {z insn x} {
	0  ict_advance            1
	1  ict_match_token        2
	2  ict_match_tokrange     3
	3  ict_match_tokclass     2
	4  inc_restore            2
	5  inc_save               1
	6  icf_ntcall             1
	7  icf_ntreturn           0
	8  iok_ok                 0
	9  iok_fail               0
	10 iok_negate             0
	11 icf_jalways            1
	12 icf_jok                1
	13 icf_jfail              1
	14 icf_halt               0
	15 icl_push               0
	16 icl_rewind             0
	17 icl_pop                0
	18 ier_push               0
	19 ier_clear              0
	20 ier_nonterminal        1
	21 ier_merge              0
	22 isv_clear              0
	23 isv_terminal           0
	24 isv_nonterminal_leaf   1
	25 isv_nonterminal_range  1
	26 isv_nonterminal_reduce 1
	27 ias_push               0
	28 ias_mark               0
	29 ias_mrewind            0
	30 ias_mpop               0
    } {
	lappend anum $x
	set iname($z) $insn
	set iname($insn) $z
    }
}

# ### ### ### ######### ######### #########
## Helper commands.

proc ::grammar::mengine::cpu::K {x y} {set x}

proc ::grammar::me::cpu::core::Str {str} {
    upvar 1 pool pool poolh poolh
    if {![info exists poolh($str)]} {
	set poolh($str) [llength $pool]
	lappend pool $str
    }
    return $poolh($str)
}

proc ::grammar::me::cpu::core::Tok {str} {
    upvar 1 tokmap tokmap ord ord plain plain

    if {[regexp {^([^:]+):(.+)$} $str -> id name]} {
	if {$plain} {
	    return -code error "Bad assembly, mixing plain and ranked tokens"
	}
	if {[info exists ord($id)]} {
	    return -code error "Bad assembly, non-total ordering for $name and $ord($id), at rank $id"
	}
	set ord($id) $name
	set tokmap($name) $id

	return $id
    } else {
	if {[array size ord]} {
	    return -code error "Bad assembly, mixing plain and ranked tokens"
	}
	set plain 1
	return [uplevel 1 [list String $str]]
    }
}

proc ::grammar::mengine::cpu::Validate {code {ovar {}} {tvar {}} {jvar {}}} {
    variable anum

    # Basic validation of structure ...

    if {![llength $code] == 3} {
	return -code error "Bad length"
    }

    foreach {asm pool tokmap} $code break

    if {[llength $tokmap] % 2 == 1} {
	return -code error "Bad tokmap, expected a dictionary"
    }

    array set ord {}
    if {[llength $tokmap] > 0} {
	foreach {tok rank} {
	    if {[info exists ord($rank)]} {
		return -code error "Bad tokmap, non-total ordering for $tok and $ord($rank), at rank $rank"
	    }
	    set ord($rank) $tok
	}
    }

    # Basic validation of ME code: Valid instructions, collect valid
    # branch target indices

    array set target {}

    set pc 0
    set pcend   [llength $asm]
    set poolend [llength $pool]

    while {$pc < $pcend} {
	set target($pc) .

	set insn [lindex $asm $pc]
	if {($insn < 0) || ($insn > 30)} {
	    return -code error "Invalid instruction $insn at PC $pc"
	}

	incr pc
	incr pc [lindex $anum $insn]
    }

    if {$pc > $pcend} {
	return -code error "Bad program, last instruction is truncated"
    }

    # Validation of ME instruction arguments (pool references, branch
    # targets, ...)

    if {$jvar ne ""} {
	upvar 1 $jvar jmp
    }
    array set jmp {}

    while {$pc < $pcend} {
	set base $pc
	set insn [lindex $asm $pc] ; incr pc
	set an   [lindex $anum $insn]

	if {$an == 1} {
	    set a [lindex $asm $pc] ; incr pc
	} elseif {$an == 2} {
	    set a [lindex $asm $pc] ; incr pc
	    set b [lindex $asm $pc] ; incr pc
	} elseif {$an == 3} {
	    set a [lindex $asm $pc] ; incr pc
	    set b [lindex $asm $pc] ; incr pc
	    set c [lindex $asm $pc] ; incr pc
	}

	switch -exact $insn {
	    0 - 5 - 20 - 24 - 25 - 26 -
	    a/string {
		if {($a < 0) || ($a >= $poolend)} {
		    return -code "Invalid string reference $a for instruction $insn at $base"
		}
	    }
	    1 {
		# a/tok b/string
		if {![llength $tokmap]} {
		    if {($a < 0) || ($a >= $poolend)} {
			return -code "Invalid string reference $a for instruction $insn at $base"
		    }
		} else {
		    if {![info exists ord($a)]} {
			return -code error "Invalid token rank $a for instruction $insn at $base"
		    }
		}
		if {($b < 0) || ($b >= $poolend)} {
		    return -code "Invalid string reference $b for instruction $insn at $base"
		}
	    }
	    2 {
		# a/tokstart b/tokend c/string

		if {![llength $tokmap]} {
		    # a = b = string references.
		    if {($a < 0) || ($a >= $poolend)} {
			return -code "Invalid string reference $a for instruction $insn at $base"
		    }
		    if {($b < 0) || ($b >= $poolend)} {
			return -code "Invalid string reference $b for instruction $insn at $base"
		    }
		} else {
		    # tokmap defined: a = b = order rank.
		    if {![info exists ord($a)]} {
			return -code error "Invalid token rank $a for instruction $insn at $base"
		    }
		    if {![info exists ord($b)]} {
			return -code error "Invalid token rank $b for instruction $insn at $base"
		    }
		    if {$a == $b} {
			return -code error "Invalid single-token range for instruction $insn at $base"
		    }
		    if {$a > $b} {
			return -code error "Invalid empty range for instruction $insn at $base"
		    }
		}
		if {($c < 0) || ($c >= $poolend)} {
		    return -code "Invalid string reference $c for instruction $insn at $base"
		}
	    }
	    3 {
		# a/class(0-5) b/string
		if {($a < 0) || ($a > 5)} {
		    return -code "Invalid token-class $a for instruction $insn at $base"
		}
		if {($b < 0) || ($b >= $poolend)} {
		    return -code "Invalid string reference $b for instruction $insn at $base"
		}
	    }
	    4 {
		# a/branch b/string
		if {![info exists target($a)]} {
		    return -code "Invalid branch target $a for instruction $insn at $base"
		} else {
		    set jmp($a) .
		}
		if {($b < 0) || ($b >= $poolend)} {
		    return -code "Invalid string reference $b for instruction $insn at $base"
		}
	    }
	    6 - 11 - 12 - 13 -
	    a/branch {
		if {![info exists target($a)]} {
		    return -code "Invalid branch target $a for instruction $insn at $base"
		} else {
		    set jmp($a) .
		}
	    }
	    default {}
	}
    }

    # All checks passed, code is deemed good enough.
    # Caller may have asked for some of the collected
    # information.

    if {$ovar ne ""} {
	upvar 1 $ovar o
	array set o $ord
    }
    if {$tvar ne ""} {
	upvar 1 $tvar t
	array set t $target
    }
    return
}

# ### ### ### ######### ######### #########
## Ready

package provide grammar::me::cpu::core 0.1
