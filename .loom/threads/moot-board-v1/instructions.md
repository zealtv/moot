# moot-board-v1 📣

**Goal.** Ship the smallest useful moot as a file-based message board where
people, gremlins, and other agents can post, read, and use messages for
coordination and announcements.

This is the board-first release, not group chat. Announcement traffic is
read-mostly, so v1 deliberately avoids solving live turn-taking, silence,
flood control, addressing semantics, invitations, trust between participants,
or sync-latency UX.

**Settled shape.** Moot is a sibling family primitive with its own repository.
A moot is a directory containing one Markdown file per post, ordered by a
sortable filename such as `<timestamp>-<sender>-<nonce>.md`; sender attribution
lives in the post header. Distinct immutable files should merge cleanly through
ordinary filesystem sync. Any combined transcript or browser view is derived
and disposable.

The first command-line surface should stay tiny:

- initialise a moot directory;
- publish a post with sender and timestamp metadata;
- list or read posts in deterministic order;
- render the board for a human without requiring a gremlin.

Reuse the Nest item-directory convention when a post needs attachments. Keep
the primitive useful by itself; gremlin integration and external platform
bridges are consumers, not part of the board protocol.

**First proof.** Run one shared moot with two fanta gremlins and one human.
Use it for real coordination and announcements, then record what the trial
reveals before expanding the protocol.

**Tie-off.** The file convention and command surface are documented; the basic
implementation is tested; a bare human-readable board works; and the small
three-participant trial succeeds end to end.

**Deferred.** Full multi-party chat remains a later design problem and should
be opened as new work only after the board trial supplies evidence. It will
need to address flooding, silence, addressing, membership, trust, ordering,
and sender-name collisions.

**Provenance.** Narrowed and moved from HQ Loom stitch `gremlin--moot` on
2026-08-29. The earlier design record remains in HQ Lore at
`.lore/items/2026-07-02-gremlin-shared-room/content/`, with later context in
`.lore/items/2026-07-05-gremlin-feature-braindump/` and
`.lore/items/2026-08-28-gremlin-sibling-primitive-braindump/`.
