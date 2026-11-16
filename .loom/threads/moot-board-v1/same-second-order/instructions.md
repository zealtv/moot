# same-second-order ⏱️

**Intent.** Make two posts from one sender in the same second sort, render
and catch up in the order they were written. Found by a review: Fable, read-only, 2026-11-16, at moot `e02923a`
(finding 3); Bob queued the fix the same day.

## What the review measured

- `20260829-163412-tengu-2.md` sorts *before* `…-tengu.md` (`-` < `.`),
  so `ls` and `read` show the later post first. README lines 105-111
  promise "later than the one without it".
- `read` labelled the second post's sender `tengu-2` (`moot.sh:571`).
  Names with hyphens, such as the planned `bopos-v3.9`, make
  `<sender>-<N>` ambiguous anyway.
- `catchup` reported the `-2` post on every run (`scanned:1,
  delivered:1`), the cursor stuck at `…-tengu`.

Reproduce these in a test before changing anything.

## Suggested fix (the reviewer's)

On a clash, wait one second and re-stamp, rather than take a suffix (the
claim loop near `moot.sh:510`). That drops the `-N` grammar from the
format entirely: the filename stays `<date>-<time>-<sender>.md`. Decide
what `read`/`catchup` do with any `-N` posts already on disk (likely: read
them as before, never write new ones), and update the README's
"Same-second collisions" section.

It matters more once [[shared-rooms]] puts many posters in one room, so it sits
ahead of [[repos-moot]].

## Tie-off

Tests show same-second posts in order under `ls`, `read` and `catchup`,
with the right sender, and the README describes the new rule.

## Added 2026-11-16 (from the second Fable review (read-only, at `c193580`, 2026-11-16))

Use a hyphenated sender such as `bopOS-v3.9` in the tests: under the old
grammar `<sender>-<N>` can't be told apart from a hyphenated name.
