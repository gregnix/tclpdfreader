# pdfdiff -- zwei PDF-Dateien vergleichen

```
tclsh pdfdiff.tcl alt.pdf neu.pdf ?-optionen?

  -text 0|1      Textvergleich je Seite (Vorgabe 1)
  -bild 0|1      Bildvergleich je Seite (Vorgabe 1, braucht Tk)
  -aufbau 0|1    Objektvergleich je Seite (Vorgabe 0)
  -dpi n         Aufloesung fuer den Bildvergleich (Vorgabe 72)
  -kontext n     Zeilen Umgebung im Textdiff (Vorgabe 2, -1 = alle)
  -seiten SPEC   nur diese Seiten, "1-3,5" oder eine Liste
```

Rueckgabewert: 0 wenn gleich, 1 wenn verschieden, 2 bei einem Fehler.

## Warum

Die Frage "hat sich wirklich nur das geaendert, was ich wollte" stellt
sich bei jeder Aenderung an einer PDF-Bibliothek. Am 05.09.2026 wurde sie
**dreimal an einem Tag** von Hand beantwortet -- Bildschirm gegen
Druckansicht, mit gegen ohne Formularschicht, vor gegen nach dem
Einbrennen. Jedes Mal derselbe Zehnzeiler, jedes Mal weggeworfen.

## Drei Ebenen, weil eine nicht reicht

| Ebene | zeigt |
|---|---|
| Byte | "identisch?" -- die schnellste Antwort, und meist die falsche: schon der Zeitstempel unterscheidet zwei Laeufe |
| Text | was ein Leser sieht: vertauschte, fehlende, veraenderte Woerter |
| Bild | was ein Drucker sieht: verschobene Linien, andere Schrift, eine verschwundene Ebene |
| Aufbau | woraus die Seite gezeichnet ist: ein Bild, das durch einen Pfad ersetzt wurde und gleich aussieht |

Gemessen an zwei Dateien, die sich nur im eingebrannten Formularwert
unterscheiden:

```
gefuellt gegen ohne -forms eingebrannt   -> Seite 1: bild:3
gefuellt gegen mit  -forms eingebrannt   -> +Spedition Muster
```

Der erste Fall zeigt, warum die Bildebene noetig ist: der Wert stand nie
im Seitentext, der Textvergleich haette "gleich" gemeldet.

## Was es NICHT tut

Entscheiden, ob ein Unterschied schlimm ist. Es zeigt, wo einer ist.

## Abhaengigkeiten, beim Namen genannt

Wer nicht die ganze tclutils-Sammlung will, braucht genau diese Dateien --
nachgemessen, indem sie einzeln in ein leeres Verzeichnis gelegt wurden:

```
tclutils/common-0.1.tm      Grundlage; 97 von 136 Modulen nennen sie
tclutils/tudiff-0.1.tm      Textebene (LCS)
tclutils/tucmp-0.1.tm       Byteebene, mit Fundstelle
tclutils/tudhash-0.1.tm     Bildebene (laeuft auch ohne common)
tclutils/tupagespec-0.1.tm  nur fuer "-seiten 1-3,5" (ohne common)
```

Dazu **pdfiumtcl**. Ab 0.6.2 wird mit `-forms 1` gerendert, damit
gefuellte Formularfelder im Bildvergleich sichtbar sind; mit einer
aelteren Fassung sagt das Skript beim Start, dass sie fehlen, und macht
ohne weiter -- statt auf halber Strecke mit "unknown option -forms"
stehenzubleiben.

## Zwei Entscheidungen im Code

**Vor dem Hashen verkleinern.** Eine A4-Seite bei 72 dpi hat eine halbe
Million Punkte; die Liste fuer `fromRGB` haette anderthalb Millionen
Eintraege gehabt. `copy -subsample` auf rund hundert Punkte Breite
erledigt das in C-Geschwindigkeit -- und der Hash faltet ohnehin auf
9 x 8 zusammen.

**Beim Aufbau die ANZAHL je Art vergleichen, nicht die Rechtecke.** Die
aendern sich schon durch eine andere Rundung, und dann meldet jede Seite
einen Unterschied.
