#!/usr/bin/env tclsh
# overlaps.tcl -- was liegt auf was?
#
#   tclsh overlaps.tcl datei.pdf ?-seiten SPEC? ?-anteil 0.3? ?-text 0|1?
#
#   -seiten SPEC   nur diese Seiten, "1-3,5" oder eine Liste
#   -anteil A      ab welchem ueberdeckten Anteil gemeldet wird (0.3)
#   -text 0|1      den betroffenen Text mitschreiben (Vorgabe 0)
#
# DIE FRAGE:
#
# Ein Eintrag, der auf einer vorgedruckten Linie sitzt, ist auf dem
# Bildschirm zu erkennen und auf dem Papier nicht. Ein Bild, das ueber
# Text liegt, macht ihn unsichtbar -- extrahieren laesst er sich
# trotzdem, also merkt es weder das Auge noch pdftotext.
#
# Bei cmrform wurde das von Hand gerechnet. Hier steht es einmal.
#
# WAS ES MISST: die RECHTECKE der Seitenobjekte, wie "pageobjects" sie
# liefert. Ueberschneiden sie sich zu mehr als dem angegebenen Anteil,
# wird es gemeldet.
#
# WAS DAS NICHT HEISST: dass sich die Zeichnung wirklich beruehrt. Das
# Rechteck einer Linie und das eines Absatzes koennen sich ueberlappen,
# waehrend die Linie sauber zwischen zwei Zeilen liegt. Ein Rechteck ist
# eine Huelle, keine Form.
#
# Darum meldet dieses Werkzeug KANDIDATEN und keine Fehler. Es sagt, wo
# man hinsehen soll -- nicht, dass dort etwas kaputt ist. Wer daraus
# eine Pruefung macht, die rot wird, bekommt Fehlalarme und liest sie
# bald nicht mehr.

package require Tcl 8.6-

proc brauche {paket zweck} {
    if {[catch {package require $paket} e]} {
        puts stderr "overlaps: braucht das Paket \"$paket\" fuer $zweck"
        puts stderr "  ($e)"
        exit 2
    }
}
brauche pdfiumtcl "die Seitenobjekte"

set opt [dict create -seiten "" -anteil 0.3 -text 0]
set datei ""
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    if {[string match "-*" $a]} {
        if {![dict exists $opt $a]} {
            puts stderr "overlaps: unbekannte Option \"$a\""
            exit 2
        }
        dict set opt $a [lindex $argv [incr i]]
    } else {
        set datei $a
    }
}
if {$datei eq "" || ![file readable $datei]} {
    puts stderr "Aufruf: tclsh overlaps.tcl datei.pdf ?-seiten SPEC?\
            ?-anteil 0.3? ?-text 0|1?"
    exit 2
}
set schwelle [dict get $opt -anteil]
if {![string is double -strict $schwelle] || $schwelle <= 0 || $schwelle > 1} {
    puts stderr "overlaps: -anteil muss zwischen 0 und 1 liegen"
    exit 2
}

# Flaeche der Ueberschneidung zweier Rechtecke {l u r o}.
proc schnittFlaeche {a b} {
    lassign $a al au ar ao
    lassign $b bl bu br bo
    set l [expr {max($al, $bl)}]
    set r [expr {min($ar, $br)}]
    set u [expr {max($au, $bu)}]
    set o [expr {min($ao, $bo)}]
    if {$r <= $l || $o <= $u} { return 0.0 }
    return [expr {($r - $l) * ($o - $u)}]
}

# Liegt a ganz in b?
proc enthalten {a b} {
    lassign $a al au ar ao
    lassign $b bl bu br bo
    return [expr {$al >= $bl - 0.01 && $ar <= $br + 0.01
               && $au >= $bu - 0.01 && $ao <= $bo + 0.01}]
}

proc flaeche {r} {
    lassign $r l u re o
    if {$re <= $l || $o <= $u} { return 0.0 }
    return [expr {($re - $l) * ($o - $u)}]
}

