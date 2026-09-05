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
