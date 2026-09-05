# tclpdfreader

A unified, **read-only** facade over three PDF backends, with graceful
degradation depending on what is installed. One API — each call picks the best
available backend and reports clearly when a capability needs a backend that is
missing.

**Version:** 0.1 · **Tcl:** 8.6 / 9.0 · **License:** BSD/MIT

## Backends

| Backend | How | Provides | Cost |
|---|---|---|---|
| `tupdf` | pure Tcl (`tclutils::tupdf`) | version, metadata, trailer, raw objects, ZUGFeRD | none; token-scan only (no compressed object/xref streams), page count is a lower bound |
| `pdfium` | native (`pdfiumtcl`) | page text, search, bookmarks, form fields, exact page count | needs `libpdfium` |
| `qpdf` | CLI (`qpdf`) | exact page count, full JSON structure, acroform fields, **layers** | needs the `qpdf` binary |

`layers` needs qpdf and nothing else will do: pdfium honours optional
content when rendering but has no interface to enumerate or switch it.
On a page object it only reports THAT the object sits in a layer -- the
parameters of the `OC` mark come back as type 0. Measured 2026-09-05.

None is required. With **no** backend beyond the pure-Tcl core you still get
version, metadata, structure and ZUGFeRD. Add `pdfium` for content (text/search/
forms), or `qpdf` for exact counts and structure.

## API

```tcl
package require tclpdfreader

set h [tclpdfreader::open file.pdf ?password?]

tclpdfreader::backends      $h            ;# which backends serve this doc
tclpdfreader::capabilities  $h            ;# dict: which calls are available
tclpdfreader::version       $h
tclpdfreader::metadata      $h            ;# dict (Title, Author, ...)
tclpdfreader::trailer       $h
tclpdfreader::object        $h id
tclpdfreader::zugferd       $h            ;# Factur-X / ZUGFeRD info
tclpdfreader::pagecount     $h            ;# best available count
tclpdfreader::pagecountExact $h           ;# 1 if exact, 0 if a lower bound
tclpdfreader::pagetext      $h page       ;# needs pdfium
tclpdfreader::search        $h page text  ;# needs pdfium
tclpdfreader::bookmarks     $h            ;# needs pdfium
tclpdfreader::formfields    $h ?page?     ;# pdfium, or best-effort via qpdf
tclpdfreader::json          $h ?args?     ;# raw qpdf --json (needs qpdf)
tclpdfreader::jsonget       $h path...    ;# value from qpdf JSON (rl_json)

tclpdfreader::close $h
```

Calls that need a missing backend raise a clear error, e.g.
`tclpdfreader: pagetext braucht Backend "pdfium"`. Use `capabilities` to test up
front.

- Pages are **1-based** in this API (page 1 = first page), consistent across
  backends; pdfium (0-based internally) is converted automatically. Out-of-range
  pages raise a clear error instead of a backend "cannot load page".

## Scope

Read-only. For **writing/transforming** (merge, fill forms, overlay, flatten)
see the companion `tclpdfwriter`. For **generating** new PDFs use `pdf4tcl` /
`pdf4tcllib`.

## Notes

- Structured qpdf JSON (form fields, `jsonget`) is parsed with **rl_json** when
  present (your ecosystem standard); it falls back to tcllib `json`, then to a
  light line scan. `jsonget $h path...` uses rl_json path syntax (incl. array
  indices); the tcllib fallback handles object/array paths too.

- `formfields` via qpdf is best-effort (returns `{fieldtype fullname value}`
  with PDF type codes like `Tx`/`Btn`); `pdfium` is preferred when present.
- `metadata` uses `tupdf`, else `pdfium`; `zugferd` uses `tupdf`, else a light
  `qpdf` attachment scan (Factur-X/ZUGFeRD/XRechnung/Order-X names).
- `pagecount` is exact via `pdfium` or `qpdf`; with only `tupdf` it can be a
  lower bound — check `pagecountExact`.
