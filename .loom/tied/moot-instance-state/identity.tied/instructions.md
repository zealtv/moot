# identity 🪪

**Intent.** Give the instance a name of its own, and fix the gremlin chain,
which does not currently work. Depends on [[instance-state]].

## The bug

`.gremlin/name` is a key=value file:

```text
name=tengu
source=generated
vocabulary=1
```

`gremlin_name` reads it as `head -n 1 | tr -d '[:space:]'`, yielding
`name=tengu`, which then fails `resolve_name`'s filename-safe check and dies.
Every gremlin host needs `--as` or `$MOOT_NAME` today, so the one line the
`gremlin-surface` stitch shipped has never run clean.

Parse the `name=` field, falling back to the first line when the file carries
no `=`, so an older bare-name file still resolves.

Keep the upward `$PWD` walk. It is the family's only one, and it is doing real
work: the gremlin runs `catchup` from its own repo root while the room lives
elsewhere, so a sibling read cannot reach `.gremlin/`.

## The chain

```text
--as   →   $MOOT_NAME   →   .moot/name   →   .gremlin/name   →   $USER
```

`.moot/name` is the payoff of having instance state at all: a human with more
than one identity, or a host with no gremlin, now has somewhere to say who they
are. `init` writes it only when given `--as`; otherwise the file stays absent
and the rest of the chain resolves exactly as before. Nobody is required to
have one.

## Tie-off

A gremlin host with a real `.gremlin/name` posts and catches up under its own
name with no flags. `.moot/name` overrides it; `$MOOT_NAME` and `--as` override
that.

Tested including: both `.gremlin/name` shapes; `.moot/name` taking precedence;
and a `.moot/name` holding an unsafe name, which must die with the existing
filename-safe message rather than writing a path.