set doc [::pdfium::open $datei]
set n [::pdfium::pagecount $doc]

set seiten {}
set spec [dict get $opt -seiten]
if {$spec eq ""} {
    for {set p 1} {$p <= $n} {incr p} { lappend seiten $p }
} else {
    set alleZahlen 1
    foreach e $spec { if {![string is integer -strict $e]} { set alleZahlen 0 } }
    if {$alleZahlen && [llength $spec]} {
        set seiten $spec
    } else {
        brauche tclutils::tupagespec "die Seitenangabe \"$spec\""
        if {[catch {::tclutils::tupagespec::parse $spec $n} seiten]} {
            puts stderr "overlaps: Seitenangabe \"$spec\": $seiten"
            ::pdfium::close $doc
            exit 2
        }
    }
}

puts "overlaps: [file tail $datei], $n Seite(n), Schwelle [format %.0f%% \
        [expr {$schwelle * 100}]]"
puts ""

set befunde 0
foreach p $seiten {
    if {$p < 1 || $p > $n} {
        puts "Seite $p: ausserhalb 1..$n"
        continue
    }
    set idx [expr {$p - 1}]
    set objekte [::pdfium::pageobjects $doc $idx]

    # HINTERGRUENDE aussortieren.
    #
    # Ein Rahmen oder eine Flaechenfuellung ueber die ganze Seite ist ein
    # Pfad, der mit JEDEM Textstueck ueberlappt -- zu 100 % der kleineren
    # Flaeche, also immer ueber jeder Schwelle. Gemessen an einer
    # schlichten Datei: zehn Kandidaten von zwoelf Objekten, und alle
    # gingen auf einen Rahmen zurueck, der 90 % der Seite einnimmt.
    #
    # So etwas liegt unter dem Text und stoert ihn nicht. Es zu melden
    # heisst, den Prueferbericht mit Rauschen zu fuellen -- und dann liest
    # ihn niemand mehr.
    lassign [::pdfium::pagesize $doc $idx] wmm hmm
    set seitenFlaeche [expr {($wmm * 72.0 / 25.4) * ($hmm * 72.0 / 25.4)}]
    set hintergruende {}
    if {$seitenFlaeche > 0} {
        set gefiltert {}
        foreach e $objekte {
            lassign $e onum otyp obox
            if {$otyp eq "path" && [flaeche $obox] > 0.6 * $seitenFlaeche} {
                lappend hintergruende $onum
                continue
            }
            lappend gefiltert $e
        }
        set objekte $gefiltert
    }

    # Texte kommen mit ihrem Inhalt aus "mctext" -- aber NUR wenn das
    # Dokument ausgezeichnet ist. Ohne das bleibt die Meldung bei der
    # Objektnummer, und das ist ehrlicher als ein geratener Text.
    set texte [dict create]
    if {[dict get $opt -text]} {
        catch {
            set i 0
            foreach {mcid txt} [::pdfium::mctext $doc $idx] {
                dict set texte $i $txt
                incr i
            }
        }
    }

    set treffer {}
    set anz [llength $objekte]
    for {set i 0} {$i < $anz} {incr i} {
        lassign [lindex $objekte $i] ia ityp ibox
        if {[flaeche $ibox] <= 0} continue
        for {set j [expr {$i + 1}]} {$j < $anz} {incr j} {
            lassign [lindex $objekte $j] ja jtyp jbox
            if {[flaeche $jbox] <= 0} continue

            # Nur Paare, bei denen eine Ueberdeckung etwas BEDEUTET.
            # Zwei Textstuecke nebeneinander ueberlappen staendig -- das
            # ist Satz und kein Befund. Gemeldet werden Text gegen Bild,
            # Text gegen Pfad und Bild gegen Text.
            set art ""
            if {$ityp eq "text" && $jtyp eq "image"} { set art "Text/Bild" }
            if {$ityp eq "image" && $jtyp eq "text"} { set art "Text/Bild" }
            if {$ityp eq "text" && $jtyp eq "path"}  { set art "Text/Linie" }
            if {$ityp eq "path" && $jtyp eq "text"}  { set art "Text/Linie" }
            if {$art eq ""} continue

            set s [schnittFlaeche $ibox $jbox]
            if {$s <= 0} continue
            # Am KLEINEREN Rechteck messen: eine Linie ueber die ganze
            # Blattbreite deckt von einem Wort viel ab und vom eigenen
            # Rechteck fast nichts. Am groesseren gemessen faenden wir
            # nie etwas.
            set kleiner [expr {min([flaeche $ibox], [flaeche $jbox])}]
            if {$kleiner <= 0} continue
            set anteil [expr {$s / $kleiner}]
            if {$anteil < $schwelle} continue

            # EIN RAHMEN IST KEINE LINIE DURCH DEN TEXT.
            #
            # Liegt der Text GANZ im Pfad, ist der Pfad ein Kasten um ihn
            # herum -- eine Umrandung, eine farbige Flaeche hinter einer
            # Ueberschrift. Das ist Layout und kein Zusammenstoss.
            # Gemessen an einer schlichten Datei: zwei Kandidaten, beide
            # ein Rahmen um seinen eigenen Text.
            #
            # Interessant ist das KREUZEN: eine Linie, die durch den Text
            # laeuft, deckt ihn teilweise und enthaelt ihn nicht.
            #
            # Beim BILD ist es umgekehrt: dort heisst "ganz darin", dass
            # der Text verdeckt ist -- und genau das soll gemeldet
            # werden.
            if {$art eq "Text/Linie"} {
                set textBox [expr {$ityp eq "text" ? "$ibox" : "$jbox"}]
                set pfadBox [expr {$ityp eq "path" ? "$ibox" : "$jbox"}]
                if {[enthalten $textBox $pfadBox]} continue
            }

            lappend treffer [list $art $ia $ityp $ja $jtyp $anteil]
        }
    }

    set hg ""
    if {[llength $hintergruende]} {
        set hg " -- [llength $hintergruende] Hintergrundflaeche(n)\
                ausgelassen"
    }
    if {![llength $treffer]} {
        puts "Seite $p: nichts zu melden ($anz Objekte)$hg"
        puts ""
        continue
    }
    incr befunde
    puts "Seite $p: [llength $treffer] Kandidat(en) von $anz Objekten$hg"
    foreach t [lsort -index 5 -real -decreasing $treffer] {
        lassign $t art ia ityp ja jtyp anteil
        puts [format "  %-11s #%-3d %-6s ueber/unter #%-3d %-6s  %3.0f%%" \
                $art $ia $ityp $ja $jtyp [expr {$anteil * 100}]]
        if {[dict get $opt -text]} {
            foreach num [list $ia $ja] {
                if {[dict exists $texte $num]} {
                    set t2 [string map [list \n " "] [dict get $texte $num]]
                    if {[string trim $t2] ne ""} {
                        puts "                #$num: [string range $t2 0 50]"
                    }
                }
            }
        }
    }
    puts ""
}

::pdfium::close $doc
puts "----------------------------------------------------------"
if {$befunde} {
    puts "[llength $seiten] Seite(n) geprueft, $befunde mit Kandidaten"
    puts ""
    puts "KANDIDATEN, keine Fehler. Ein Rechteck ist eine Huelle, keine"
    puts "Form: eine Linie kann sauber zwischen zwei Zeilen liegen und"
    puts "sich mit deren Rechtecken trotzdem ueberschneiden. Das Werkzeug"
    puts "sagt, wo man hinsehen soll."
} else {
    puts "[llength $seiten] Seite(n) geprueft, keine Kandidaten"
}
exit [expr {$befunde ? 1 : 0}]
