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

## What is French-only, and why

The following are deliberately not translated. The reason is the same in every
case: **their audience speaks French**, and a second version would either drift
or, worse, carry a different meaning.

| Document | Why |
|---|---|
| User manual, training plan, accessibility statement | Written for the people who use the product and the people who train them |
| Privacy policy, terms of use | Legal texts. Two versions of a legal text are two texts that can disagree — a real risk, not a theoretical one |
| Test book (*cahier de recette*), user stories | Acceptance artefacts, read by the team and the examining board |
| The 39 full ADR records | Summarised in [adr-index.md](adr-index.md); the code, tables and diagrams inside are already language-neutral |
| Detailed operations runbook | Troubleshooting procedures for the team that operates the service; [operations.md](operations.md) covers what a reader needs to run and understand the stack |

## Conventions

Commit messages, pull request titles and Linear tickets are written **in
French**. That is a project convention, decided once and applied everywhere —
not an oversight in a bilingual repository.

Code identifiers, API fields and the OpenAPI specification are in **English**,
as is usual. The specification is in fact the one artefact that was always
English-only, which is why the bilingual gap ran in both directions before this
work.
