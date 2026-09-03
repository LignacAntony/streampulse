# StreamPulse — technical documentation (English)

> 🇫🇷 **Version française : [docs/README.md](../README.md)** — the French
> documentation is the reference and is more complete. This section covers the
> declared bilingual scope; the scope itself, and the reasoning behind where it
> stops, are stated in [docs/README.md](../README.md#périmètre-bilingue).

---

## Start here

| Document | What it answers |
|---|---|
| [../../README.en.md](../../README.en.md) | What the project is, how to run it, which environment variables it needs |
| [architecture.md](architecture.md) | How the pieces fit together, and why these technologies |
| [operations.md](operations.md) | How to run, observe and deploy the stack |
| [security.md](security.md) | Who can reach what, how secrets are protected, what is exposed |
| [adr-index.md](adr-index.md) | Every architecture decision, summarised |

## Also in English

| Document | What it answers |
|---|---|
| [user-stories.md](user-stories.md) | The product's user stories, by epic, with their original acceptance criteria |
| [database.md](database.md) | The database schema: tables, relationships, constraints |
| [diagrams.md](diagrams.md) | UML views of the system, each backed by a textual equivalent |
| [training-plan.md](training-plan.md) | How each audience — including people with disabilities — is brought to autonomy on the product |
| [accessibility.md](accessibility.md) | The documentation's declared accessibility level (WCAG 2.1 AA), glossary, known gaps |
| [user-manual.md](user-manual.md) | The listener, broadcaster and administrator walkthroughs, with no command line |

## What is French-only, and why

The following are deliberately not translated. The reason is the same in every
case: **their audience speaks French**, and a second version would either drift
or, worse, carry a different meaning.

| Document | Why |
|---|---|
| Privacy policy, terms of use | Legal texts. Two versions of a legal text are two texts that can disagree — a real risk, not a theoretical one |
| Test book (*cahier de recette*) | An acceptance artefact, read by the team and the examining board |
| The full ADR records | Summarised in [adr-index.md](adr-index.md); the code, tables and diagrams inside are already language-neutral |
| Detailed operations runbook | Troubleshooting procedures for the team that operates the service; [operations.md](operations.md) covers what a reader needs to run and understand the stack |

## Conventions

Commit messages, pull request titles and Linear tickets are written **in
French**. That is a project convention, decided once and applied everywhere —
not an oversight in a bilingual repository.

Code identifiers, API fields and the OpenAPI specification are in **English**,
as is usual. The specification is in fact the one artefact that was always
English-only, which is why the bilingual gap ran in both directions before this
work.
