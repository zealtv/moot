# readme-to-contract 📜

**Intent.** Cut `README.md` back to the contract, moving the history and
argument into a lore record. From a review: Fable, read-only, 2026-11-16, at moot `e02923a`
(finding 8); Bob asked for this stitch the same day. Not queued.

## As the review found it

- 541 lines, against 387 for nestlings and 189 for glean.
- History and self-argument: "not the exception it used to be" (~line 47),
  "Containment did not cost this… If you watched the room move" (~257-261),
  internal function names (~356).
- `--json` on `init`/`join` exists (`moot.sh:53-54`) but the README's
  usage block (~400-401) omits it. The review judged that, and
  `.moot/room` plus `$MOOT_ROOM`, marginal; decide keep, document or drop.
- Unlike its siblings (e.g. `nestlings/.nest/nestling.sh`), moot keeps its
  script at the repo root and has no `.moot/` of its own. Decide whether to
  match.

## Keep (the review's "protect these")

Filename as the whole header; immutability so union is the merge; the cursor
outside the room; reader-side `@`; `--deliver <dir>`; the atomic
`link(2)` claim; etiquette in `skills/moot.md`; "a moot needs no tool".

Do it after [[shared-rooms]], [[same-second-order]] and any
[[extract-git-transport]] decision, so the README gets rewritten once. Keep
public text free of lore/loom/glean ids (`loom:public-split`).

## Tie-off

The README states the format and the tool; the reasoning that came out of it
lives in a dated lore record.

## Added 2026-11-16 (second Fable review; Bob approved)

Fold in these removals: `.moot/room`, `$MOOT_ROOM` and `init --room`
(every MVP participant holds two rooms, so the sole-room default never
fires; document `--room`), and `--json` on `init`/`join`.
