# Process-primitives design exchange

Status: closed; selected design canonicalized

## Purpose

This directory holds the numbered design exchange between the OCaml Plan 9
port task and the caml9 review task for native process primitives and their
first demanding consumer, caml9 CPU-017.

The exchange files preserve proposals, reviews, corrections, rejected
alternatives, and open questions that are too substantial to live safely only
in task transcripts. They are review history, not the normative API.

The selected P2-004 plus P2-006 conclusions are promoted into the canonical
documents one level above:

- [native API requirements](../../01-native-api-requirements.md);
- [verification and recovery](../../03-verification-and-recovery.md); and
- [implementation plan](../../04-implementation-plan.md).

A cold-start reader should use those canonical documents for the current
contract and use this directory when the reasoning or provenance matters.
No current-state change was part of this canonicalization.

## Reading order

Read [P2-000](P2-000-exchange-protocol.md) first. It defines naming,
authorship, exclusive write leases, response structure, canonicalization, and
the boundary between a design document and operational authorization.

## Exchange index

| ID | Title | Origin | Responds to | Status | Canonicalized in |
| --- | --- | --- | --- | --- | --- |
| P2-000 | Process-primitives exchange protocol | caml9 review task | user workflow request | accepted | P2-001 clarifications; no API impact |
| P2-001 | OCaml protocol adoption and historical-exchange plan | OCaml Plan 9 port task | P2-000 | accepted | not applicable; no API impact |
| P2-002 | Initial native process-primitives design | OCaml Plan 9 port task | plan9-phase-2-process-primitives-design-001 | answered | P2-003 review |
| P2-003 | Caml9 review of the initial process design | caml9 CPU-017 review task | P2-002 | answered | P2-004 response |
| P2-004 | Corrected native process-primitives design | OCaml Plan 9 port task | P2-003 | accepted | [01](../../01-native-api-requirements.md), [03](../../03-verification-and-recovery.md), and [04](../../04-implementation-plan.md), as clarified by P2-006 |
| P2-005 | Caml9 review of the corrected process design | caml9 CPU-017 review task | P2-004 | answered | P2-006 response |
| P2-006 | OCaml process-lifecycle clarification | OCaml Plan 9 port task | P2-005 | accepted | [01](../../01-native-api-requirements.md), [03](../../03-verification-and-recovery.md), and [04](../../04-implementation-plan.md) |
| P2-007 | Caml9 lifecycle acceptance | caml9 CPU-017 review task | P2-006 | closed | confirms the P2-004 plus P2-006 canonical package |

## Closed disposition

P2-004 as clarified by P2-006 is the selected design. P2-007 accepts that
package without further correction and closes the P2 exchange. A later
substantive disagreement receives a new numbered exploration document; it
does not rewrite this history or silently override the canonical documents.

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
