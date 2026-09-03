# Documentation accessibility

> 🇫🇷 **Version française : [docs/accessibilite.md](../accessibilite.md)** —
> the French version is the reference.

This document declares the accessibility level targeted by StreamPulse's **documentation**, the
rules that ensure it, and the gaps that remain.

> **Scope.** It covers the documents in `docs/` and the `README`. It does **not** cover the
> accessibility of the Flutter application itself. Both matter, separately, and conflating the
> two would amount to declaring something compliant when it is not.
>
> The application side has been addressed since STR-244:
> [ADR 043](../adr/043-accessibilite-de-l-application-et-adaptation-aux-largeurs.md) describes
> what is done — semantic labels, WCAG checkers in CI, adaptation to screen widths — **and what
> is not**: no verification with an actual screen reader, for lack of a device. No compliance is
> declared there.

---

## 1. Targeted and declared level

**WCAG 2.1 level AA**, applied to the documentary content.

RGAA (the French public-sector accessibility framework) was not chosen as the reference standard
for this declaration: it is designed for public online services, and a good share of its
criteria cover interface components — forms, navigation, time-based media — that Markdown
documentation does not contain. WCAG 2.1 AA covers what genuinely applies here, without claiming
compliance on criteria that are beside the point.

## 2. What this requires, and how it is upheld

| Rule | Criterion | How it is applied |
|---|---|---|
| Every image carries a textual alternative | 1.1.1 | Every screenshot in the manual comes with a description in the body text, never only in the `alt` attribute |
| Every diagram has a textual equivalent | 1.1.1 | Mermaid diagrams are followed by a "Textual equivalent" paragraph describing the same content |
| Information does not rely on colour alone | 1.4.1 | Status tables use **words** ("yes", "no", "owner"), not colour-coded dots alone |
| Structure is carried by markup | 1.3.1 | Headings are hierarchical with no level skipped, tables have a header row, lists are real lists |
| Reading does not depend on spatial formatting | 1.3.2 | No information is carried by space-based alignment or character-drawn art |
| Links are explicit out of context | 2.4.4 | No "click here": the label names the target |
| The language is declared | 3.1.1 | Each document is written in one consistent language, French or English; foreign terms it keeps are defined in the glossary |

## 3. Concrete consequences for writing

**A document must remain complete once its images are removed.** That is the test we apply: if
removing the screenshots makes a step incomprehensible, the text is insufficient, not the missing
illustration. The [user manual](user-manual.md) is written in that order — the text first, the
screenshots in support.

**Diagrams are in Mermaid, not drawn with characters.** A Mermaid diagram is structured text: a
screen reader reads back its nodes and links. A diagram drawn with box-drawing characters is read
out character by character — "dash dash dash vertical bar" — which is actively painful, not
merely unhelpful. See [diagrams.md](diagrams.md).

**Tables stay readable in a linear pass.** A screen reader goes through a table cell by cell; we
therefore keep few columns and headers that stand on their own.

## 4. Printable version

The documents are Markdown: they print from any viewer, or convert to PDF with the heading
structure preserved — a condition for the PDF to stay navigable by assistive technology.

No layout relies on spaces or tabs, which guarantees that conversion does not destroy the
meaning.

## 5. Glossary

The documentation stays dense. The terms that cannot be avoided:

| Term | What it is |
|---|---|
| **Stream** (or *live*) | A real-time audio broadcast, created by a broadcaster |
| **Stream key** | The secret that authorises sending audio to a given stream |
| **Ingest** | The act of sending audio to the server, from the broadcaster's side |
| **HLS** | The broadcasting technique used: audio is split into small successive files that the player fetches one after another |
| **Segment** | One of those small files, about ten seconds of audio |
| **Manifest** (`.m3u8`) | The list of available segments, which the player re-fetches regularly |
| **Playlist** | A personal list of tracks — unrelated to the manifest above, despite the shared word "list" |
| **Track** | An audio file uploaded by a user |
| **Queue** | What the player will play, in order, once a playlist has started |
| **Token** | The proof of identity the application presents to the server on every request |
| **Favourite** | A stream set aside to find again from the home screen |
| **Role** | An account's level of rights: listener, broadcaster, administrator |
| **ADR** | *Architecture Decision Record* — a note that explains **why** a technical choice was made |
| **Audit log** | The record of administration actions: who did what, when |

## 6. Known gaps

1. **The French `architecture.md` still contains diagrams drawn with box-drawing characters** —
   79 lines are affected. This is the main shortfall of this declaration, and it is **active**: a
   screen reader reads them out character by character. The English
   [architecture.md](architecture.md) already uses Mermaid instead.

   Immediate mitigation: the same content also exists in Mermaid, with textual equivalents, in
   [diagrams.md](diagrams.md). A reader using assistive technology should be directed to that
   document.

   Rewriting the French file is deliberately left out of this change: it is being rewritten
   elsewhere, and two concurrent rewrites of the same file would not merge cleanly. To be
   addressed as soon as that rewrite lands.

2. **Only one screenshot has been produced** — the login screen. The manual is written to be
   complete without images — that is the rule in § 3 — but their scarcity denies people who rely
   on visual landmarks an anchor point. The missing screenshots require navigating the
   application, and therefore sending it taps, which the available tooling did not allow at the
   time of writing.

3. **Part of the documentation still exists only in French.** The bilingual scope is declared
   separately in [docs/README.md § Bilingual scope](../README.md#périmètre-bilingue), and is not
   covered by this declaration.

4. **No audit by a person who actually uses assistive technology** has been carried out. The
   rules above are applied in good faith; they have not been tested against real use. That is
   the honest limit of this declaration.

5. **No audio version of the documentation.** The criterion asks for documentation that is
   "readable, audible": here, the audible part rests on the screen reader's speech synthesis, not
   on a recording. That is a choice — a recording would drift from the text at the first update
   — but it is one, and it is declared as such.

## 7. Reporting an accessibility issue

Open an issue on the project's repository describing the document in question, the assistive
technology used and what is blocking. Accessibility issues are handled with the same priority as
a functional defect.
