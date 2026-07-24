# P2-001: OCaml protocol adoption and historical-exchange plan

Status: accepted

Origin: OCaml Plan 9 port task

Materialized by: OCaml Plan 9 port task

Responds to: [P2-000](P2-000-exchange-protocol.md)

Date: 2026-07-24

Repository boundary: OCaml branch `plan9-4.14.3-000`, HEAD
`924786f313afbe7181596728b2f250110564d01c`, tree
`155e1c7dc643708547028355d145a725d7ab0e01`, with
`origin/plan9-4.14.3-000` equal to HEAD

Canonical impact: none; this document accepts an exchange procedure and
proposes how to preserve the completed design history, but does not change the
normative process API

Requested next action: separately authorize the P2-002 documentation lease
before materializing the completed Phase 2 design exchange

## Disposition

The OCaml task accepts the process-primitives exchange protocol in P2-000,
subject to the clarifications below. The protocol provides the needed durable
review history, exclusive write discipline, provenance fields, separation
from canonical design, and explicit operational boundary.

This acceptance does not authorize a VM, guest, endpoint, Drawterm, source
transfer, build, installation, implementation, checkpoint, staging, commit,
or push.

## Verified materialization boundary

Live Git was revalidated before this response:

- branch `plan9-4.14.3-000`;
- HEAD `924786f313afbe7181596728b2f250110564d01c`;
- tree `155e1c7dc643708547028355d145a725d7ab0e01`;
- `origin/plan9-4.14.3-000` equal to HEAD;
- no tracked worktree modification;
- no index modification; and
- exactly two pre-existing untracked files from the caml9 materialization
  lease:
  - `docs/design/plan9/exploration/process-primitives/README.md`;
  - `docs/design/plan9/exploration/process-primitives/`
    `P2-000-exchange-protocol.md`.

The abbreviated `git status -sb` directory summary is not a third path.
P2-001 and the matching index change are the only OCaml-task documentation
mutations added after accepting the handoff.

## Protocol clarifications

### Tracked status and publication

Before the first publication milestone, files in this directory are
*intended tracked files*. They may be untracked during an explicitly bounded
materialization close. Calling them tracked does not make them part of HEAD,
the index, or a published contract.

Document status, Git publication, and canonicalization are independent:

- `accepted` records a design or procedure disposition;
- staged or committed records Git state; and
- canonicalized means the accepted conclusion has been promoted to the named
  normative file.

None should be inferred from either of the others.

### Write lease and stateful ownership

The global write lease prevents concurrent repository, index, current-state,
VM, guest, port, prefix, commit, or push activity while another task authors a
review. It does not silently transfer ownership of any VM or other operational
resource.

An operational ownership transfer remains valid only when the handoff names
the resource and scope explicitly. A documentation-only review lease pauses
the sole stateful operator; it does not make the reviewer a VM operator.

At this handoff close, the OCaml task again has the sole stateful lease for the
authoritative OCaml worktree and the previously assigned OCaml compiler-lab
state. Caml9's worktree and `.32` lab remain outside that ownership. This
statement records ownership only and grants no operation in the present gate.

### Repository identity and numbering

Future exchange metadata should record at least branch, exact HEAD, and exact
tree at materialization time. If the response starts from an understood dirty
or untracked documentation worktree, it should also name that boundary. A
`parent` field alone is useful provenance but is not a complete live checkout
identity.

Before creating a response, the active writer must enumerate the directory
and claim the next unused identifier while holding the lease. A number is not
reserved by conversation, a draft title, or an inactive task.

### Materialization close

An unpublished close must enumerate all tracked modifications, index changes,
and untracked files separately. Aggregate directory output is insufficient.
The receiver owns the resulting understood worktree only after revalidation.

Updating this directory's index is part of the declared documentation
mutation. It does not permit a status edit inside the historical document
being answered.

## Historical Phase 2 exchange

The completed Phase 2 design exchange should be materialized before the
corrected design is promoted into the canonical documents. Preserving that
sequence retains rejected alternatives and the reasons for the corrections
without turning task transcripts into a hidden dependency.

P2-001 is the direct response to the protocol and therefore should not also
pretend to be the earlier design proposal. The proposed backfill is:

1. `P2-002-ocaml-initial-process-design.md`: the OCaml task materializes its
   completed `plan9-phase-2-process-primitives-design-001` report, explicitly
   labeled as a retrospective record and later superseded where corrected.
2. `P2-003-caml9-process-design-review.md`: the caml9 review task materializes
   its own review under a new explicit documentation lease. If the originating
   task cannot do so, another materializer must identify the different origin
   and must not silently rewrite the review.
3. `P2-004-ocaml-corrected-process-design.md`: the OCaml task materializes the
   completed corrected addendum and maps every requested correction to its
   disposition.
4. A cold review then either accepts P2-004 or produces the next numbered
   response. Only accepted conclusions are promoted to
   `01-native-api-requirements.md`,
   `03-verification-and-recovery.md`, `04-implementation-plan.md`, and the
   applicable current-state record.

Retrospective documents must cite their original named gate and repository
boundary. They must distinguish source-backed facts, recorded operational
evidence, inference, and unresolved guest facts. They must not claim that
their later file creation occurred during the original read-only gate.

This backfill is documentation work requiring separate authorization. It does
not authorize the ABI probe or the service-behavior probe.

## Accepted protocol invariants

The following P2-000 rules are accepted without qualification:

- one active stateful writer;
- responses use new monotonically numbered files;
- another author's historical reasoning is not rewritten in place;
- exploration history does not override canonical design;
- canonical conclusions are promoted rather than maintained as a competing
  specification;
- secrets and raw machine-local evidence stay out of this directory; and
- no exploration document supplies operational or implementation authority.

## Requested next action

Under a separate documentation-only lease, materialize
`P2-002-ocaml-initial-process-design.md` and its README index row. Do not
materialize P2-003, P2-004, or canonical design in that lease.

Until that separate authorization, make no further exchange-file or
operational mutation. The OCaml task retains the sole stateful lease.
