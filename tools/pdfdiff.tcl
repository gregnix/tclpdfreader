#!/usr/bin/env tclsh
# pdfdiff.tcl -- zwei PDF-Dateien vergleichen, auf drei Ebenen
#
#   tclsh pdfdiff.tcl alt.pdf neu.pdf ?-optionen?
#
#   -text 0|1      Textvergleich je Seite (Vorgabe 1)
#   -bild 0|1      Bildvergleich je Seite (Vorgabe 1, braucht Tk)
#   -aufbau 0|1    Objektvergleich je Seite (Vorgabe 0)
#   -dpi n         Aufloesung fuer den Bildvergleich (Vorgabe 72)
#   -kontext n     Zeilen Umgebung im Textdiff (Vorgabe 2, -1 = alle)
#   -seiten SPEC   nur diese Seiten, "1-3,5" oder eine Liste
#
# WARUM DIESES SKRIPT:
#
# Die Frage "hat sich wirklich nur das geaendert, was ich wollte" stellt
# sich bei jeder Aenderung an einer PDF-Bibliothek. Am 05.09.2026 wurde
# sie dreimal an einem Tag von Hand beantwortet -- Bildschirm gegen
# Druckansicht, mit gegen ohne Formularschicht, vor gegen nach dem
# Einbrennen. Jedes Mal derselbe Zehnzeiler, jedes Mal weggeworfen.
#
# DREI EBENEN, weil eine nicht reicht:
#
#   Byte    "identisch?" -- die schnellste Antwort, und meist die
#           falsche: zwei Laeufe derselben Bibliothek unterscheiden sich
#           schon im Zeitstempel.
#   Text    was ein Leser sieht. Findet vertauschte, fehlende oder
#           veraenderte Woerter.
#   Bild    was ein Drucker sieht. Findet, was der Text NICHT zeigt:
#           verschobene Linien, andere Schrift, eine Ebene, die
#           verschwindet. Genau der Fall, der uns beschaeftigt hat.
#   Aufbau  woraus die Seite gezeichnet ist. Findet, was Text und Bild
#           beide nicht zeigen: ein Bild, das durch einen Pfad ersetzt
#           wurde und gleich aussieht.
#
# WAS ES NICHT TUT: entscheiden, ob ein Unterschied schlimm ist. Es
# zeigt, wo einer ist.

package require Tcl 8.6-

set here [file dirname [file normalize [info script]]]

# --- Abhaengigkeiten, beim Namen genannt ------------------------------
#
# Wer nicht die ganze tclutils-Sammlung will, braucht genau diese vier
# Dateien -- nachgemessen am 05.09.2026, indem sie einzeln in ein leeres
# Verzeichnis gelegt wurden:
#
#   tclutils/common-0.1.tm      Grundlage; 97 von 136 Modulen nennen sie
#   tclutils/tudiff-0.1.tm      Textebene (LCS)
#   tclutils/tucmp-0.1.tm       Byteebene, mit Fundstelle
#   tclutils/tudhash-0.1.tm     Bildebene (laeuft auch ohne common)
#
# tclutils::tupagespec kommt dazu, wenn "-seiten 1-3,5" benutzt wird.
proc brauche {paket zweck} {
    if {[catch {package require $paket} e]} {
        puts stderr "pdfdiff: braucht das Paket \"$paket\" fuer $zweck"
        puts stderr "  ($e)"
        exit 2
    }
}

brauche pdfiumtcl "Seitenzahl, Text und Rendern"

# "-forms" gibt es erst ab pdfiumtcl 0.6.2. Aeltere Fassungen brechen
# sonst MITTEN im Vergleich mit "unknown option -forms" ab -- gemessen
# am 05.09.2026 mit einer installierten 0.6.1 im auto_path. Lieber
# vorher fragen und ohne Formularschicht weitermachen, als auf halber
# Strecke stehenzubleiben.
set kannForms [package vsatisfies [package provide pdfiumtcl] 0.6.2-]
if {!$kannForms} {
    puts "Hinweis: pdfiumtcl [package provide pdfiumtcl] kennt \"-forms\"\
            noch nicht (ab 0.6.2)."
    puts "  Gefuellte Formularfelder sind im Bildvergleich darum NICHT zu"
    puts "  sehen. Der Textvergleich ist davon nicht betroffen."
}
brauche tclutils::tucmp "den Bytevergleich"
brauche tclutils::tudiff "den Textvergleich"

