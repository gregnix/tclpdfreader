# tools/

Skripte, die man **aufruft**, nicht einbindet.

Der Unterschied zu `lib/` ist eine Zusage: `lib/tclpdfreader-0.2.tm`
kommt mit dem aus, was zur Laufzeit gefunden wird, und laeuft auch, wenn
pdfium oder qpdf fehlen -- dann meldet es eben weniger. Ein Werkzeug in
`tools/` darf **mehr voraussetzen**, weil es niemand versehentlich
mitzieht: wer es nicht startet, zahlt nichts dafuer.

Dasselbe Muster steht bei pdf4tcl in `tools/pdfcheck-native.tcl`.

## pdfdiff.tcl

Zwei PDF-Dateien vergleichen, auf drei Ebenen -- Byte, Text, Bild, dazu
wahlweise der Objektaufbau.

```
tclsh tools/pdfdiff.tcl alt.pdf neu.pdf ?-optionen?
```

Rueckgabewert 0 gleich, 1 verschieden, 2 Fehler -- damit laesst es sich
in einem Makefile benutzen.

**Braucht** `pdfiumtcl` (ab 0.6.2 werden Formularfelder mitgerendert)
und aus `tclutils` die Module `common`, `tudiff`, `tucmp`, `tudhash`;
`tupagespec` zusaetzlich fuer `-seiten 1-3,5`.

Einzelheiten und die Begruendung der drei Ebenen: `LIESMICH-pdfdiff.md`.

## readorder.tcl

Liest das Dokument so, wie es ausgezeichnet ist?

```
tclsh tools/readorder.tcl datei.pdf ?-seiten SPEC? ?-text 0|1?
```

Ein Vorleseprogramm folgt dem **Strukturbaum**, ein Drucker dem
**Inhaltsstrom**. Beide koennen auseinandergehen, ohne dass man es dem
fertigen Blatt ansieht: eine zweispaltige Seite, spaltenweise
gezeichnet und zeilenweise ausgezeichnet, liest sich vorgelesen wie
Kraut und Rueben und sieht gedruckt tadellos aus.

`structure` gab die eine Reihenfolge, `mctext` die andere -- beide
Haelften gab es laenger, verglichen hat sie nichts.

Gemeldet wird:

| Befund | heisst |
|---|---|
| Reihenfolge weicht ab | Baum und Strom nennen dieselben Marken in anderer Folge; die erste Abweichung wird genannt |
| OHNE MARKE | gezeichneter Text in keinem Strukturelement -- fuer ein Vorleseprogramm nicht vorhanden |
| OHNE TEXT | ausgezeichnet, aber nichts gezeichnet |
| NICHT AUSGEZEICHNET | die Seite hat gar keinen Baum |

**Drei Dinge, die KEIN Befund sind** -- alle drei gemessen an pdf4tcls
`demo-tagged.pdf`, die zuerst faelschlich angemeckert wurde:

* **Artefakte.** Kopfzeile und Seitenzahl tragen absichtlich keine MCID
  (ISO 32000-1 14.8.2.2). PDFium meldet fuer sie dieselbe `-1` wie fuer
  unausgezeichneten Text; unterschieden werden sie ueber
  `pageobjects -marks 1` und den Markennamen `Artifact` -- den gibt es
  seit pdfiumtcl 0.6.2.
* **Bildhafte Elemente.** Ein `Figure` enthaelt ein Bild und hat
  naturgemaess keinen Text; `mctext` sieht nur Text.
* **Elemente ueber den Seitenumbruch.** Ein Absatz kann EIN
  Strukturelement mit Marken auf ZWEI Seiten sein -- in der Demo steht
  auf Seite 2 ein `P` mit `mcids {26 0}`, und 26 liegt auf Seite 1. Nur
  ein Element, von dem auf dieser Seite GAR NICHTS gezeichnet wurde,
  zaehlt.

Eine Doppelung ist ebenfalls keine: ein Absatz wird oft in mehreren
Textstuecken gezeichnet. Verglichen wird die Reihenfolge des **ersten
Auftretens**.

Rueckgabewert 0 ohne Befund, 1 mit, 2 bei einem Fehler.

**Es entscheidet nicht, ob eine Abweichung schlimm ist.** Eine
Kopfzeile, die zuletzt gezeichnet wird, ist voellig in Ordnung. Es
zeigt, wo eine ist.

Braucht `pdfiumtcl`; `tclutils::tupagespec` nur fuer `-seiten 1-3,5`.

## overlaps.tcl

Was liegt auf was?

```
tclsh tools/overlaps.tcl datei.pdf ?-seiten SPEC? ?-anteil 0.3? ?-text 0|1?
```

Ein Eintrag, der auf einer vorgedruckten Linie sitzt, ist am Bildschirm
zu erkennen und auf dem Papier nicht. Ein Bild ueber Text macht ihn
unsichtbar -- extrahieren laesst er sich trotzdem, also merkt es weder
das Auge noch `pdftotext`. Bei cmrform wurde das von Hand gerechnet.

Gemeldet werden **Text/Bild** und **Text/Linie**. Zwei Textstuecke
nebeneinander ueberlappen staendig -- das ist Satz und kein Befund.

**KANDIDATEN, keine Fehler.** Ein Rechteck ist eine Huelle, keine Form:
eine Linie kann sauber zwischen zwei Zeilen liegen und sich mit deren
Rechtecken trotzdem ueberschneiden. Das Werkzeug sagt, wo man hinsehen
soll.

### Zwei Arten Laerm, die abgestellt sind

Beide an echten Dateien gemessen, nicht ausgedacht:

**Hintergruende.** Ein Rahmen oder eine Flaeche ueber die ganze Seite
ueberlappt mit JEDEM Textstueck zu 100 %. Eine schlichte Datei ergab
zehn Kandidaten von zwoelf Objekten, alle auf einen Rahmen
zurueckgehend, der 90 % der Seite einnimmt. Pfade ueber 60 % der
Seitenflaeche werden ausgelassen und die Zahl genannt.

**Rahmen um Text.** Liegt der Text GANZ im Pfad, ist der Pfad ein Kasten
um ihn herum -- eine Umrandung, eine farbige Flaeche hinter einer
Ueberschrift. Interessant ist das KREUZEN. Beim Bild ist es umgekehrt:
dort heisst "ganz darin", dass der Text verdeckt ist, und genau das soll
gemeldet werden.

Nach beiden Regeln melden `sample.pdf` und `demo-forms.pdf` nichts, eine
eigens gebaute Datei mit Text auf einer Linie und einem Bild ueber Text
beides.

Rueckgabewert 0 ohne Kandidaten, 1 mit, 2 bei einem Fehler.

Braucht `pdfiumtcl`; `tclutils::tupagespec` nur fuer `-seiten 1-3,5`.
