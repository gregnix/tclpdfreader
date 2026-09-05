# tclpdfreader -- unified read-only facade over three PDF backends, with
# graceful degradation depending on what is installed:
#
#   tupdf   (pure Tcl, tclutils::tupdf)  -- always-available core; structure,
#           metadata, trailer, raw objects, ZUGFeRD. No external dependency,
#           but token-scan only (no compressed object/xref streams).
#   pdfium  (native, package "pdfiumtcl") -- render, page text, search,
#           form fields, bookmarks. Needs libpdfium.
#   qpdf    (CLI)                          -- accurate page count, full JSON
#           structure incl. compressed objects, acroform.
#
# The caller uses one API; each call picks the best backend present and errors
# clearly when a capability needs a backend that is missing.
package require Tcl 8.6-

namespace eval ::tclpdfreader {
    variable counter 0
    variable S            ;# S($handle) = state dict
    variable have
    array set have {tupdf 0 pdfium 0 qpdf 0 rl_json 0}
    # Optional backends, detected at load; missing ones degrade gracefully.
    # (tclpdfium 0.5.1+ loads Tk lazily, so requiring pdfiumtcl pulls no Tk.)
    if {![catch {package require tclutils::tupdf}]} { set have(tupdf) 1 }
    if {![catch {package require pdfiumtcl}]}       { set have(pdfium) 1 }
    if {[llength [auto_execok qpdf]] > 0}           { set have(qpdf) 1 }
    if {![catch {package require rl_json}]}         { set have(rl_json) 1 }
}

# ---- helpers --------------------------------------------------------------
proc ::tclpdfreader::_check {h} {
    variable S
    if {![info exists S($h)]} { return -code error "tclpdfreader: invalid handle \"$h\"" }
}
proc ::tclpdfreader::_file {h} { variable S; dict get $S($h) file }
proc ::tclpdfreader::_need {backend what} {
    variable have
    if {!$have($backend)} {
        return -code error "tclpdfreader: \"$what\" braucht Backend \"$backend\" (nicht installiert)"
    }
}
proc ::tclpdfreader::_qpdf {args} { exec qpdf {*}$args }

# ---- lifecycle ------------------------------------------------------------
proc ::tclpdfreader::open {file {password ""}} {
    variable counter; variable S; variable have
    if {![file exists $file]} { return -code error "tclpdfreader: no such file: $file" }
    set h reader[incr counter]
    set pdoc ""
    if {$have(pdfium)} {
        set a [list $file]; if {$password ne ""} { lappend a $password }
        catch {::pdfium::open {*}$a} pdoc
        if {[string match "*rror*" $pdoc]} { set pdoc "" }
    }
    set S($h) [dict create file $file password $password pdfium $pdoc]
    return $h
}
proc ::tclpdfreader::close {h} {
    variable S
    _check $h
    set pdoc [dict get $S($h) pdfium]
    if {$pdoc ne ""} { catch {::pdfium::close $pdoc} }
    unset S($h)
    return
}
# Which backends are usable for this document right now.
proc ::tclpdfreader::backends {h} {
    variable have; variable S
    _check $h
    set out {}
    if {$have(tupdf)}  { lappend out tupdf }
    if {[dict get $S($h) pdfium] ne ""} { lappend out pdfium }
    if {$have(qpdf)}   { lappend out qpdf }
    return $out
}