# --- Argumente --------------------------------------------------------
set opt [dict create -text 1 -bild 1 -aufbau 0 -dpi 72 -kontext 2 -seiten ""]
set dateien {}
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    if {[string match "-*" $a]} {
        if {![dict exists $opt $a]} {
            puts stderr "pdfdiff: unbekannte Option \"$a\""
            exit 2
        }
        dict set opt $a [lindex $argv [incr i]]
    } else {
        lappend dateien $a
    }
}
if {[llength $dateien] != 2} {
    puts stderr "Aufruf: tclsh pdfdiff.tcl alt.pdf neu.pdf ?-optionen?"
    puts stderr "  -text/-bild/-aufbau 0|1  -dpi n  -kontext n  -seiten SPEC"
    exit 2
}
lassign $dateien alt neu
foreach f [list $alt $neu] {
    if {![file readable $f]} {
        puts stderr "pdfdiff: nicht lesbar: $f"
        exit 2
    }
}

# Tk nur laden, wenn wirklich gerendert wird. Ein Bildvergleich ohne
# Anzeige ist nicht moeglich -- das gehoert gesagt, nicht stillschweigend
# uebersprungen.
set bild [dict get $opt -bild]
if {$bild} {
    if {[catch {package require Tk} e]} {
        puts "Hinweis: kein Tk ($e) -- der Bildvergleich entfaellt."
        set bild 0
    } elseif {[catch {package require tclutils::tudhash} e]} {
        puts "Hinweis: kein tclutils::tudhash -- der Bildvergleich entfaellt."
        set bild 0
    }
}


# --- Hilfsprozeduren --------------------------------------------------

# Ein dhash aus einem Tk-Bild.
#
# VORHER VERKLEINERN, und zwar mit "copy -subsample": eine A4-Seite bei
# 72 dpi hat 595 x 842 Punkte, also eine halbe Million -- und die Liste
# fuer fromRGB haette anderthalb Millionen Eintraege. Das dauert in Tcl
# Sekunden je Seite.
#
# Der Hash faltet ohnehin auf 9 x 8 zusammen; ein Zwischenschritt auf
# rund hundert Punkte Breite aendert am Ergebnis nichts Wesentliches --
# solange BEIDE Bilder gleich behandelt werden, und das tun sie.
proc hashVonBild {img} {
    set w [image width $img]
    set h [image height $img]
    set schritt [expr {$w > 200 ? $w / 100 : 1}]
    if {$schritt < 1} { set schritt 1 }
    image create photo ::pdKlein
    ::pdKlein copy $img -subsample $schritt $schritt
    set kw [image width ::pdKlein]
    set kh [image height ::pdKlein]
    set rgb {}
    foreach zeile [::pdKlein data] {
        foreach px $zeile {
            # "#rrggbb" in drei Zahlen. scan ist hier schneller als
            # string range plus format.
            scan $px "#%2x%2x%2x" r g b
            lappend rgb $r $g $b
        }
    }
    image delete ::pdKlein
    return [::tclutils::tudhash::fromRGB $kw $kh $rgb]
}

# Wieviele Objekte welcher Art -- "path 8 text 28".
#
# Nicht die Rechtecke vergleichen: die aendern sich schon durch eine
# andere Rundung, und dann meldet jede Seite einen Unterschied. Die
# ANZAHL je Art ist grob genug, um Rauschen zu ueberstehen, und fein
# genug, um ein Bild zu bemerken, das durch einen Pfad ersetzt wurde.
proc artenZaehlen {doc idx} {
    if {[catch {::pdfium::pageobjects $doc $idx} objekte]} { return "?" }
    set arten [dict create]
    foreach e $objekte { dict incr arten [lindex $e 1] }
    set aus {}
    foreach k [lsort [dict keys $arten]] {
        lappend aus "$k [dict get $arten $k]"
    }
    return [join $aus ", "]
}

# --- Byteebene --------------------------------------------------------
puts "pdfdiff"
puts "  alt: $alt ([file size $alt] Bytes)"
puts "  neu: $neu ([file size $neu] Bytes)"
puts ""

set b [::tclutils::tucmp::files $alt $neu]
if {[dict get $b equal]} {
    puts "Byteweise IDENTISCH -- es gibt nichts zu vergleichen."
    exit 0
}
puts [format "Byteweise verschieden ab Offset %s (%s gegen %s)" \
        [dict get $b offset] [dict get $b byte1] [dict get $b byte2]]
