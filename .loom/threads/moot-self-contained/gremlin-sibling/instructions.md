# gremlin-sibling 🪪

**Intent.** Read `.gremlin/name` as a sibling, the way every other primitive in
the family does. Depends on [[room-layout]].

## The walk can go

[[identity]] kept an upward `$PWD` walk for `.gremlin/name`, and was explicit
about why: *"the gremlin runs `catchup` from its own repo root while the room
lives elsewhere, so a sibling read cannot reach `.gremlin/`."*

Containment deletes that reason. `.moot/` now sits beside `.gremlin/` in the
host's own directory, so the name is one hop up from `$moot_dir` — a fixed
path, resolved from the script's own location, independent of the working
directory. That is what the rest of the family does, and it is strictly better
than the walk: `catchup` from any cwd resolves the same name, and a stray
`.gremlin/` in some ancestor of wherever the heartbeat happened to run can no
longer be picked up by accident.

Replace the walk with `$moot_dir/../.gremlin/name`. Keep the `name=` field
parse and the bare-first-line fallback exactly as [[identity]] shipped them —
that bug is fixed and the fix is not what is changing here.

The chain itself is unchanged in order and meaning:

```text
--as   →   $MOOT_NAME   →   .moot/name   →   ../.gremlin/name   →   $USER
```

## The wiring line

The one line a gremlin host runs loses its absolute path:

```sh
.moot/moot.sh catchup --deliver .nest/in/
```

Relative, from the host root, identical in shape to `.loom/loom.sh` and every
other sibling. This is the point of the whole thread, and it is worth checking
it actually reads that way on a real host before tying.

## Accepted loss

A `.moot/` installed somewhere with no `.gremlin/` beside it no longer finds a
gremlin name from an ancestor. That is correct: it means the `.moot/` is not
part of that gremlin, and `$USER`, `$MOOT_NAME` or `.moot/name` is the honest
answer. Nobody is left without a name.

## Tie-off

A gremlin host with `.gremlin/` and `.moot/` as siblings posts and catches up
under its own name, with no flags, from any working directory.

Tested including: both `.gremlin/name` shapes still parsing; resolution from a
cwd outside the host entirely; `.moot/name` taking precedence and `$MOOT_NAME`
and `--as` over that; an ancestor `.gremlin/name` that is *not* a sibling being
correctly ignored in favour of `$USER`.