# ---- metadata / structure (pure-Tcl first) --------------------------------
proc ::tclpdfreader::version {h} {
    variable have
    _check $h
    set f [_file $h]
    if {$have(tupdf)} { return [::tclutils::tupdf::version $f] }
    # pure fallback: read the header line
    set fh [::open $f rb]; set head [read $fh 32]; ::close $fh
    if {[regexp {%PDF-([0-9.]+)} $head -> v]} { return $v }
    return ""
}
proc ::tclpdfreader::metadata {h} {
    variable have; variable S
    _check $h
    if {$have(tupdf)} {
        set m [::tclutils::tupdf::metadata [_file $h]]
        if {[llength $m] > 0} { _trace "metadata via tupdf"; return $m }
    }
    set pdoc [dict get $S($h) pdfium]
    if {$pdoc ne ""} { _trace "metadata via pdfium"; return [_metaFromPdfium $pdoc] }
    return {}
}
proc ::tclpdfreader::_metaFromPdfium {pdoc} {
    set out {}
    foreach k {Title Author Subject Keywords Creator Producer CreationDate ModDate} {
        set v ""
        catch {set v [::pdfium::meta $pdoc $k]}
        if {[string trim $v] ne ""} { dict set out $k $v }
    }
    return $out
}
proc ::tclpdfreader::trailer {h} {
    _check $h; _need tupdf trailer
    return [::tclutils::tupdf::trailer [_file $h]]
}
proc ::tclpdfreader::object {h id} {
    variable have
    _check $h
    if {$have(tupdf)} {
        set o [::tclutils::tupdf::object [_file $h] $id]
        if {$o ne ""} { return $o }
    }
    if {$have(qpdf)} { return [_qpdf [_file $h] --show-object=$id] }
    return -code error "tclpdfreader: object $id nicht auffindbar (nur tupdf sieht keine komprimierten Objekte)"
}
proc ::tclpdfreader::zugferd {h} {
    variable have
    _check $h
    if {$have(tupdf)} { _trace "zugferd via tupdf"; return [::tclutils::tupdf::zugferd [_file $h]] }
    if {$have(qpdf)}  { _trace "zugferd via qpdf"; return [_zugferdFromQpdf [_file $h]] }
    return -code error "tclpdfreader: zugferd braucht Backend \"tupdf\" oder \"qpdf\""
}
# Light Factur-X/ZUGFeRD/XRechnung detection via qpdf attachment names.
proc ::tclpdfreader::_zugferdFromQpdf {f} {
    set names {}
    if {![catch {_qpdf $f --json --json-key=attachments} j]} {
        set names [_jsonKeys $j attachments]
    }
    set detected 0
    foreach n $names {
        if {[regexp -nocase {factur-x|zugferd|xrechnung|order-x} $n]} { set detected 1 }
    }
    return [dict create detected $detected profile {} \
                attachmentNames $names mimeTypes {} hints qpdf]
}
# keys of a json object at a path (rl_json preferred, tcllib fallback)
proc ::tclpdfreader::_jsonKeys {j args} {
    variable have
    if {$have(rl_json)} {
        if {![rl_json::json exists $j {*}$args]} { return {} }
        return [rl_json::json keys $j {*}$args]
    }
    if {![catch {package require json}]} {
        set d [::json::json2dict $j]
        if {[dict exists $d {*}$args]} { return [dict keys [dict get $d {*}$args]] }
    }
    return {}
}

# ---- page count: pdfium > qpdf (exact) > tupdf (lower bound) ---------------
proc ::tclpdfreader::pagecount {h} {
    variable have; variable S
    _check $h
    set pdoc [dict get $S($h) pdfium]
    if {$pdoc ne ""}  { _trace "pagecount via pdfium"; return [::pdfium::pagecount $pdoc] }
    if {$have(qpdf)}  { _trace "pagecount via qpdf"; return [string trim [_qpdf [_file $h] --show-npages]] }
    if {$have(tupdf)} {
        set sum [::tclutils::tupdf::summary [_file $h]]
        if {[dict exists $sum pages]} { return [dict get $sum pages] }
    }
    return -code error "tclpdfreader: pagecount nicht bestimmbar"
}
# Is the page count exact, or a lower bound (tupdf-only)?
proc ::tclpdfreader::pagecountExact {h} {
    variable have; variable S
    _check $h
    expr {[dict get $S($h) pdfium] ne "" || $have(qpdf)}
}

# ---- content: page text / search / form fields (need pdfium) --------------
# Facade pages are 1-based (page 1 = first). pdfium is 0-based -> convert.
proc ::tclpdfreader::_pdfium {h what} {
    variable S; _check $h
    set pdoc [dict get $S($h) pdfium]
    if {$pdoc eq ""} { return -code error "tclpdfreader: $what braucht Backend \"pdfium\"" }
    return $pdoc
}
proc ::tclpdfreader::_pageIndex {h page} {
    set n [pagecount $h]
    if {![string is integer -strict $page] || $page < 1 || $page > $n} {
        return -code error "tclpdfreader: Seite \"$page\" ausserhalb 1..$n"
    }
    return [expr {$page - 1}]
}
proc ::tclpdfreader::pagetext {h page} {
    set pdoc [_pdfium $h pagetext]
    return [::pdfium::gettext $pdoc [_pageIndex $h $page]]
}
proc ::tclpdfreader::search {h page text args} {
    set pdoc [_pdfium $h search]
    return [::pdfium::search $pdoc [_pageIndex $h $page] $text {*}$args]
}
proc ::tclpdfreader::bookmarks {h} {
    set pdoc [_pdfium $h bookmarks]
    return [::pdfium::bookmarks $pdoc]
}
# Form fields: pdfium natively (1-based here); else best-effort from qpdf JSON.
proc ::tclpdfreader::formfields {h {page ""}} {
    variable have; variable S
    _check $h
    set pdoc [dict get $S($h) pdfium]
    if {$pdoc ne ""} {
        if {$page eq ""} {
            set all {}
            set n [pagecount $h]
            for {set p 1} {$p <= $n} {incr p} {
                catch {lappend all {*}[::pdfium::formfields $pdoc [expr {$p - 1}]]}
            }
            return $all
        }
        _trace "formfields via pdfium"
        return [::pdfium::formfields $pdoc [_pageIndex $h $page]]
    }
    if {$have(qpdf)} { _trace "formfields via qpdf"; return [_formsFromJson [_file $h]] }
    return -code error "tclpdfreader: formfields braucht \"pdfium\" oder \"qpdf\""
}

