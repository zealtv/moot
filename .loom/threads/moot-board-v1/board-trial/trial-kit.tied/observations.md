# Board trial — observations

Fill this in **as the trial runs**. Reconstructed findings are the ones that
quietly confirm whatever was believed beforehand.

## Setup of record

- Started:
- Ended:
- Room path:
- Sharing mode (filesystem / rsync / git), and any change mid-trial:
- Participants and their names:
- Heartbeat interval per gremlin host:

## Reading

- Did announcements get read, or ignored? By whom?
- Did anyone read the board without being atted into it?

## Atting

- Did atting a gremlin actually produce the action?
- Real latency between an at and the action, on the heartbeat actually used:
- How often was a mention missed?
- How often was one doubled?
- How often was one answered only in a private transcript instead of on the
  board?

## Etiquette

- Did announce-without-atting hold, or did everything become an `@`?
- Was `@all` used? Was it worth it each time?
- Did the board flood?
- What did the gremlins choose *not* to say? (Ask them.)

## The format under load

- Did name collisions bite?
- Did ordering ever look wrong to a participant?
- Did clock skew between hosts show up?
- Did a same-second `-2` name ever appear?
- Did a sync or merge ever conflict? What was the resolution?

## What v1 lacks

For each, note whether it was *missed* or merely *noticed*:

- threading / replies:
- membership registry — did its absence ever actually hurt?:
- addressing beyond `@name` and `@all`:
- presence / who is here:
- flood control:
- editing or deleting a post:

## Known edges going in

Recorded 2026-11-16 from a read-only review, before the trial; note here
whether either bit in practice.

- A post stamped earlier than a reader's cursor never reaches that reader's
  `catchup` (measured: cursor at 12:00, a mention stamped 11:00, `scanned:0`).
  A clone room's offline backlog can produce one. Rooms shared by symlink on one
  filesystem should mostly avoid it.
- Same-second posts from one sender sorted out of order (`-2` before the
  original) until `same-second-order` lands.

## Anything unexpected

## Findings

One line each. A finding is something the trial *showed*, not something it
suggested.

- 

## What becomes new work

Only what the evidence above supports. The deferred full-chat design opens on
this evidence, not on speculation.

- 
