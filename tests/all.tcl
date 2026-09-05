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

# ---------------------------------------------------------------------------
# 0.2: Seitenmass, Text vorhanden, Verschluesselung
# ---------------------------------------------------------------------------
#
# Eine Vorlage zum Messen, mit pdf4tcl erzeugt: A4 hoch, eine zweite
# Seite quer und gedreht.
testConstraint havePdf4tcl [expr {![catch {package require pdf4tcl}]}]
testConstraint haveQpdf    [expr {[llength [auto_execok qpdf]] > 0}]

proc probeDatei {} {
    set f [file join [temporaryDirectory] reader-probe-[pid].pdf]
    if {[file exists $f]} { return $f }
    set p [::pdf4tcl::new %AUTO% -paper a4 -compress 0]
    $p startPage
    $p setFont 12 Helvetica
    $p text "Seite eins mit Text" -x 50 -y 700
    $p startPage -paper a5 -landscape 1
    $p setFont 12 Helvetica
    $p text "Seite zwei" -x 50 -y 300
    $p write -file $f
    $p destroy
    return $f
}

test pagesize-1.1 {A4 in Punkt und Millimeter} -constraints {havePdf4tcl haveQpdf} -body {
    set h [tclpdfreader::open [probeDatei]]
    set s [tclpdfreader::pagesize $h 1]
    tclpdfreader::close $h
    # 595 x 842 pt, 210 x 297 mm -- beides gemeldet, keines gerechnet
    # verschwiegen. In der DATEI stehen Punkte, pdfium meldet Millimeter.
    list [expr {abs([dict get $s width] - 595) < 1}] \
         [expr {abs([dict get $s height] - 842) < 1}] \
         [expr {abs([dict get $s widthmm] - 210) < 1}] \
         [dict get $s rotate]
} -result {1 1 1 0}

test pagesize-1.2 {zweite Seite hat ein anderes Mass} -constraints {havePdf4tcl haveQpdf} -body {
    # Der Fall, an dem ein Stempel scheitert, der EIN Mass annimmt.
    set h [tclpdfreader::open [probeDatei]]
    set a [tclpdfreader::pagesize $h 1]
    set b [tclpdfreader::pagesize $h 2]
    tclpdfreader::close $h
    # Das PAAR vergleichen, nicht eine Kante: A5 quer ist mit 595 pt
    # genauso breit wie A4 hoch. Ein Test auf die Breite allein war
    # gruen, ohne etwas zu messen.
    expr {[list [dict get $a width] [dict get $a height]] ne
          [list [dict get $b width] [dict get $b height]]}
} -result 1

test pagesize-1.3 {das Rechteck kommt aus der Datei} -constraints {havePdf4tcl haveQpdf} -body {
    set h [tclpdfreader::open [probeDatei]]
    set s [tclpdfreader::pagesize $h 1]
    tclpdfreader::close $h
    # Vier Zahlen, und keine davon traegt einen Zeilenumbruch: "string is
    # double" laesst umgebende Leerzeichen durch, und ein "842\n" landete
    # zuerst als solches im Rechteck.
    set mb [dict get $s mediabox]
    set sauber 1
    foreach z $mb { if {$z ne [string trim $z]} { set sauber 0 } }
    list [llength $mb] $sauber
} -result {4 1}

test pagesize-1.4 {eine Seite ausserhalb wird gemeldet} -constraints {havePdf4tcl haveQpdf} -body {
    set h [tclpdfreader::open [probeDatei]]
    catch {tclpdfreader::pagesize $h 99} e
    tclpdfreader::close $h
    string match "*ausserhalb*" $e
} -result 1

test hastext-1.1 {Text auf der Seite} -constraints {havePdf4tcl} -body {
    if {![info exists ::tclpdfreader::have(pdfium)] || !$::tclpdfreader::have(pdfium)} {
        return 1
    }
    set h [tclpdfreader::open [probeDatei]]
    set r [tclpdfreader::hastext $h 1]
    tclpdfreader::close $h
    set r
} -result 1

test encryption-1.1 {eine offene Datei meldet sich als offen} -constraints {havePdf4tcl haveQpdf} -body {
    set h [tclpdfreader::open [probeDatei]]
    set e [tclpdfreader::encryption $h]
    tclpdfreader::close $h
    list [dict get $e encrypted] [dict get $e printing]
} -result {0 1}

test capabilities-1.1 {die neuen Faehigkeiten stehen im Bericht} -body {
    set h [tclpdfreader::open [probeDatei]]
    set c [tclpdfreader::capabilities $h]
    tclpdfreader::close $h
    list [dict exists $c pagesize] [dict exists $c hastext] \
            [dict exists $c encryption]
} -constraints {havePdf4tcl} -result {1 1 1}

