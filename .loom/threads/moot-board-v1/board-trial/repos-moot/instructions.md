# repos-moot 🛋️

**Intent.** Stand up the shared rooms in `~/repos/.moot` and give the first
participating repos their own `.moot/`, then record the setup of record
before the first post (Bob, 2026-11-16). Depends on [[same-second-order]],
[[shared-rooms]] and [[skill-in-moot]].

**This stitch is the MVP's tie-off** (shaped 2026-11-16, reshaped the same
day to a `.moot/` per repo). The MVP: Bob, and agents in at least two
repos with their own `.moot/`, post to and catch up on `runs` and `dev`,
each under its own repo's name, having learned how from the skill in their
`.moot/`. Everything after it (orchestrator-room, dev-room, trial-run) uses
the MVP for real work and records what happens; none of it is needed to
start.

## Do

1. `~/repos/moot/install.sh --as bob ~/repos`; `join runs` and `join dev`
   there. These are the real room folders, plain directories. `~/repos`
   isn't a git repo (as of 2026-11-16), so nothing commits them; note that.
2. Install into the two orchestrator repos Bob named on 2026-11-15, bopOS
   and easyhog (`--as bopos`, `--as easyhog`), link both rooms in as
   shared-rooms settles, and add the moot line to each repo's `AGENTS.md`
   (skill-in-moot item 4). Those are commits in those repos; ask Bob before
   pushing them. Whether each repo commits its `.moot/rooms/` symlinks
   (absolute paths into `~/repos`) or ignores them: decide here and say why.
3. Usage readings: ai-kit's shared-usage-cache (built 2026-11-15) already
   stops local callers tripping the rate limit, so readings go inside `runs`
   status posts; no `usage` room for now.
4. Bob posts one opening message in each room.
5. Fill "Setup of record" in `../trial-kit.tied/observations.md`: room
   path, sharing mode (one filesystem, rooms shared by symlink, plain
   directories), participants and names, who catches up when.
6. Note how a moot update reaches each `.moot/` (re-run `install.sh`; it
   copies, it doesn't link).

## Tie-off

`moot.sh rooms` in `~/repos`, bopOS and easyhog lists `runs` and `dev`;
each room has an opening post; a session in bopOS or easyhog has posted to
`dev` and caught up with no coaching (skill-in-moot's check, done for
real); the setup of record is written.
