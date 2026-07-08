package require tcltest
namespace import tcltest::*
tcl::tm::path add [file normalize [file join [file dirname [info script]] .. lib tm]]
package require tclpdfreader

test open-bad {open non-existent file} -body {
    tclpdfreader::open /no/such/file.pdf
} -returnCodes error -match glob -result {*no such file*}

test badhandle {invalid handle} -body {
    tclpdfreader::version nope
} -returnCodes error -match glob -result {*invalid handle*}

test detect {backend detection runs} -body {
    expr {[info exists ::tclpdfreader::have(tupdf)]
       && [info exists ::tclpdfreader::have(qpdf)]}
} -result 1

cleanupTests