# ---- page geometry --------------------------------------------------------
#
# Wer einen Stempel oder ein Wasserzeichen ueber eine fremde Seite legen
# will, braucht drei Dinge: das Blattmass, den Beschnitt und die Drehung.
# Ohne die Drehung steht der Stempel quer, sobald eine Seite /Rotate 90
# traegt -- und das faellt erst auf dem Papier auf.
#
# EINHEITEN, weil sie hier auseinandergehen: in der DATEI stehen Punkte
# (1/72 Zoll), pdfium meldet MILLIMETER. Beides wird gemeldet, keines
# stillschweigend umgerechnet -- wer den Stempel mit pdf4tcl baut,
# braucht Punkte, wer ihn ausmisst, meist Millimeter.
#
#   width height        Punkt, aus /MediaBox
#   widthmm heightmm    Millimeter, dieselbe Groesse
#   rotate              0, 90, 180 oder 270
#   mediabox cropbox    die Rechtecke selbst, leer wenn unbekannt
#   source              welches Backend geantwortet hat
proc ::tclpdfreader::pagesize {h page} {
    variable have; variable S
    _check $h
    set idx [_pageIndex $h $page]
    set res [dict create width "" height "" widthmm "" heightmm "" \
            rotate 0 mediabox {} cropbox {} source ""]

    # qpdf zuerst: es liest die Rechtecke, wie sie in der Datei stehen,
    # samt /CropBox und geerbtem /MediaBox aus dem Seitenbaum.
    if {$have(qpdf)} {
        if {![catch {_pageBoxesFromQpdf [_file $h] $idx} boxen] && \
                [dict get $boxen mediabox] ne ""} {
            set res [dict merge $res $boxen]
            dict set res source qpdf
        }
    }
    # pdfium ergaenzt oder springt ein. Es liefert Millimeter und die
    # Drehung, aber keine Rechtecke.
    set pdoc [dict get $S($h) pdfium]
    if {$pdoc ne ""} {
        if {![catch {::pdfium::pagesize $pdoc $idx} mm]} {
            lassign $mm wmm hmm
            dict set res widthmm $wmm
            dict set res heightmm $hmm
            if {[dict get $res width] eq ""} {
                dict set res width  [expr {$wmm * 72.0 / 25.4}]
                dict set res height [expr {$hmm * 72.0 / 25.4}]
                dict set res source pdfium
            }
        }
        if {![catch {::pdfium::rotation $pdoc $idx} r]} { dict set res rotate $r }
    }
    if {[dict get $res width] eq ""} {
        return -code error "tclpdfreader: pagesize braucht \"qpdf\" oder \"pdfium\""
    }
    if {[dict get $res widthmm] eq ""} {
        dict set res widthmm  [expr {[dict get $res width]  * 25.4 / 72.0}]
        dict set res heightmm [expr {[dict get $res height] * 25.4 / 72.0}]
    }
    return $res
}

