# public-split 🚪

**Goal.** Publish moot in the `split` shape Bob chose on 2026-11-16: a
private `moot-dev` holds development, the dotdirs, `AGENTS.md` and the full
history; a public `moot` receives one release commit per tagged version.
Standard described in `~/repos/ai-kit/skills/repo-setup/reference/public-release.md`
(bopOS is the worked example). Not queued.

## As of 2026-11-16

- `zealtv/moot` exists and is private (`gh repo view`). Nothing has been
  released, so there are no existing public links to keep.
- A grep of `README.md`, `moot.sh`, `install.sh`, `skills/moot.md` and
  `test/run.sh` for `lore:`/`loom:`/`glean:` ids, `.lore/items`, `~/repos`
  and `HQ` found nothing. Public files look clean; keep them that way.
- No sibling primitive repo had recorded a publishing shape yet, so moot may
  set the pattern for loom, glean, lore, nestlings and groundhog.

## To settle with Bob

1. Names: Bob, 2026-11-16: "I want to call the private repo moot-dev."
   Likely the current private `zealtv/moot` gets renamed to `moot-dev`
   (keeping history) and a fresh public `zealtv/moot` gets created; confirm
   that, then update this checkout's `origin` and add `public` with its push
   URL disabled.
   Bob, same day: "ideally rename the folder on this machine at the same
   time", so `~/repos/moot` becomes `~/repos/moot-dev` in the same step.
   A grep on 2026-11-16 found `~/repos/moot` cited only in this loom
   (`trial-kit.tied/setup.md`, `repos-moot/instructions.md`) and in
   tengu-the-gremlin's archived transcript and nest receipts, which are
   history and stay as written. Re-grep `~/repos`, `~/.claude` and ai-kit
   before renaming; Claude Code's per-project session history is keyed by
   the old path and won't follow. Do it from a session started outside the
   folder.
2. What goes public: source at each release minus the private paths
   (dotdirs, `AGENTS.md`/`CLAUDE.md`, `.claude/`, `inbox`).
3. History: one commit per release, starting fresh.
4. Release mechanics: an allowlist manifest and an export test as in
   bopOS, or the shared release tool if ai-kit's `generalise-release-tool`
   lands first.
5. Licence, public README wording, whether issues and PRs open.

Don't create, rename or change the visibility of any GitHub repo without Bob.

## Tie-off

The first tagged release is on the public repo, produced by the release
tool, and the public tree passes its self-contained test.