test pagesizes-1.1 {alle Masse auf einmal} -constraints {havePdf4tcl haveQpdf} -body {
    set h [tclpdfreader::open [probeDatei]]
    set alle [tclpdfreader::pagesizes $h]
    set n [tclpdfreader::pagecount $h]
    tclpdfreader::close $h
    list [llength $alle] [expr {[llength $alle] == $n}]
} -result {2 1}

test annotations-1.1 {ein Formularfeld taucht als Anmerkung auf} -constraints {havePdf4tcl} -body {
    # Wer stempelt, sollte wissen, was er ueberklebt.
    if {!$::tclpdfreader::have(pdfium)} { return 1 }
    set f [file join [temporaryDirectory] annot-[pid].pdf]
    set p [::pdf4tcl::new %AUTO%]
    $p startPage
    $p setFont 10 Helvetica
    $p addForm text 50 600 100 20 -id feld
    $p write -file $f
    $p destroy
    set h [tclpdfreader::open $f]
    set a [tclpdfreader::annotations $h 1]
    tclpdfreader::close $h
    file delete $f
    expr {[llength $a] >= 1 && [string match "*widget*" $a]}
} -result 1

test attachments-1.1 {Schluessel eingebetteter Dateien} -constraints {havePdf4tcl haveQpdf} -body {
    # Zum Entfernen braucht man den SCHLUESSEL; den nennt sonst nur
    # "qpdf --list-attachments" auf der Kommandozeile.
    set f  [file join [temporaryDirectory] att1-[pid].pdf]
    set f2 [file join [temporaryDirectory] att2-[pid].pdf]
    set p [::pdf4tcl::new %AUTO%]
    $p startPage ; $p setFont 10 Helvetica ; $p text "x" -x 50 -y 700
    $p write -file $f
    $p destroy
    exec qpdf $f --add-attachment $f --key=beispiel -- $f2
    set h [tclpdfreader::open $f2]
    set a [tclpdfreader::attachments $h]
    tclpdfreader::close $h
    file delete $f $f2
    set a
} -result {beispiel}

test pagelabels-1.1 {ohne /PageLabels eine leere Liste} -constraints {havePdf4tcl haveQpdf} -body {
    # Leer heisst: die Beschriftung IST die Nummer. Kein Fehler.
    set h [tclpdfreader::open [probeDatei]]
    set l [tclpdfreader::pagelabels $h]
    tclpdfreader::close $h
    llength $l
} -result 0

test layers-1.1 {Ebenen mit Namen, Sichtbarkeit und Druckzustand} \
        -constraints {havePdf4tcl haveQpdf} -body {
    # WARUM IM READER: pdfium befolgt Ebenen beim Rendern, kann sie aber
    # nicht aufzaehlen -- es meldet an einem Objekt nur, DASS es in einer
    # liegt. Wer wissen will, WELCHE es gibt, muss in die Datei sehen.
    set f [file join [temporaryDirectory] layers-[pid].pdf]
    set p [::pdf4tcl::new %AUTO% -compress 0]
    $p addLayer "Sichtbar"
    $p addLayer "Versteckt" -visible 0
    $p addLayer "Nur Schirm" -print 0
    $p startPage ; $p endPage
    $p write -file $f
    $p destroy
    set h [tclpdfreader::open $f]
    set l [tclpdfreader::layers $h]
    tclpdfreader::close $h
    file delete $f
    set namen {} ; set sicht {} ; set druck {}
    foreach e $l {
        lappend namen [dict get $e name]
        lappend sicht [dict get $e visible]
        lappend druck [dict get $e print]
    }
    list $namen $sicht $druck
} -result {{Sichtbar Versteckt {Nur Schirm}} {1 0 1} {1 1 0}}

test layers-1.2 {ohne Ebenen eine leere Liste} -constraints {havePdf4tcl haveQpdf} -body {
    # Leer heisst "keine", nicht "unbekannt" -- und ist kein Fehler.
    set h [tclpdfreader::open [probeDatei]]
    set l [tclpdfreader::layers $h]
    tclpdfreader::close $h
    llength $l
} -result 0

test durchreichen-1.1 {charboxes und pageobjects kommen durch} \
        -constraints {havePdf4tcl} -body {
    if {!$::tclpdfreader::have(pdfium)} { return {1 1} }
    set h [tclpdfreader::open [probeDatei]]
    set cb [tclpdfreader::charboxes $h 1]
    set po [tclpdfreader::pageobjects $h 1]
    tclpdfreader::close $h
    list [expr {[llength $cb] > 0}] [expr {[llength $po] > 0}]
} -result {1 1}

file delete -force [file join [temporaryDirectory] reader-probe-[pid].pdf]
cleanupTests
