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

Rueckgabewert 0 ohne Befund, 1 mit, 2 bei einem Fehler.

**Es entscheidet nicht, ob eine Abweichung schlimm ist.** Eine
Kopfzeile, die zuletzt gezeichnet wird, ist voellig in Ordnung. Es
zeigt, wo eine ist.

Braucht `pdfiumtcl`; `tclutils::tupagespec` nur fuer `-seiten 1-3,5`.
