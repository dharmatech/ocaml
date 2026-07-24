# P2-000: Process-primitives exchange protocol

Status: accepted

Origin: caml9 review task

Materialized by: caml9 review task

Responds to: user workflow request

Date: 2026-07-24

Repository boundary: OCaml branch `plan9-4.14.3-000`, parent
`924786f313afbe7181596728b2f250110564d01c`

Canonical impact: none; the exchange procedure is accepted with the
clarifications in [P2-001](P2-001-ocaml-protocol-adoption.md), but no
normative API conclusion is promoted

Requested next action: follow the accepted procedure and materialize P2-002
only under a separately authorized documentation lease

## Purpose

The OCaml and caml9 tasks have reached a design depth at which relaying full
specifications through conversation is fragile. Long task messages are harder
to review, can render poorly when fenced Markdown is nested, and can disappear
from immediate context after compaction.

This protocol moves substantive design exchange into numbered, tracked files.
Conversation remains useful for notification, explicit ownership transfer,
short questions, and concise closeout reports.

The goals are:

- preserve the reasoning behind the Plan 9 process API;
- let each task author its own proposals and reviews directly;
- prevent simultaneous writes to the shared checkout;
- distinguish exploratory reasoning from the current normative contract;
- make accepted decisions discoverable without replaying a transcript; and
- ensure that a design discussion never silently grants operational authority.

## Authoring model

There may be multiple authors, but there is exactly one active stateful writer
at a time.

The OCaml task ordinarily owns:

- the authoritative OCaml worktree and index;
- canonical OCaml design documents;
- the compiler lab, its address, prefixes, and current-state;
- implementation, validation, commits, and pushes.

The caml9 task ordinarily remains read-only. During an explicitly transferred
review lease, it may directly author:

- the next numbered `P2-NNN-caml9-*.md` review; and
- the matching row in this directory's `README.md` index.

Unless the handoff says otherwise, a caml9 review lease does not include:

- rewriting the OCaml proposal under review;
- changing canonical OCaml design;
- changing either repository's current-state;
- editing implementation source;
- staging, committing, or pushing;
- using a VM, guest, endpoint, prefix, or mounted filesystem; or
- starting a build, probe, installation, checkpoint, or caml9 integration.

An OCaml response uses the next identifier and does not edit the caml9 review
it answers.

## Write-lease handoff

A task must not infer write ownership merely because the other task appears
idle. The current writer explicitly transfers the lease.

A handoff states:

- repository and branch;
- live HEAD and tree;
- worktree/index status;
- exact writable files or directory;
- whether staging, commit, and push are included;
- operational exclusions; and
- the task that receives the lease.

The receiver revalidates live Git before writing. If the checkout differs from
the handoff, it stops and reports the difference.

While the review lease is active, the prior writer pauses repository, index,
current-state, VM, guest, port, commit, and push activity. This is a global
stateful lease, even when the receiver's authorized mutation is only one
documentation file.

The receiver closes the lease in one of two explicit ways:

1. **Published close:** when publication was authorized, validate, commit, and
   push the review-only milestone, require a clean checkout, and hand ownership
   back at the published identity.
2. **Materialization close:** when publication was not authorized, leave only
   the precisely declared documentation changes, do not stage them, report
   every changed or untracked path, and hand that understood worktree to the
   receiving operator. The receiving operator then owns review, staging, and
   publication.

The published close is preferable for later exchanges because it creates the
cleanest cold-start boundary. The materialization close is appropriate for
bootstrapping this protocol or when the user requested file creation but not
publication.

## File naming and identity

Exchange files use:

```text
P2-NNN-short-title.md
```

`NNN` is the next unused three-digit identifier. The identifier records
conversation order, not importance.

Every document begins with:

- `Status`;
- `Origin`;
- `Materialized by`;
- `Responds to`;
- `Date`;
- `Repository boundary`;
- `Canonical impact`; and
- `Requested next action`.

`Origin` identifies the task responsible for the reasoning.
`Materialized by` identifies the task that wrote the file. Historical reviews
relayed through the user may therefore have different origin and materializer.
New reviews should normally be directly materialized by their originating task
during an exclusive review lease.