# /MediaBox, /CropBox und /Rotate einer Seite aus qpdf --json.
#
# Alle drei duerfen im Seitenbaum VERERBT sein (ISO 32000-1 7.7.3.4) --
# eine Seite ohne eigenes /MediaBox holt es vom Elternknoten. qpdf loest
# das in seiner JSON-Ausgabe bereits auf, deshalb wird hier nichts
# nachgeschlagen; wer den Baum selbst laeuft, muss es tun.
proc ::tclpdfreader::_pageBoxesFromQpdf {file idx} {
    set res [dict create mediabox {} cropbox {} width "" height "" rotate 0]
    if {[catch {_qpdf $file --json --json-key=pages} j]} { return $res }
    # Die Seiten stehen in der Reihenfolge des Dokuments; die idx-te ist
    # unsere. Ohne rl_json reicht ein Durchgang durch die Objekte.
    set seiten {}
    foreach zeile [split $j \n] {
        if {[regexp {"object":\s*"([0-9]+ [0-9]+ R)"} $zeile -> o]} {
            lappend seiten $o
        }
    }
    set obj [lindex $seiten $idx]
    if {$obj eq ""} { return $res }
    if {[catch {_qpdf $file --json --json-object=$obj} jo]} { return $res }
    foreach {schluessel feld} {MediaBox mediabox CropBox cropbox} {
        if {[regexp "\"/$schluessel\":\\s*\\\[(\[^\\\]\]*)\\\]" $jo -> werte]} {
            set zahlen {}
            foreach z [split [string map {, " "} $werte] " "] {
                # trim VOR der Pruefung: "string is double" laesst
                # umgebende Leerzeichen und Zeilenumbrueche durchgehen,
                # und ein "842\n" landete dann als solches im Rechteck.
                set z [string trim $z]
                if {$z ne "" && [string is double -strict $z]} {
                    lappend zahlen $z
                }
            }
            if {[llength $zahlen] == 4} { dict set res $feld $zahlen }
        }
    }
    if {[regexp {"/Rotate":\s*(-?[0-9]+)} $jo -> r]} {
        dict set res rotate [expr {(($r % 360) + 360) % 360}]
    }
    set mb [dict get $res mediabox]
    if {[llength $mb] == 4} {
        lassign $mb x1 y1 x2 y2
        dict set res width  [expr {abs($x2 - $x1)}]
        dict set res height [expr {abs($y2 - $y1)}]
    }
    return $res
}

# Steht auf der Seite Text, oder ist es ein Scan?
#
# Beantwortet vorab, ob "search" ueberhaupt etwas finden kann. Ohne die
# Auskunft sucht man auf einem gescannten Blatt und haelt das leere
# Ergebnis fuer einen Fehler.
proc ::tclpdfreader::hastext {h page} {
    set pdoc [_pdfium $h hastext]
    set t [::pdfium::gettext $pdoc [_pageIndex $h $page]]
    expr {[string trim $t] ne ""}
}

# Ist die Datei geschuetzt, und was ist erlaubt?
#
# Ueberlagern und Bearbeiten scheitern an einer verschluesselten Datei
# ohne Passwort -- besser vorher fragen als hinterher eine qpdf-Meldung
# deuten.
proc ::tclpdfreader::encryption {h} {
    variable have; variable S
    _check $h
    set res [dict create encrypted 0 method "" printing 1 modify 1 extract 1]
    if {!$have(qpdf)} {
        # pdfium kann wenigstens sagen, ob gedruckt werden darf.
        set pdoc [dict get $S($h) pdfium]
        if {$pdoc ne "" && ![catch {::pdfium::canprint $pdoc} c]} {
            dict set res printing $c
        }
        return $res
    }
    if {[catch {_qpdf [_file $h] --show-encryption} out]} { return $res }
    if {[string match -nocase "*not encrypted*" $out]} { return $res }
    dict set res encrypted 1
    foreach {muster feld} {"*print: not allowed*" printing
                           "*modify: not allowed*" modify
                           "*extract: not allowed*" extract} {
        if {[string match -nocase $muster $out]} { dict set res $feld 0 }
    }
    if {[regexp -nocase {R = ([0-9]+)} $out -> r]} { dict set res method "R$r" }
    return $res
}

# Alle Seitenmasse auf einmal.
#
# Wer stempelt, braucht sie fuer jede Seite -- einzeln abgefragt bezahlt
# man den qpdf-Aufruf je Seite. Hier einmal durchgehen und die Liste
# zurueckgeben.
proc ::tclpdfreader::pagesizes {h} {
    _check $h
    set alle {}
    set n [pagecount $h]
    for {set p 1} {$p <= $n} {incr p} { lappend alle [pagesize $h $p] }
    return $alle
}

# Anmerkungen einer Seite -- was schon darauf liegt.
#
# Wer stempelt, sollte wissen, was er ueberklebt: ein Kommentar, ein
# Verweis, ein Formularfeld. Ohne die Auskunft merkt man es erst, wenn
# jemand das PDF oeffnet und der Verweis unter dem Stempel liegt.
proc ::tclpdfreader::annotations {h page} {
    set pdoc [_pdfium $h annotations]
    return [::pdfium::annot_list $pdoc [_pageIndex $h $page]]
}

# Verweise einer Seite (Ziel und Rechteck).
proc ::tclpdfreader::links {h page} {
    set pdoc [_pdfium $h links]
    return [::pdfium::links $pdoc [_pageIndex $h $page]]
}