puts "  Das allein sagt wenig: schon der Zeitstempel unterscheidet zwei"
puts "  Laeufe derselben Bibliothek."
puts ""

# --- Seiten -----------------------------------------------------------
set dA [::pdfium::open $alt]
set dB [::pdfium::open $neu]
set nA [::pdfium::pagecount $dA]
set nB [::pdfium::pagecount $dB]

if {$nA != $nB} {
    puts "SEITENZAHL: $nA gegen $nB"
    puts ""
}
set n [expr {$nA < $nB ? $nA : $nB}]

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
        # Auffangen und sagen, WORAN es liegt: verglichen werden nur die
        # Seiten, die es in BEIDEN Dateien gibt, also hoechstens $n. Wer
        # "1,4" angibt und eine der Dateien hat nur eine Seite, bekam
        # sonst eine rohe Tcl-Ablaufverfolgung.
        if {[catch {::tclutils::tupagespec::parse $spec $n} seiten]} {
            puts stderr "pdfdiff: Seitenangabe \"$spec\": $seiten"
            if {$nA != $nB} {
                puts stderr "  (verglichen wird bis Seite $n --\
                        $nA gegen $nB Seiten)"
            }
            ::pdfium::close $dA
            ::pdfium::close $dB
            exit 2
        }
    }
}

# --- Vergleich je Seite -----------------------------------------------
set gleich 0
set anders {}

foreach p $seiten {
    if {$p < 1 || $p > $n} {
        puts "Seite $p: ausserhalb 1..$n -- uebersprungen"
        continue
    }
    set idx [expr {$p - 1}]
    set befund {}

    # Text
    if {[dict get $opt -text]} {
        set tA [::pdfium::gettext $dA $idx]
        set tB [::pdfium::gettext $dB $idx]
        if {$tA ne $tB} { lappend befund text }
    }

    # Bild: EIN Hash je Seite statt eines Pixelvergleichs.
    #
    # Das Pixelzaehlen von Hand sagte nur "es hat sich etwas geaendert".
    # Der Abstand zweier Hashes sagt WIE VIEL -- 0 heisst gleich, ein
    # kleiner Wert heisst Rundung, ein grosser heisst wirklich anders.
    set abstand ""
    if {$bild} {
        # "-forms 1": ein Formularfeld gehoert zu dem, was ein Betrachter
        # zeigt. Ohne das sieht pdfdiff einen gefuellten Wert NICHT --
        # gemessen an zwei Dateien, die sich genau darin unterschieden,
        # und der Vergleich meldete "gleich". Richtig gemessen, aber am
        # Thema vorbei.
        set formArg [expr {$kannForms ? {-forms 1} : {}}]
        ::pdfium::render $dA $idx -dpi [dict get $opt -dpi] {*}$formArg \
                -imagename ::pdA
        ::pdfium::render $dB $idx -dpi [dict get $opt -dpi] {*}$formArg \
                -imagename ::pdB
        set hA [hashVonBild ::pdA]
        set hB [hashVonBild ::pdB]
        image delete ::pdA ::pdB
        set abstand [::tclutils::tudhash::distance $hA $hB]
        if {$abstand > 0} { lappend befund "bild:$abstand" }
    }

    # Aufbau
    if {[dict get $opt -aufbau]} {
        set oA [artenZaehlen $dA $idx]
        set oB [artenZaehlen $dB $idx]
        if {$oA ne $oB} { lappend befund "aufbau" }
    }

    if {![llength $befund]} {
        incr gleich
        continue
    }
    lappend anders $p
    puts "Seite $p: [join $befund {, }]"

    if {[dict get $opt -text] && "text" in $befund} {
        set d [::tclutils::tudiff::unifiedText $tA $tB \
                -fromlabel "alt Seite $p" -tolabel "neu Seite $p" \
                -context [dict get $opt -kontext]]
        foreach zeile [split $d \n] { puts "    $zeile" }
    }
    if {[dict get $opt -aufbau] && "aufbau" in $befund} {
        puts "    alt: $oA"
        puts "    neu: $oB"
    }
    puts ""
}

::pdfium::close $dA
::pdfium::close $dB

puts "----------------------------------------------------------"
puts "[llength $seiten] Seite(n) verglichen: $gleich gleich, [llength $anders] verschieden"
if {[llength $anders]} { puts "Verschieden: [join $anders {, }]" }
exit [expr {[llength $anders] ? 1 : 0}]
