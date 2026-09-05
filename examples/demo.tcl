#!/usr/bin/env tclsh
# demo: report what tclpdfreader can tell about a PDF, given whichever backends
# happen to be installed. Every backend-dependent call is guarded, so the demo
# degrades gracefully instead of erroring.
package require tclpdfreader
if {[llength $argv] < 1} { puts "usage: demo.tcl file.pdf"; exit 1 }

proc show {label script} {
    if {[catch {uplevel 1 $script} r]} {
        puts [format "%-12s: n/a  (%s)" $label $r]
    } else {
        puts [format "%-12s: %s" $label $r]
    }
}

set h [tclpdfreader::open [lindex $argv 0]]
show backends     {tclpdfreader::backends $h}
show version      {tclpdfreader::version $h}
show pagecount    {format "%s (exact=%s)" [tclpdfreader::pagecount $h] [tclpdfreader::pagecountExact $h]}
show metadata     {tclpdfreader::metadata $h}
show encryption   {tclpdfreader::encryption $h}
show pagesize1    {tclpdfreader::pagesize $h 1}
show hastext1     {expr {[tclpdfreader::hastext $h 1] ? "ja" : "nein (Scan?)"}}
show zugferd      {tclpdfreader::zugferd $h}
show formfields   {tclpdfreader::formfields $h}
show pagetext-1   {string range [tclpdfreader::pagetext $h 1] 0 60}
puts "capabilities: [tclpdfreader::capabilities $h]"
tclpdfreader::close $h

