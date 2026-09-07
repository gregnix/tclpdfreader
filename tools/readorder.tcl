#!/usr/bin/env tclsh
# readorder.tcl -- liest ein Dokument so, wie es ausgezeichnet ist?
#
#   tclsh readorder.tcl datei.pdf ?-seiten SPEC? ?-text 0|1?
#
#   -seiten SPEC   nur diese Seiten, "1-3,5" oder eine Liste
#   -text 0|1      den Text je Marke mitschreiben (Vorgabe 0)
#
# DIE FRAGE:
#
# Ein Vorleseprogramm folgt dem STRUKTURBAUM, ein Drucker dem
# INHALTSSTROM. Beide Reihenfolgen koennen auseinandergehen, ohne dass
# man es dem fertigen Blatt ansieht -- eine zweispaltige Seite, die
# spaltenweise gezeichnet, aber zeilenweise ausgezeichnet ist, liest
# sich vorgelesen wie Kraut und Rueben und sieht gedruckt tadellos aus.
#
# tclpdfium liefert seit laengerem beide Haelften: "structure" gibt die
# Reihenfolge der Auszeichnung, "mctext" die des Zeichnens. Verglichen
# hat sie bisher nichts -- der Kommentar in mctext sagt die Frage sogar,
# aber es gab kein Werkzeug dafuer.
#
# WAS ES MELDET:
#
#   Reihenfolge   stimmen Baum und Strom ueberein?
#   ohne Marke    gezeichneter Text, der in KEINEM Strukturelement
#                 steht -- fuer ein Vorleseprogramm nicht vorhanden
#   ohne Text     ausgezeichnete Elemente, zu denen nichts gezeichnet
#                 wurde -- ein leerer Eintrag im Inhaltsverzeichnis
#
# WAS ES NICHT TUT: entscheiden, ob eine Abweichung schlimm ist. Eine
# Kopfzeile, die zuletzt gezeichnet wird, ist voellig in Ordnung. Es
# zeigt, wo eine ist.

package require Tcl 8.6-

proc brauche {paket zweck} {
    if {[catch {package require $paket} e]} {
        puts stderr "readorder: braucht das Paket \"$paket\" fuer $zweck"
        puts stderr "  ($e)"
        exit 2
    }
}
brauche pdfiumtcl "Strukturbaum und Marked Content"

set opt [dict create -seiten "" -text 0]
set datei ""
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    if {[string match "-*" $a]} {
        if {![dict exists $opt $a]} {
            puts stderr "readorder: unbekannte Option \"$a\""
            exit 2
        }
        dict set opt $a [lindex $argv [incr i]]
    } else {
        set datei $a
    }
}
if {$datei eq "" || ![file readable $datei]} {
    puts stderr "Aufruf: tclsh readorder.tcl datei.pdf ?-seiten SPEC? ?-text 0|1?"
    exit 2
}

# Die MCIDs aus dem Strukturbaum einsammeln, in BAUMREIHENFOLGE.
#
# Ein Element kann mehrere Marken tragen (ein Absatz aus mehreren
# Textstuecken) und Kinder haben. Die Reihenfolge ist die des Baums --
# genau die, der ein Vorleseprogramm folgt.
proc mcidsAusBaum {knoten pfadVar gruppenVar} {
    upvar 1 $pfadVar pfad
    upvar 1 $gruppenVar gruppen
    set aus {}
    foreach k $knoten {
        set typ [dict get $k type]
        set eigene [dict get $k mcids]
        if {[llength $eigene]} {
            # Die Marken EINES Elements zusammen merken.
            #
            # Ein Absatz, der ueber einen Seitenumbruch laeuft, ist EIN
            # Strukturelement mit Marken auf ZWEI Seiten -- in pdf4tcls
            # demo-tagged.pdf steht auf Seite 2 ein P mit "mcids {26 0}",
            # und 26 liegt auf Seite 1. Wer die Marken einzeln
            # betrachtet, meldet 26 als "ausgezeichnet, aber nichts
            # gezeichnet" -- und meckert damit genau den Fall an, den die
            # Demo vorfuehrt.
            lappend gruppen [list $typ $eigene]
        }
        foreach m $eigene {
            lappend aus $m
            dict set pfad $m $typ
        }
        if {[dict exists $k children]} {
            lappend aus {*}[mcidsAusBaum [dict get $k children] pfad gruppen]
        }
    }
    return $aus
}