## Status values

Use one of:

- `proposed`: awaiting review;
- `answered`: a later document responds, but no final decision is claimed;
- `accepted`: its conclusions were selected for canonicalization;
- `partially accepted`: accepted and rejected portions are named;
- `superseded`: a later document replaces its operative proposal;
- `rejected`: retained for provenance but not selected; or
- `closed`: no further response is requested.

The index is the quick status view. A later status update must not rewrite the
historical reasoning inside a published exchange document.

## Recommended document structure

Use only the sections that add value:

- Purpose
- Evidence and inputs
- Proposal or findings
- Accepted points
- Required corrections
- Alternatives considered
- Open questions
- Requested next action
- Canonical impact

Link to local source, canonical design, evidence summaries, and primary Plan 9
documentation rather than copying large source or raw evidence blocks.

Do not store credentials, secrets, raw guest dumps, or machine-local evidence
archives here.

## Proposal and response sequence

A typical exchange is:

1. The OCaml task writes `P2-001-ocaml-...md`.
2. It publishes or explicitly hands off an understood documentation worktree.
3. The user tells the caml9 task to review `P2-001`.
4. The caml9 task writes `P2-002-caml9-review.md` during its review lease.
5. The caml9 task validates and hands ownership back.
6. The OCaml task writes `P2-003-ocaml-response.md`.
7. When the design settles, the OCaml task updates the canonical design and
   marks the exchange documents accepted or superseded in the index.

There is no requirement that odd and even numbers permanently belong to one
task. The `Origin` field, not parity, is authoritative.

## Canonicalization

Exploration history must not become a second competing specification.

When a decision is accepted, the active OCaml operator updates the applicable
canonical files, such as:

- `docs/design/plan9/01-native-api-requirements.md`;
- `docs/design/plan9/03-verification-and-recovery.md`;
- `docs/design/plan9/04-implementation-plan.md`; and
- `.agents/skills/ocaml-plan9-local/references/current-state.md`.

The index then records where the conclusion was canonicalized.

Portable architectural rules belong in `docs/design/plan9`. Machine-local VM,
address, prefix, process, listener, disk, and recovery observations belong in
the local skill's current-state or runbook. Caml9 integration status belongs
in caml9's own design and current-state records.

If an exploration document and canonical design disagree, the canonical
design governs once its accepting milestone is published. The discrepancy
must still be corrected or explicitly recorded; readers should never be
expected to guess which text is newer.

## Conversation convention

After this protocol is adopted, a normal substantive task reply should be
short:

```text
P2-005 is ready:
docs/design/plan9/exploration/process-primitives/P2-005-...md

Summary: ...
Requested next action: caml9 review.
Write lease: ...
```

The reviewing task reads the file directly from the shared checkout. The user
should not have to copy the document body between tasks.

Short clarification questions may remain in conversation. Any answer that
changes architecture, safety policy, operational procedure, or an accepted
gate must be recorded in a new exchange document or promoted directly to its
canonical home.

## Operational boundary

An exchange document may propose a gate, but it does not authorize it.

VM boot, Drawterm access, guest commands, source transfer, builds,
installation, prefixes, service processes, checkpoints, implementation,
staging, commits, and pushes remain governed by the repository instructions
and an explicit named authorization.

The stateful operator must continue to revalidate live Git and machine state.
Neither an exchange file nor a current-state observation replaces that
requirement.

## Initial requested response

The OCaml task should:

1. read this protocol and the directory index;
2. verify that the two files are the only new OCaml worktree paths from this
   materialization lease;
3. propose any correction in the next numbered OCaml document rather than
   rewriting P2-000;
4. if it accepts the protocol, record that disposition in its next numbered
   process-design document and update the index;
5. decide whether to materialize the already completed Phase 2 exchange as
   P2-001 and later files before publishing the canonical corrected design;
6. retain sole stateful ownership after accepting the materialization handoff;
   and
7. perform no operational or implementation work merely because this protocol
   exists.

## Canonical impact

None to the normative API. This exchange procedure is accepted with P2-001's
clarifications. The current canonical OCaml and caml9 design remains unchanged
until a separately reviewed documentation milestone promotes settled
conclusions.