# Seitenbeschriftungen: /PageLabels aus dem Katalog.
#
# Das ist NICHT die Seitennummer. Ein Dokument kann roemisch beginnen,
# bei 1 neu anfangen oder einen Anhang mit A-1 zaehlen. Wer eine
# Seitenzahl aufstempelt, will meist die BESCHRIFTUNG, nicht den Index --
# sonst steht auf Seite iv eine 4.
#
# Rueckgabe: Liste von {index stil praefix start}, wie im Katalog. Leer,
# wenn das Dokument keine hat -- dann ist die Beschriftung die Nummer.
proc ::tclpdfreader::pagelabels {h} {
    variable have
    _check $h
    if {!$have(qpdf)} { return {} }
    if {[catch {_qpdf [_file $h] --json --json-key=pagelabels} j]} { return {} }
    set res {}
    # Ohne rl_json reicht ein Durchgang: die Eintraege sind flach.
    set idx "" ; set stil "" ; set praefix "" ; set start ""
    foreach zeile [split $j \n] {
        if {[regexp {"index":\s*([0-9]+)} $zeile -> v]} {
            if {$idx ne ""} { lappend res [list $idx $stil $praefix $start] }
            set idx $v ; set stil "" ; set praefix "" ; set start ""
        }
        if {[regexp {"/S":\s*"/([A-Za-z]+)"} $zeile -> v]}  { set stil $v }
        if {[regexp {"/P":\s*"u:([^"]*)"} $zeile -> v]}     { set praefix $v }
        if {[regexp {"/St":\s*([0-9]+)} $zeile -> v]}       { set start $v }
    }
    if {$idx ne ""} { lappend res [list $idx $stil $praefix $start] }
    return $res
}

# Eingebettete Dateien: Schluessel und Name.
#
# Gegenstueck zu tclpdfwriter::addAttachment und removeAttachments -- zum
# Entfernen braucht man den SCHLUESSEL, und den nennt sonst nur
# "qpdf --list-attachments" auf der Kommandozeile.
proc ::tclpdfreader::attachments {h} {
    variable have
    _check $h
    if {!$have(qpdf)} { return {} }
    if {[catch {_qpdf [_file $h] --list-attachments} out]} { return {} }
    set res {}
    foreach zeile [split $out \n] {
        # "schluessel -> 12,0" bzw. mit --verbose mehr; der Schluessel
        # steht immer am Anfang.
        set zeile [string trim $zeile]
        if {$zeile eq "" || [string match "*attachments*" $zeile]} continue
        if {[regexp {^(\S+)\s*->} $zeile -> k]} { lappend res $k }
    }
    return $res
}

# Ebenen (Optional Content Groups) des Dokuments.
#
# Rueckgabe je Ebene ein dict:
#   id       das Objekt, "4 0 R"
#   name     der Name, wie er im Betrachter steht
#   visible  1 wenn beim Oeffnen sichtbar (aus /ON, /OFF und /BaseState)
#   print    1 gedruckt, 0 nicht, "" wenn die Datei nichts dazu sagt
#
# WARUM HIER UND NICHT IN tclpdfium: pdfium befolgt Ebenen beim Rendern,
# hat aber keine Schnittstelle, sie aufzuzaehlen oder zu schalten. Wer
# wissen will, WELCHE Ebenen ein Dokument hat, muss in die Datei sehen --
# und das kann qpdf. Nachgemessen am 05.09.2026: pdfium meldet an einem
# Objekt nur, DASS es in einer Ebene liegt (Markierung "OC"), die
# Parameter kommen als Typ 0 zurueck.
#
# "print" ist die Angabe aus /Usage /Print /PrintState. Leer heisst: die
# Datei sagt nichts, der Betrachter entscheidet -- das ist etwas anderes
# als "ja".
proc ::tclpdfreader::layers {h} {
    variable have
    _check $h
    if {!$have(qpdf)} { return {} }
    if {[catch {_qpdf [_file $h] --json} j]} { return {} }

    # ZEILENWEISE durchgehen, nicht mit einer Regex ueber die ganze
    # Ausgabe.
    #
    # Der erste Versuch stand hier mit einem Muster fuer verschachtelte
    # Klammern -- schon als Muster kaum zu lesen, und ein OCG mit /Usage
    # hat zwei Ebenen, also haette es sie ohnehin nicht alle getroffen.
    # qpdf schreibt die JSON-Ausgabe eingerueckt und mit einem Schluessel
    # je Zeile; das reicht voellig.
    set aus      {}
    set druckbar {}
    set hatAS    0

    # qpdf schreibt Arrays ueber mehrere Zeilen, also merken, in welchem
    # Abschnitt wir gerade sind.
    set abschnitt ""
    set event ""
    foreach zeile [split $j \n] {
        set t [string trim $zeile]
        if {[string match {"/OFF":*} $t]}      { set abschnitt off ; continue }
        if {[string match {"/ON":*} $t]}       { set abschnitt on  ; continue }
        if {[string match {"/Event":*} $t]} {
            regexp {"/Event":\s*"/([A-Za-z]+)"} $t -> event
            continue
        }
        if {[string match {"/OCGs":*} $t]} {
            set abschnitt [expr {$event eq "Print" ? "printas" : "andere"}]
            if {$abschnitt eq "printas"} { set hatAS 1 }
            continue
        }
        if {[string match "\]*" $t]} { set abschnitt "" ; continue }
        if {$abschnitt eq "" } continue
        if {![regexp {"([0-9]+ [0-9]+ R)"} $t -> ref]} continue
        switch -- $abschnitt {
            off     { lappend aus $ref }
            printas { lappend druckbar $ref }
        }
    }

    # Und die OCG-Objekte selbst: "obj:N 0 R" leitet einen Block ein,
    # der bis zum naechsten "obj:" reicht.
    set ergebnis {}
    set id ""
    set name ""
    set imOCG 0
    set printState ""
    foreach zeile [split $j \n] {
        set t [string trim $zeile]
        if {[regexp {"obj:([0-9]+ [0-9]+ R)":} $t -> neueId]} {
            # Den vorigen Block abschliessen.
            if {$imOCG} {
                lappend ergebnis [_layerDict $id $name $printState \
                        $aus $druckbar $hatAS]
            }
            set id $neueId ; set name "" ; set imOCG 0 ; set printState ""
            continue
        }
        if {[string match {*"/Type":*"/OCG"*} $t]} { set imOCG 1 ; continue }
        if {[regexp {"/Name":\s*"u:(.*)"} $t -> n]} { set name $n ; continue }
        if {[regexp {"/PrintState":\s*"/([A-Z]+)"} $t -> ps]} {
            set printState [expr {$ps eq "ON"}]
        }
    }
    if {$imOCG} {
        lappend ergebnis [_layerDict $id $name $printState $aus $druckbar $hatAS]
    }
    return $ergebnis
}

proc ::tclpdfreader::_layerDict {id name printState aus druckbar hatAS} {
    # "print" leer heisst: die Datei sagt nichts, der Betrachter
    # entscheidet. Das ist etwas anderes als "ja" -- und wer es
    # gleichsetzt, verspricht mehr, als in der Datei steht.
    set drucken $printState
    if {$drucken eq "" && $hatAS} {
        set drucken [expr {[lsearch -exact $druckbar $id] >= 0}]
    }
    return [dict create id $id name $name \
            visible [expr {[lsearch -exact $aus $id] < 0}] \
            print $drucken]
}

# Rechtecke je Zeichen -- durchgereicht an pdfium (0.6.2).
proc ::tclpdfreader::charboxes {h page args} {
    set pdoc [_pdfium $h charboxes]
    return [::pdfium::charboxes $pdoc [_pageIndex $h $page] {*}$args]
}

# Woraus die Seite gezeichnet ist -- durchgereicht an pdfium (0.6.2).
proc ::tclpdfreader::pageobjects {h page} {
    set pdoc [_pdfium $h pageobjects]
    return [::pdfium::pageobjects $pdoc [_pageIndex $h $page]]
}

# ---- structure JSON (qpdf) ------------------------------------------------
proc ::tclpdfreader::json {h args} {
    _check $h; _need qpdf json
    return [_qpdf [_file $h] --json {*}$args]
}

# ---- capability report ----------------------------------------------------
proc ::tclpdfreader::capabilities {h} {
    _check $h
    set b [backends $h]
    set caps {}
    dict set caps version   1
    dict set caps metadata  [expr {"tupdf" in $b || "pdfium" in $b}]
    dict set caps trailer   [expr {"tupdf" in $b}]
    dict set caps object    [expr {"tupdf" in $b || "qpdf" in $b}]
    dict set caps zugferd   [expr {"tupdf" in $b || "qpdf" in $b}]
    dict set caps pagecount [expr {[llength $b] > 0}]
    dict set caps pagetext  [expr {"pdfium" in $b}]
    dict set caps search    [expr {"pdfium" in $b}]
    dict set caps bookmarks [expr {"pdfium" in $b}]
    dict set caps formfields [expr {"pdfium" in $b || "qpdf" in $b}]
    dict set caps json      [expr {"qpdf" in $b}]
    dict set caps pagesize  [expr {"qpdf" in $b || "pdfium" in $b}]
    dict set caps hastext   [expr {"pdfium" in $b}]
    dict set caps encryption [expr {"qpdf" in $b || "pdfium" in $b}]
    dict set caps annotations [expr {"pdfium" in $b}]
    dict set caps links       [expr {"pdfium" in $b}]
    dict set caps pagelabels  [expr {"qpdf" in $b}]
    dict set caps attachments [expr {"qpdf" in $b}]
    dict set caps layers      [expr {"qpdf" in $b}]
    dict set caps charboxes   [expr {"pdfium" in $b}]
    dict set caps pageobjects [expr {"pdfium" in $b}]
    return $caps
}

# ---- internal qpdf-JSON helpers (rl_json preferred) -----------------------
proc ::tclpdfreader::_formsFromJson {f} {
    # acroform extraction from qpdf --json. Preferred parser: rl_json (your
    # ecosystem standard); falls back to tcllib json, then a line scan.
    if {[catch {_qpdf $f --json --json-key=acroform} j]} { return {} }
    variable have
    if {$have(rl_json)} { return [_afRlJson $j] }
    if {![catch {package require json}]} { return [_afTcllib $j] }
    return [_afLines $j]
}
proc ::tclpdfreader::_pdfstr {v} {
    # qpdf JSON strings carry a "u:" (utf8) prefix; strip it for clean values.
    if {[string match "u:*" $v]} { return [string range $v 2 end] }
    return $v
}
proc ::tclpdfreader::_afRlJson {j} {
    set out {}
    if {![rl_json::json exists $j acroform fields]} { return {} }
    rl_json::json foreach fld [rl_json::json extract $j acroform fields] {
        set ft [string trimleft [rl_json::json get $fld fieldtype] /]
        set fn [rl_json::json get $fld fullname]
        if {"value" in [rl_json::json keys $fld] && ![rl_json::json isnull $fld value]} {
            set val [_pdfstr [rl_json::json get $fld value]]
        } else { set val "" }
        lappend out [list $ft $fn $val]
    }
    return $out
}
proc ::tclpdfreader::_afTcllib {j} {
    set out {}
    set d [::json::json2dict $j]
    if {![dict exists $d acroform fields]} { return {} }
    foreach fld [dict get $d acroform fields] {
        set ft [string trimleft [dict get $fld fieldtype] /]
        set fn [dict get $fld fullname]
        set val [expr {[dict exists $fld value] ? [dict get $fld value] : ""}]
        if {$val eq "null"} { set val "" }
        set val [_pdfstr $val]
        lappend out [list $ft $fn $val]
    }
    return $out
}
proc ::tclpdfreader::_afLines {j} {
    set out {}; set ft ""; set fn ""; set val ""
    foreach line [split $j \n] {
        if {[regexp {"fieldtype":\s*"/?([^"]*)"} $line -> x]} {
            if {$fn ne ""} { lappend out [list $ft $fn $val]; set fn ""; set val "" }
            set ft $x
        } elseif {[regexp {"fullname":\s*"([^"]*)"} $line -> x]} {
            set fn $x
        } elseif {[regexp {"value":\s*(null|"([^"]*)")} $line -> raw inner]} {
            set val [_pdfstr [expr {$raw eq "null" ? "" : $inner}]]
        }
    }
    if {$fn ne ""} { lappend out [list $ft $fn $val] }
    return $out
}

# Structured access into the full qpdf JSON (rl_json path syntax), e.g.
#   tclpdfreader::jsonget $h acroform needappearances
proc ::tclpdfreader::jsonget {h args} {
    variable have
    _check $h; _need qpdf jsonget
    set j [_qpdf [_file $h] --json]
    if {$have(rl_json)} { return [rl_json::json get $j {*}$args] }
    if {![catch {package require json}]} {
        return [_dictpath [::json::json2dict $j] {*}$args]
    }
    return -code error "tclpdfreader: jsonget braucht rl_json oder tcllib json"
}
# Walk a json2dict result: numeric segments index lists, others index dicts.
proc ::tclpdfreader::_dictpath {d args} {
    foreach k $args {
        if {[string is integer -strict $k]} {
            set d [lindex $d $k]
        } else {
            set d [dict get $d $k]
        }
    }
    return $d
}

# ---- debug / diagnostics --------------------------------------------------
namespace eval ::tclpdfreader {
    variable traceOn   0
    variable traceChan stderr
}
proc ::tclpdfreader::_trace {msg} {
    variable traceOn; variable traceChan
    if {$traceOn} { puts $traceChan "\[tclpdfreader] $msg" }
}

namespace eval ::tclpdfreader::debug {
    namespace export *
    namespace ensemble create
}

# Loaded backend versions (or "-" if absent).
proc ::tclpdfreader::debug::versions {} {
    variable ::tclpdfreader::have
    set v [dict create]
    dict set v tupdf   [expr {$::tclpdfreader::have(tupdf)   ? [package present tclutils::tupdf] : "-"}]
    dict set v pdfium  [expr {$::tclpdfreader::have(pdfium)  ? [package present pdfiumtcl]        : "-"}]
    dict set v rl_json [expr {$::tclpdfreader::have(rl_json) ? [package present rl_json]          : "-"}]
    if {$::tclpdfreader::have(qpdf)} {
        dict set v qpdf [lindex [split [::tclpdfreader::_qpdf --version] \n] 0]
    } else {
        dict set v qpdf "-"
    }
    return $v
}

# For each capability, which backend would actually serve it for this handle.
proc ::tclpdfreader::debug::which {h} {
    set b [::tclpdfreader::backends $h]
    set pick [dict create]
    dict set pick version   [expr {"tupdf"  in $b ? "tupdf"  : "header"}]
    dict set pick metadata  [::tclpdfreader::debug::_first $b {tupdf pdfium}]
    dict set pick trailer   [expr {"tupdf"  in $b ? "tupdf"  : "-"}]
    dict set pick object    [::tclpdfreader::debug::_first $b {tupdf qpdf}]
    dict set pick zugferd   [::tclpdfreader::debug::_first $b {tupdf qpdf}]
    dict set pick pagecount [::tclpdfreader::debug::_first $b {pdfium qpdf tupdf}]
    dict set pick pagetext  [expr {"pdfium" in $b ? "pdfium" : "-"}]
    dict set pick search    [expr {"pdfium" in $b ? "pdfium" : "-"}]
    dict set pick bookmarks [expr {"pdfium" in $b ? "pdfium" : "-"}]
    dict set pick formfields [::tclpdfreader::debug::_first $b {pdfium qpdf}]
    dict set pick json      [expr {"qpdf"   in $b ? "qpdf"   : "-"}]
    return $pick
}
proc ::tclpdfreader::debug::_first {have order} {
    foreach o $order { if {$o in $have} { return $o } }
    return "-"
}

# Raw qpdf JSON (optionally filtered by --json-key=... via args).
proc ::tclpdfreader::debug::rawjson {h args} {
    ::tclpdfreader::_check $h
    ::tclpdfreader::_need qpdf rawjson
    return [::tclpdfreader::_qpdf [::tclpdfreader::_file $h] --json {*}$args]
}
# Raw tupdf output: what in {version summary metadata trailer objects}.
proc ::tclpdfreader::debug::tupdf {h what} {
    ::tclpdfreader::_check $h
    ::tclpdfreader::_need tupdf "debug tupdf"
    return [::tclutils::tupdf::$what [::tclpdfreader::_file $h]]
}

# Toggle per-call backend-selection tracing. "on"/"off"/1/0, or query.
proc ::tclpdfreader::debug::trace {{state ""}} {
    variable ::tclpdfreader::traceOn
    if {$state eq ""} { return $::tclpdfreader::traceOn }
    set ::tclpdfreader::traceOn [expr {$state in {on 1 true yes}}]
    return $::tclpdfreader::traceOn
}

# Human-readable one-shot diagnostic report.
proc ::tclpdfreader::debug::report {h} {
    ::tclpdfreader::_check $h
    set L {}
    lappend L "file        : [::tclpdfreader::_file $h]"
    lappend L "backends    : [::tclpdfreader::backends $h]"
    lappend L "versions    : [versions]"
    lappend L "which       : [which $h]"
    lappend L "capabilities: [::tclpdfreader::capabilities $h]"
    catch {lappend L "version     : [::tclpdfreader::version $h]"}
    catch {lappend L "pagecount   : [::tclpdfreader::pagecount $h] (exact=[::tclpdfreader::pagecountExact $h])"}
    catch {lappend L "metadata    : [::tclpdfreader::metadata $h]"}
    catch {lappend L "zugferd     : [::tclpdfreader::zugferd $h]"}
    catch {lappend L "formfields  : [llength [::tclpdfreader::formfields $h]] Feld(er)"}
    return [join $L \n]
}

package provide tclpdfreader 0.2