# Jede Marke nur beim ersten Auftreten behalten, Reihenfolge sonst
# unveraendert.
proc ersteVorkommen {liste} {
    set gesehen [dict create]
    set aus {}
    foreach m $liste {
        if {[dict exists $gesehen $m]} continue
        dict set gesehen $m 1
        lappend aus $m
    }
    return $aus
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
            puts stderr "readorder: Seitenangabe \"$spec\": $seiten"
            ::pdfium::close $doc
            exit 2
        }
    }
}

puts "readorder: [file tail $datei], $n Seite(n)"

# Die Frage "ist das Dokument ausgezeichnet" gehoert ans DOKUMENT, nicht
# an die Seite. Vorher wurde sie indirekt ueber einen leeren
# Strukturbaum beantwortet -- und dann ist "nicht ausgezeichnet" nicht
# zu unterscheiden von "diese eine Seite hat nichts". "catalog" gibt es
# seit pdfiumtcl 0.6.3.
set istGetaggt ""
set sprache ""
if {![catch {::pdfium::catalog $doc} kat]} {
    set istGetaggt [dict get $kat tagged]
    set sprache [dict get $kat language]
    if {$istGetaggt} {
        puts "  ausgezeichnet: ja[expr {$sprache ne ""
                ? ", Sprache $sprache" : ", OHNE /Lang"}]"
        if {$sprache eq ""} {
            puts "    Ohne /Lang weiss ein Vorleseprogramm nicht, in welcher"
            puts "    Sprache es lesen soll -- deutscher Text wird dann"
            puts "    englisch ausgesprochen. PDF/UA verlangt den Eintrag."
        }
    } else {
        puts "  ausgezeichnet: NEIN -- kein Strukturbaum im Katalog."
        puts "    Ein Vorleseprogramm liest, wie gezeichnet wurde."
        # EINMAL zaehlen, nicht je Seite.
        #
        # Der erste Versuch meldete am Ende "ohne Befund" -- dabei steht
        # der Befund drei Zeilen weiter oben. Ein Rueckgabewert 0 haette
        # gesagt "alles in Ordnung", und in einem Makefile waere das
        # durchgelaufen.
        set nichtGetaggt 1
    }
}
puts ""

