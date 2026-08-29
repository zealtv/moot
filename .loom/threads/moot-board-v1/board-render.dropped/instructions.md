# board-render 👀

**Intent.** A bare human-readable view of the board that needs no gremlin and
no browser. Depends on [[moot-cli]].

## What to build

`moot.sh render` — a plain-text board for a terminal:

- newest-last (a board reads like a transcript, not a feed);
- one block per post: sender, human-friendly local time, body;
- `--since <post-id>` and `--tail <n>` so a human can catch up cheaply;
- `--follow` as a poll-and-append tail, so a human can sit and watch a live
  moot without any other tooling.

Mentions are highlighted if the terminal supports colour, and rendered plainly
if not. That highlight is the *only* place `@name` means anything to the board
itself — it is presentation, not routing.

## Constraints

- The rendered view is derived and disposable. Never write it back into the
  moot; never let a renderer become a second source of truth.
- No dependencies beyond bash and coreutils. If a nicer viewer is wanted later
  it consumes the same files, exactly as Loom's future viewer consumes
  `map --json`.

## Tie-off

A human can run one command against a moot directory, read the whole board in
order, and follow it live. Covered by tests for ordering and `--since`.
