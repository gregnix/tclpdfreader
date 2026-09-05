# tclpdfreader

*Einheitliche, nur-lesende Fassade ueber drei PDF-Backends -- mit grazioeser
Degradierung je nachdem, was installiert ist.*

## Zweck

`tclpdfreader` gibt **eine** API zum Lesen bestehender PDFs. Intern waehlt jeder
Aufruf das beste vorhandene Backend und meldet klar, wenn eine Faehigkeit ein
nicht installiertes Backend braucht. Teil der Trias:

- **pdf4tcl / pdf4tcllib** -- PDFs *erzeugen* (inkl. Factur-X, PDF/A)
- **tclpdfreader** -- PDFs *lesen* (diese Bibliothek)
- **tclpdfwriter** -- PDFs *veraendern / Formulare fuellen*

## Backends

| Backend | Herkunft | Liefert | Preis |
|---------|----------|---------|-------|
| `tupdf` | rein Tcl (`tclutils::tupdf`) | version, metadata, trailer, object, ZUGFeRD | keine Abhaengigkeit; Token-Scan (keine komprimierten Objekt-/Xref-Streams), Seitenzahl = Untergrenze |
| `pdfium` | nativ (`pdfiumtcl`) | pagetext, search, bookmarks, formfields, exakte Seitenzahl | braucht `libpdfium` |
| `qpdf` | CLI (`qpdf`) | exakte Seitenzahl, JSON-Struktur, acroform-Felder | braucht das `qpdf`-Binary |

Kein Backend ist Pflicht. Mit nur dem rein-Tcl-Kern gibt es version, metadata,
struktur und ZUGFeRD. `pdfium` ergaenzt Inhalt (Text/Suche/Formulare), `qpdf`
exakte Zahlen und Struktur. Strukturiertes qpdf-JSON wird mit **rl_json**
geparst (Fallback: tcllib `json`, dann Zeilen-Scan).

## Laden

```tcl
tcl::tm::path add /pfad/zu/tclpdfreader/lib/tm
package require tclpdfreader
```

## API

### Lebenszyklus

| Aufruf | Beschreibung |
|--------|--------------|
| `tclpdfreader::open datei ?passwort?` | Oeffnet ein PDF, gibt ein Handle zurueck. Oeffnet pdfium (falls vorhanden) mit. |
| `tclpdfreader::close handle` | Schliesst das Handle (und ein evtl. offenes pdfium-Dokument). |
| `tclpdfreader::backends handle` | Liste der Backends, die dieses Dokument bedienen koennen. |
| `tclpdfreader::capabilities handle` | Dict: welche Aufrufe verfuegbar sind (1/0). |

### Metadaten / Struktur

| Aufruf | Backend | Rueckgabe |
|--------|---------|-----------|
| `version handle` | tupdf, sonst Header-Lesung | PDF-Version, z.B. `1.7` |
| `metadata handle` | tupdf, sonst pdfium | Dict (Title, Author, Subject, ...) |
| `trailer handle` | tupdf | Trailer-Dict |
| `object handle id` | tupdf, sonst qpdf | Rohes Objekt |
| `zugferd handle` | tupdf, sonst qpdf | Factur-X/ZUGFeRD-Info (detected, profile, attachmentNames, ...) |

Seiten sind **1-basiert** (Seite 1 = erste). pdfium (intern 0-basiert) wird
automatisch umgerechnet; ungueltige Seiten liefern `Seite "N" ausserhalb 1..M`.

### Seitenzahl

| Aufruf | Backend | Rueckgabe |
|--------|---------|-----------|
| `pagecount handle` | pdfium > qpdf > tupdf | Seitenzahl (beste verfuegbare) |
| `pagecountExact handle` | -- | 1 wenn exakt, 0 wenn Untergrenze (nur tupdf) |

### Inhalt (braucht pdfium)

| Aufruf | Beschreibung |
|--------|--------------|
| `pagetext handle seite` | Text einer Seite (1-basiert) |
| `search handle seite text ?args?` | Textsuche auf einer Seite |
| `bookmarks handle` | Lesezeichen/Outline |

### Formularfelder / JSON