set befunde 0
if {[info exists nichtGetaggt]} { incr befunde }
foreach p $seiten {
    if {$p < 1 || $p > $n} {
        puts "Seite $p: ausserhalb 1..$n"
        continue
    }
    set idx [expr {$p - 1}]

    set baum [::pdfium::structure $doc $idx]
    set gezeichnet [::pdfium::mctext $doc $idx]

    # mctext gibt eine Wechselliste mcid/text in ZEICHENREIHENFOLGE.
    # MCID -1 heisst "kein Marked Content" -- gezeichnet, aber nicht
    # ausgezeichnet.
    # ARTEFAKTE zaehlen: Kopfzeile, Seitenzahl, Wasserzeichen.
    #
    # Sie tragen KEINE MCID -- das ist ihr Zweck, ein Vorleseprogramm
    # soll sie ueberspringen (ISO 32000-1 14.8.2.2). pdfium meldet fuer
    # sie dieselbe -1 wie fuer unausgezeichneten Text, und ohne den
    # Markennamen sind die beiden nicht zu unterscheiden.
    #
    # Gemessen an pdf4tcls demo-tagged.pdf: der erste Lauf meldete
    # "2 Textstueck(e) ohne Marke" -- dabei benutzt die Demo
    # "tagArtifact" und macht alles richtig. Ein Pruefer, der korrekte
    # Artefakte anmeckert, wird nicht mehr gelesen.
    #
    # "pageobjects -marks 1" gibt es seit pdfiumtcl 0.6.2; mit einer
    # aelteren Fassung bleibt der alte, ungenauere Befund.
    set artefakte 0
    if {[catch {::pdfium::pageobjects $doc $idx -marks 1} objekte]} {
        set objekte {}
    }
    foreach e $objekte {
        if {[lindex $e 1] ne "text"} continue
        if {"Artifact" in [lindex $e 3]} { incr artefakte }
    }

    set stromIds {}
    set stromText [dict create]
    set ohneMarke 0
    foreach {mcid txt} $gezeichnet {
        if {$mcid < 0} {
            if {[string trim $txt] ne ""} { incr ohneMarke }
            continue
        }
        lappend stromIds $mcid
        dict append stromText $mcid $txt
    }

    if {![llength $baum]} {
        if {![llength $stromIds] && !$ohneMarke} {
            puts "Seite $p: leer"
        } elseif {$istGetaggt eq 0} {
            # Beim ungetaggten Dokument steht es schon oben. Es je Seite
            # zu wiederholen macht aus einer Nachricht zwanzig.
            puts "Seite $p: ohne Baum ([llength $gezeichnet] Textstueck(e))"
        } else {
            puts "Seite $p: KEIN Baum, obwohl das Dokument ausgezeichnet ist\
                    ([llength $gezeichnet] Textstueck(e) gezeichnet)"
            puts "    Diese Seite faellt aus der Struktur heraus."
            incr befunde
        }
        puts ""
        continue
    }

    set pfad [dict create]
    set gruppen {}
    set baumIds [mcidsAusBaum $baum pfad gruppen]

    # ERSTES AUFTRETEN je Marke, auf beiden Seiten.
    #
    # Eine Marke darf mehrfach vorkommen: ein Absatz wird oft in
    # mehreren Textstuecken gezeichnet, und ein Strukturelement kann
    # dieselbe Marke an zwei Stellen nennen. Wer die Rohlisten
    # vergleicht, meldet das als Abweichung -- gemessen an pdf4tcls
    # eigener demo-tagged.pdf: Baum "... 24 26 0", Strom "0 1 1 2 ...",
    # und der Befund war eine Doppelung, keine Vertauschung.
    #
    # Was zaehlt, ist die REIHENFOLGE des ersten Auftretens: in welcher
    # Folge begegnen einem Leser die Elemente.
    set baumIds [ersteVorkommen $baumIds]
    set stromIds [ersteVorkommen $stromIds]

    # Vergleich. Nur die Marken, die in BEIDEN vorkommen -- alles andere
    # meldet der Abschnitt darunter, und zwar getrennt, weil es etwas
    # anderes bedeutet.
    set gemeinsamBaum {}
    foreach m $baumIds { if {$m in $stromIds} { lappend gemeinsamBaum $m } }
    set gemeinsamStrom {}
    foreach m $stromIds { if {$m in $baumIds} { lappend gemeinsamStrom $m } }

    set gleich [expr {$gemeinsamBaum eq $gemeinsamStrom}]
    # Nur ein Element, von dem GAR NICHTS auf dieser Seite gezeichnet
    # wurde, ist ein Befund. Hat es hier eine Marke und anderswo eine
    # weitere, laeuft es ueber den Seitenumbruch -- das ist richtig so.
    set nurBaum {}
    set nurBaumEcht {}
    set ueberSeiten 0
    foreach g $gruppen {
        lassign $g typ marken
        set hier 0
        foreach m $marken { if {$m in $stromIds} { incr hier } }
        if {$hier > 0} {
            if {$hier < [llength $marken]} { incr ueberSeiten }
            continue
        }
        foreach m $marken {
            lappend nurBaum $m
            if {$typ ni {Figure Formula Artifact}} { lappend nurBaumEcht $m }
        }
    }
    set nurStrom {}
    foreach m $stromIds { if {$m ni $baumIds} { lappend nurStrom $m } }

    set zeile "Seite $p: [llength $baumIds] Marke(n) im Baum,\
            [llength $stromIds] im Strom"
    set echtOhneMarke [expr {$ohneMarke - $artefakte}]
    if {$echtOhneMarke < 0} { set echtOhneMarke 0 }
    if {$gleich && ![llength $nurBaumEcht] && ![llength $nurStrom]
            && !$echtOhneMarke} {
        set zusatz {}
        if {[llength $nurBaum]} { lappend zusatz "[llength $nurBaum] bildhaft" }
        if {$artefakte} { lappend zusatz "$artefakte Artefakt(e)" }
        if {$ueberSeiten} { lappend zusatz "$ueberSeiten ueber den Umbruch" }
        if {[llength $zusatz]} {
            puts "$zeile -- Reihenfolge stimmt ([join $zusatz {, }])"
            puts ""
            continue
        }
        puts "$zeile -- Reihenfolge stimmt"
        puts ""
        continue
    }
    puts $zeile
    incr befunde

    if {!$gleich} {
        puts "  REIHENFOLGE weicht ab:"
        puts "    Baum:  [join $gemeinsamBaum { }]"
        puts "    Strom: [join $gemeinsamStrom { }]"
        # Die erste Stelle nennen, an der es auseinandergeht -- die
        # ganze Liste zu vergleichen ueberlaesst dem Leser die Arbeit.
        for {set i 0} {$i < [llength $gemeinsamBaum]} {incr i} {
            set a [lindex $gemeinsamBaum $i]
            set b [lindex $gemeinsamStrom $i]
            if {$a ne $b} {
                set typ ""
                if {[dict exists $pfad $a]} { set typ " ([dict get $pfad $a])" }
                puts "    ab Stelle [expr {$i+1}]: Baum $a$typ, Strom $b"
                break
            }
        }
    }
    if {$ohneMarke} {
        set echtOhne [expr {$ohneMarke - $artefakte}]
        if {$echtOhne > 0} {
            puts "  OHNE MARKE: $echtOhne Textstueck(e) gezeichnet, aber in"
            puts "    keinem Strukturelement -- fuer ein Vorleseprogramm"
            puts "    nicht vorhanden."
        }
        if {$artefakte > 0} {
            puts "  Artefakte: $artefakte Textstueck(e) als /Artifact"
            puts "    markiert -- kein Befund, genau dafuer sind sie da."
        }
    }
    if {[llength $nurBaum]} {
        # "mctext" sieht nur TEXT. Ein Figure mit einem Bild darin hat
        # naturgemaess keinen -- das als Befund zu melden waere ein
        # Fehlalarm, und ein Pruefer, der bei jedem Bild anschlaegt,
        # wird nicht mehr gelesen. Gemessen an pdf4tcls demo-tagged.pdf:
        # Marke 25 ist ein Figure.
        set bildhaft {Figure Formula Artifact}
        set echte {}
        set bilder {}
        foreach m $nurBaum {
            set typ [expr {[dict exists $pfad $m] ? [dict get $pfad $m] : ""}]
            set eintrag [expr {$typ ne "" ? "$m ($typ)" : $m}]
            if {$typ in $bildhaft} {
                lappend bilder $eintrag
            } else {
                lappend echte $eintrag
            }
        }
        if {[llength $echte]} {
            puts "  OHNE TEXT: [join $echte {, }] -- ausgezeichnet, aber nichts"
            puts "    gezeichnet."
        }
        if {[llength $bilder]} {
            puts "  ohne Text, aber bildhaft: [join $bilder {, }] --"
            puts "    kein Befund: mctext sieht nur Text."
        }
    }
    if {[llength $nurStrom]} {
        puts "  NICHT IM BAUM: [join $nurStrom {, }] -- markiert, aber in"
        puts "    keinem Strukturelement."
    }
    if {[dict get $opt -text]} {
        foreach m $baumIds {
            if {![dict exists $stromText $m]} continue
            set t [string map [list \n " "] [dict get $stromText $m]]
            puts "    $m [expr {[dict exists $pfad $m]
                    ? [dict get $pfad $m] : {}}]: [string range $t 0 60]"
        }
    }
    puts ""
}

::pdfium::close $doc
puts "----------------------------------------------------------"
if {[info exists nichtGetaggt]} {
    set weitere [expr {$befunde - 1}]
    puts "[llength $seiten] Seite(n) geprueft; das Dokument ist nicht\
            ausgezeichnet[expr {$weitere ? ", $weitere Seite(n) mit weiterem Befund" : ""}]"
} elseif {$befunde} {
    puts "[llength $seiten] Seite(n) geprueft, $befunde mit Befund"
} else {
    puts "[llength $seiten] Seite(n) geprueft, ohne Befund"
}
exit [expr {$befunde ? 1 : 0}]
