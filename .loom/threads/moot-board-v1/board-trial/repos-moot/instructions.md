# repos-moot 🛋️

**Intent.** Stand up `~/repos/.moot` as the host moot for every repo under
`~/repos` (Bob, 2026-11-16), and record the setup of record before the first
post. Depends on [[same-second-order]], [[host-moot]] and [[host-skill]].

**This stitch is the MVP's tie-off** (shaped 2026-11-16). The MVP: Bob and
agent sessions in different repos can post to and catch up on `runs` and
`dev` in `~/repos/.moot`, under names that can't silently fall back to
`bob`, having learned how from the moot skill. Everything after it
(orchestrator-room, dev-room, trial-run) uses the MVP for real work and
records what happens; none of it is needed to start.

## Do

1. `~/repos/moot/install.sh ~/repos`, then mark it shared per host-moot's
   name guard. `~/repos` is not a git repo (as of 2026-11-16), so nothing
   commits the rooms; note that.
2. Join two rooms:
   - `runs`: orchestrators' status posts and requests ([[orchestrator-room]]).
   - `dev`: development chat between Bob and agent sessions in any repo
     ([[dev-room]]).
   Whether usage readings get their own room stays open: ai-kit's
   shared-usage-cache (built 2026-11-15) already stops local callers
   tripping the rate limit, so start with readings inside `runs` status posts.
3. Bob posts one opening message in each room.
4. Fill "Setup of record" in `../trial-kit.tied/observations.md`: path,
   sharing mode (one filesystem, plain directories), rooms, names, who runs
   `catchup` on what heartbeat.
5. Note how a moot.sh update reaches `~/repos/.moot` (re-run `install.sh`;
   it copies, it doesn't link).

## Tie-off

`~/repos/.moot/moot.sh rooms` lists `runs` and `dev`, each with an opening
post; a session in another repo has posted to `dev` and caught up with no
coaching (host-skill's check, done for real); the setup of record is written.