| Aufruf | Backend | Rueckgabe |
|--------|---------|-----------|
| `formfields handle ?seite?` | pdfium, sonst qpdf | Liste `{typ name wert}` je Feld |
| `json handle ?args?` | qpdf | Rohes `qpdf --json` (args = weitere qpdf-Flags) |
| `jsonget handle pfad...` | qpdf + rl_json | Wert aus dem qpdf-JSON (rl_json-Pfadsyntax, inkl. `end`) |

`formfields`-Werte werden vom `u:`-Prefix (qpdf-JSON-String) befreit; Namen wie
`/Off` bleiben.

## Debug

Die `debug`-Ensemble hilft bei Diagnose:

| Aufruf | Zweck |
|--------|-------|
| `tclpdfreader::debug versions` | Geladene Backend-Versionen (`-` wenn abwesend) |
| `tclpdfreader::debug which handle` | Welches Backend jede Faehigkeit tatsaechlich bedient |
| `tclpdfreader::debug report handle` | Menschenlesbarer Voll-Report |
| `tclpdfreader::debug rawjson handle ?args?` | Rohes `qpdf --json` (Debug) |
| `tclpdfreader::debug tupdf handle was` | Rohe tupdf-Ausgabe (`summary`, `objects`, `trailer`, ...) |
| `tclpdfreader::debug trace ?on\|off?` | Live-Log der Backend-Wahl nach stderr (ohne Arg: Status) |

```tcl
tclpdfreader::debug trace on
tclpdfreader::pagecount $h        ;# stderr: [tclpdfreader] pagecount via qpdf
puts [tclpdfreader::debug report $h]
```

## Beispiel

```tcl
package require tclpdfreader
set h [tclpdfreader::open rechnung.pdf]

if {[dict get [tclpdfreader::capabilities $h] pagetext]} {
    puts [tclpdfreader::pagetext $h 1]
}
set zf [tclpdfreader::zugferd $h]
if {[dict get $zf detected]} {
    puts "Factur-X-Profil: [dict get $zf profile]"
}
tclpdfreader::close $h
```


## pdfium und Tk

`pdfiumtcl` rendert Seiten in **Tk-Photo-Images** und ist gegen Tk gelinkt --
`package require pdfiumtcl` initialisiert also Tk und liesse unter `tclsh` das
Standardfenster `.` erscheinen. tclpdfreader **versteckt dieses Fenster nur
dann**, wenn es Tk selbst ausgeloest hat (headless-Kontext); in einer echten
GUI (Tk war schon geladen) bleibt `.` unberuehrt.

Abschaltbar vor dem Laden:

```tcl
set ::tclpdfreader::withdrawTkRoot 0   ;# Fenster nicht verstecken
package require tclpdfreader
```

Die pdfium-Funktionen (Text, Suche, Formularfelder) funktionieren auch bei
verstecktem `.` -- Photo-Rendering braucht kein sichtbares Fenster.

## Grenzen

- Nur-lesend. Zum Schreiben/Fuellen `tclpdfwriter`, zum Erzeugen `pdf4tcl`.
- `tupdf` sieht keine komprimierten Objekt-/Xref-Streams (Zaehlungen ggf.
  Untergrenze -- `pagecountExact` pruefen).
- `formfields` via qpdf ist best-effort; `pdfium` wird bevorzugt.

## 0.2 -- Seitengeometrie, Text vorhanden, Verschluesselung

### `pagesize $h $page`

| Schluessel | Bedeutung |
|---|---|
| `width` `height` | **Punkt**, aus `/MediaBox` |
| `widthmm` `heightmm` | **Millimeter**, dieselbe Groesse |
| `rotate` | 0, 90, 180 oder 270 |
| `mediabox` `cropbox` | die Rechtecke selbst, leer wenn unbekannt |
| `source` | welches Backend geantwortet hat |

**Warum beide Einheiten:** in der Datei stehen Punkte, `pdfium` meldet
Millimeter. Keines wird stillschweigend umgerechnet -- wer einen Stempel
mit `pdf4tcl` baut, braucht Punkte; wer ihn ausmisst, meist Millimeter.

**Warum `rotate` dabeisteht:** ohne die Drehung steht ein Stempel quer,
sobald eine Seite `/Rotate 90` traegt -- und das faellt erst auf dem
Papier auf.

