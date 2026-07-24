# Process-primitives design exchange

Status: exploratory working record

## Purpose

This directory holds the numbered design exchange between the OCaml Plan 9
port task and the caml9 review task for native process primitives and their
first demanding consumer, caml9 CPU-017.

The exchange files preserve proposals, reviews, corrections, rejected
alternatives, and open questions that are too substantial to live safely only
in task transcripts. They are review history, not the normative API.

Settled conclusions must be promoted into the canonical documents one level
above:

- `01-native-api-requirements.md`;
- `03-verification-and-recovery.md`;
- `04-implementation-plan.md`; and
- the applicable tracked current-state record.

A cold-start reader should use those canonical documents for the current
contract and use this directory when the reasoning or provenance matters.

## Reading order

Read [P2-000](P2-000-exchange-protocol.md) first. It defines naming,
authorship, exclusive write leases, response structure, canonicalization, and
the boundary between a design document and operational authorization.

## Exchange index

| ID | Title | Origin | Responds to | Status | Canonicalized in |
| --- | --- | --- | --- | --- | --- |
| P2-000 | Process-primitives exchange protocol | caml9 review task | user workflow request | accepted | P2-001 clarifications; no API impact |
| P2-001 | OCaml protocol adoption and historical-exchange plan | OCaml Plan 9 port task | P2-000 | accepted | not applicable; no API impact |

## Current convention

- Files use `P2-NNN-short-title.md`, with monotonically increasing three-digit
  identifiers.
- Multiple tasks may author files, but only one task may hold the active
  stateful write lease at a time.
- A response never rewrites the document it reviews. It receives the next
  identifier.
- Once published, substantive corrections receive a new document. The index
  may later change only status and canonicalization metadata.
- Conversation is the control plane: normally it carries only the file path,
  a short summary, the requested next action, and an explicit write-lease
  handoff when one is needed.
- No exploration document by itself authorizes a VM, guest, port, build,
  installation, checkpoint, implementation, commit, or push.