`/MediaBox`, `/CropBox` und `/Rotate` duerfen im Seitenbaum vererbt sein
(ISO 32000-1 7.7.3.4); qpdf loest das in seiner JSON-Ausgabe auf.

### `hastext $h $page`

1, wenn die Seite Text enthaelt. Beantwortet vorab, ob `search`
ueberhaupt etwas finden kann -- auf einem Scan sucht man sonst und haelt
das leere Ergebnis fuer einen Fehler. Braucht pdfium.

### `encryption $h`

`encrypted`, `method`, `printing`, `modify`, `extract`. Ueberlagern und
Bearbeiten scheitern an einer verschluesselten Datei ohne Passwort --
besser vorher fragen als hinterher eine qpdf-Meldung deuten.

### Weitere Auskuenfte in 0.2

`pagesizes $h` -- alle Masse auf einmal. Wer stempelt, braucht sie fuer
jede Seite; einzeln abgefragt bezahlt man den qpdf-Aufruf je Seite.

`annotations $h $page` -- was schon auf der Seite liegt: Kommentare,
Verweise, Formularfelder. **Wer stempelt, sollte wissen, was er
ueberklebt** -- sonst merkt man es erst, wenn jemand das PDF oeffnet und
der Verweis unter dem Stempel liegt. Braucht pdfium.

`links $h $page` -- Verweise mit Ziel und Rechteck.

`pagelabels $h` -- `/PageLabels` aus dem Katalog, als Liste von
`{index stil praefix start}`. Das ist **nicht** die Seitennummer: ein
Dokument kann roemisch beginnen, bei 1 neu anfangen oder einen Anhang mit
A-1 zaehlen. Wer eine Seitenzahl aufstempelt, will meist die
Beschriftung -- sonst steht auf Seite iv eine 4. Leere Liste heisst: die
Beschriftung ist die Nummer.

`attachments $h` -- die **Schluessel** eingebetteter Dateien. Zum
Entfernen braucht man sie, und sonst nennt sie nur
`qpdf --list-attachments` auf der Kommandozeile.

### Was hier NICHT geht, und warum

**Rechtecke zu Suchtreffern.** `search` liefert Zeichenindex und Laenge,
keine Koordinaten -- fuer "dieses Wort durchstreichen" braeuchte man sie.
pdfium hat sie (`FPDFText_GetRect`), aber `tclpdfium 0.6.1` reicht sie
nicht durch. Das ist eine Erweiterung der C-Schicht, nicht dieses
Pakets. Bis dahin muss die Stelle von Hand kommen.

### `layers $h`

Die Ebenen (Optional Content Groups) des Dokuments, je Ebene ein dict:

| Schluessel | Bedeutung |
|---|---|
| `id` | das Objekt, `"4 0 R"` |
| `name` | wie er im Betrachter steht |
| `visible` | 1, wenn beim Oeffnen sichtbar |
| `print` | 1 gedruckt, 0 nicht, **leer** wenn die Datei nichts sagt |

**Warum hier und nicht in tclpdfium:** pdfium befolgt Ebenen beim
Rendern, hat aber keine Schnittstelle, sie aufzuzaehlen oder zu
schalten. An einem Objekt meldet es nur, DASS es in einer Ebene liegt
(Markierung `OC`); die Parameter kommen als Typ 0 zurueck. Wer wissen
will, WELCHE Ebenen es gibt, muss in die Datei sehen -- und das kann
qpdf.

`print` **leer** heisst: die Datei sagt nichts, der Betrachter
entscheidet. Das ist etwas anderes als `1`, und wer es gleichsetzt,
verspricht mehr, als in der Datei steht.

```tcl
foreach l [tclpdfreader::layers $h] {
    puts "[dict get $l name]: sichtbar=[dict get $l visible]"
}
# Debug-Raster: sichtbar=0
# Vordruck (nur Ansicht): sichtbar=1   (print=0)
```

### `charboxes $h $page ?-range {start count}?`
### `pageobjects $h $page`

Durchgereicht an pdfium (ab 0.6.2): ein Rechteck je Zeichen, und woraus
die Seite gezeichnet ist. `search` nimmt ebenfalls `-rects 1` entgegen.
