# Architecture decisions — index

> 🇫🇷 **Version française : [docs/README.md § Index complet des ADR](../README.md)**
> and the full records in [`docs/adr/`](../adr/).

This page summarises **every** architecture decision record in one line of
context, one of decision, and one of consequence. It exists because the full
records are written in French and total roughly 44 000 words — translating them
all was judged a worse use of effort than making all of them *findable* and
*understandable* in English.

**What this page is not.** It is not a substitute for the records. Each record
carries the alternatives that were rejected and why, which is the part that
actually justifies a decision. If a decision matters to you, read the record —
the code snippets, tables and diagrams inside are largely language-neutral.

The bilingual scope, and why it stops here, is stated in
[docs/README.md](../README.md#périmètre-bilingue).

---

## Foundations

**ADR 001 — Observability stack: LGTM.** *Context:* the project needs logs,
metrics and traces without a licence budget. *Decision:* adopt Loki, Grafana,
Tempo and Prometheus. *Consequence:* one vendor, OpenTelemetry-compatible, and
far less memory than an ELK stack since Loki indexes labels only.

**ADR 002 — Docker Compose for development.** *Context:* every developer needs
the same environment. *Decision:* Compose v2 for local orchestration, and a
multi-stage Dockerfile for the production image. *Consequence:* one command
starts everything; the final image stays under 30 MB.

**ADR 003 — GitHub Actions and GHCR.** *Context:* CI/CD had to live where the
code already is. *Decision:* GitHub Actions, with GitHub Container Registry for
images. *Consequence:* no third-party CI to operate, at the cost of coupling the
pipeline to GitHub.

**ADR 004 — 12-Factor configuration through Viper.** *Context:* no value may be
hard-coded. *Decision:* centralise loading in `internal/config`, reading `.env`
in development and the environment in production. *Consequence:* the API
**refuses to start** when a required variable is missing — failure is loud and
immediate rather than latent.

**ADR 037 — Database initialisation.** *Context:* schema, migrations and seed
data needed a single owner. *Decision:* SQL migrations applied at startup, seed
only in development. *Consequence:* an ORM was explicitly rejected; the schema
is written by hand and read by sqlc.

**ADR 007 — Database access with sqlc.** *Context:* raw SQL is precise but
untyped. *Decision:* write SQL, generate typed Go from it. *Consequence:*
queries are checked against the real schema at generation time; the generated
code is never edited.

**ADR 008 — Handler / service / repository layering.** *Context:* the backend
needed a shape that survives growth. *Decision:* three layers per domain, with
narrow interfaces declared by the consumer. *Consequence:* handlers are tested
against stubs, services against in-memory fakes.

## Authentication and accounts

**ADR 006 — JWT authentication.** *Context:* sessions must survive an app
restart without keeping a password. *Decision:* a 15-minute HS256 access token,
plus a refresh token stored **hashed** and rotated on every use. *Consequence:*
a stolen refresh token stops working at the next legitimate renewal; an access
token stays valid until it expires.

**ADR 009 — Authentication on the Flutter side.** *Context:* tokens must not sit
in plain storage. *Decision:* Keychain and EncryptedSharedPreferences, with a
**serialised** refresh — many parallel 401s trigger a single renewal.
*Consequence:* logout purges local storage even when the network call fails.

**ADR 010 — Password reset, backend.** *Context:* a reset link is a credential.
*Decision:* store only the token's hash, single use, short-lived, and answer
identically whether the address exists or not. *Consequence:* the endpoint
cannot be used to discover who has an account.

**ADR 011 — Password reset, Flutter.** *Context:* the link must reopen the app.
*Decision:* a custom-scheme deep link. *Consequence:* the flow works without a
web page, at the cost of platform-specific configuration.

**ADR 038 — User profile.** *Context:* preferences do not belong on the
identity row. *Decision:* a dedicated `profiles` table, one-to-one with `users`,
created by a trigger. *Consequence:* a profile exists from the moment an account
does, so reads never have to handle its absence.

**ADR 014 — Requesting the broadcaster role.** *Context:* not every account may
broadcast. *Decision:* an explicit request, reviewed by an administrator, that
promotes the account within a single transaction. *Consequence:* a review
decision and a role change can never disagree.

## Streaming

**ADR 013 — The streaming domain.** *Context:* streams have a lifecycle, an
owner and secrets. *Decision:* one domain owning creation, visibility, the
`stream_key` and live sessions, with **one live stream per broadcaster**.
*Consequence:* the constraint is enforced by a partial unique index, not by
application code.

**ADR 015 — HLS engine, ffmpeg segmentation.** *Context:* browsers and mobile
players expect HLS. *Decision:* one ffmpeg process per live session, copying
AAC into ~10 s `.ts` segments with a sliding manifest. *Consequence:* no
transcoding cost on the nominal path; the process is killed and its directory
cleaned on stop.

**ADR 030 — On-the-fly ingest transcoding.** *Context:* broadcasters do not all
push AAC. *Decision:* insert a second ffmpeg **only** when the content type is
not AAC. *Consequence:* the AAC path pays neither a process nor a re-encode;
undecodable input returns 415 rather than 500.

**ADR 027 — Microphone capture and AAC push.** *Context:* broadcasting from a
phone had to be possible without external software. *Decision:* capture on
device and push AAC/ADTS straight to the ingest endpoint. *Consequence:* the
phone becomes a complete broadcasting station.

**ADR 028 — Rotating the stream key.** *Context:* a leaked key must be
revocable. *Decision:* rotation replaces the key and invalidates the old one,
and is **refused while the stream is live**. *Consequence:* rotation cannot
break a broadcast in progress.

**ADR 016 — Scalability, load testing and the HLS limiter.** *Context:* the
brief asks for evidence, not confidence. *Decision:* a repeatable load test and
a concurrency cap on HLS requests. *Consequence:* past the cap the server
answers 503 with `Retry-After` immediately, rather than queueing and degrading
for everyone.

**ADR 025 — Real-time audience statistics.** *Context:* HLS holds no persistent
connection. *Decision:* estimate listeners from the playlist request rate.
*Consequence:* the order of magnitude is right and an exact count does not
exist — which the interface says plainly.

## Listening and library

**ADR 023 — Mobile HLS audio player.** *Context:* playback must survive
navigation. *Decision:* a single app-level player behind an abstraction the
controller depends on. *Consequence:* the player is testable with a fake, and
playback does not stop when the screen changes.

**ADR 031 — Background playback.** *Context:* audio must continue when the
screen locks. *Decision:* `audio_service`, with a system notification and its
controls. *Consequence:* native declarations are required on both platforms,
and the behaviour can only be tested on a device.

**ADR 033 — Handling audio interruptions.** *Context:* a call or a notification
must not leave playback in an inconsistent state. *Decision:* a **pure,
testable** interruption policy — pause and resume for calls, duck for
notifications, pause without resume when headphones are unplugged.
*Consequence:* the rule is unit-tested rather than observed by hand.

**ADR 026 — The playlists domain.** *Context:* playlists are personal.
*Decision:* ownership filtered in SQL, and a third party's playlist returns
**404** rather than 403. *Consequence:* the API never reveals that a resource it
refuses exists.

**ADR 029 — Playlist tracks: add, remove, reorder.** *Context:* reordering
rewrites every position, so intermediate states necessarily contain duplicates.
*Decision:* a **deferred** unique constraint, checked at commit, with all
mutations inside a transaction. *Consequence:* `ON CONFLICT` must name its
columns — a deferred constraint cannot arbitrate.

**ADR 032 — The track domain and audio upload.** *Context:* an uploaded file is
untrusted input. *Decision:* **sniff** the MIME type from the content, store
outside any served directory under a generated name, and cap both file and
account size. *Consequence:* a PDF renamed `.mp3` is rejected; the client's file
name never reaches the filesystem.

**ADR 034 — Playing a playlist with a queue.** *Context:* the player must
chain tracks. *Decision:* delegate chaining to the native player and follow its
index, rather than keeping a second source of truth. *Consequence:* a skip from
the system notification travels the same path as a tap in the app.

**ADR 035 — Shuffle and repeat.** *Context:* a shuffled order must be stable.
*Decision:* let the native player draw the order, and re-apply it on
**involuntary** reloads. *Consequence:* a token expiry no longer reshuffles the
queue every fifteen minutes.

**ADR 042 — In-app volume and live listening time.** *Context:* the brief lists
a volume control and a progress bar; the code documented the absence of the
former as a deliberate choice. *Decision:* put volume on `PlaybackTransport` —
so one slider serves both live and queue — keep the listener's setting as the
source of truth with ducking as a factor derived from it, and show a live's
elapsed **listening time** rather than a progress bar. *Consequence:* a volume
change made during an interruption survives it, and the elapsed counter survives
a reconnection, where the player's own position would reset because the
controller reloads the source.

**ADR 043 — App accessibility and width adaptation.** *Context:* one `Semantics`
call across 147 files, no layout adaptation, and landscape allowed by both
manifests. *Decision:* give icon-only controls a real semantic **label** — a
tooltip lands in the node's `tooltip` field, which iOS turns into a hint, so the
button has no name for VoiceOver — run Flutter's WCAG guidelines in CI alongside
a stricter in-house check, and **adapt** to width rather than locking portrait.
*Consequence:* screen-reader behaviour is still unverified on real devices, and
that gap is declared rather than glossed over.

## Administration

**ADR 017 — Admin dashboard, user management.** *Context:* administration must
not be able to lock itself out. *Decision:* search, filtering, deactivation and
deletion, with two guards — no self-action, and never the last active
administrator. *Consequence:* both return 409 with an explicit message.

**ADR 039 — Admin supervision and audit log.** *Context:* moderation must leave
a trace. *Decision:* interrupt any live stream without an ownership check, and
record it. *Consequence:* `actor_id` is set to NULL when the administrator's
account is deleted — the fact survives, the person does not.

**ADR 024 — Broadcaster dashboard.** *Context:* a stream can stop without its
owner acting. *Decision:* dedicated start and stop endpoints, and a server-sent
event stream the dashboard subscribes to. *Consequence:* the interface reflects
reality rather than the last action taken.

## Observability

**ADR 018 — Structured logs, zerolog and Loki.** *Context:* text logs are not
queryable. *Decision:* one JSON line per request, correlated by `request_id`,
with the `stream_key` redacted from paths. *Consequence:* `log.Printf` is banned
project-wide.

**ADR 019 — Prometheus metrics and cardinality.** *Context:* an unbounded label
kills a metrics store. *Decision:* label paths with the **router pattern**
rather than the URL, and keep methods to an allowlist. *Consequence:* there is
no table to keep in sync, and cardinality is bounded by construction.

**ADR 020 — OpenTelemetry traces to Tempo.** *Context:* a slow request must be
explainable. *Decision:* OTLP export, one span per SQL query — without the
arguments — and `trace_id` in every log line. *Consequence:* traces are disabled
by default locally, so `go run` needs no collector.

**ADR 021 — Provisioned Grafana alerting.** *Context:* an alert configured by
hand is lost with its container. *Decision:* declare contact points, policies
and rules as code. *Consequence:* the truth lives in git and the UI is
read-only.

**ADR 022 — Streaming business metrics.** *Context:* a technical 500 and a
listener dropping out are not the same event. *Decision:* separate business
metrics, and **delete** per-stream series when a stream ends. *Consequence:*
cardinality does not grow with every broadcast.

**ADR 041 — Throughput, listener departures and the admin summary.** *Context:*
outbound bandwidth was never measured, nothing counted listeners leaving, and
the admin role had no access to any metric. *Decision:* publish the byte counter
the access log already kept, count departures and stream interruptions as
business metrics, split each dashboard into business and technical rows, and
serve `GET /api/admin/metrics` from the **process's own** Prometheus registry
rather than by querying the Prometheus server. *Consequence:* the admin summary
reports totals since process start, not sliding rates — and HLS being
connectionless, a listener closing the player and a listener losing the network
are indistinguishable, so the metric is named *departures*, never
*disconnections*.

## Contracts and cross-cutting concerns

**ADR 012 — OpenAPI as the source of truth.** *Context:* a client and a server
drift. *Decision:* the specification is the contract; the Dart client is
generated from it. *Consequence:* a route change without a spec change is a bug,
and the spec is not published in production.

**ADR 005 — Flutter Clean Architecture.** *Context:* the mobile code needed a
shape. *Decision:* three layers per feature, entities free of any infrastructure
import. *Consequence:* superseded on state management by ADR 036.

**ADR 036 — `provider` rather than Riverpod.** *Context:* the course forbids
Riverpod. *Decision:* `provider` with `ChangeNotifier`, and the constraint
written down rather than hidden. *Consequence:* selective invalidation costs
more; the record says what that costs and how it is mitigated.

**ADR 040 — Mobile distribution.** *Context:* the app was signed with the debug
key and built nowhere. *Decision:* release signing that **degrades** loudly when
the key is absent, and Android artefacts attached to each GitHub release.
*Consequence:* iOS is not distributed — TestFlight requires a paid Apple
Developer account the team does not have, and that absence is stated rather than
faked.

**ADR 044 — CPU cost of streaming and VPS sizing.** *Context:* the brief asks
what 100 concurrent streams cost in CPU, and nothing in the repository measured
the processor or named the server's price. *Decision:* measure with
`getrusage`, counting child processes separately and subtracting the load
generator's own ffmpeg, on a sweep over the number of *streams* rather than the
number of listeners — and refuse to publish a figure measured under `-race`.
*Consequence:* 100 AAC streams cost 0.6–0.8 core across two runs, 100 transcoded
streams 2.4 — a 3–4× gap that turns ADR 030's "worth watching" into a number.
Every figure is an upper bound: the simulated clients share the measured
process, so their own HTTP work cannot be separated from the server's. And the
first ceiling StreamPulse will hit as it grows is bandwidth, not CPU.

**ADR 045 — HLS manifest error codes.** *Context:* the manifest returned one
indistinguishable `409` for a finished broadcast and for a live one still
writing its first segment — two situations calling for opposite behaviour, which
the server could tell apart and the client could not. *Decision:* keep the
status, split the meaning into two public `error.code` values
(`stream_not_live`, `manifest_not_ready`), and have the player apply the
server's verdict instead of guessing from whether playback had ever started.
*Consequence:* opening an already-ended stream from a stale list now says so
immediately, where it previously spent ~15 s reconnecting toward a conclusion the
server had from the first request. An unrecognised code falls back to "not
ready": erring toward waiting costs a bounded backoff, erring toward "over"
would cut off a broadcast that is starting.

**ADR 046 — Track recommendations from listening history.** *Context:* US-09-04
asks for a simple recommendation based on listening history, but no listening
history was persisted and live HLS offers no reliable per-user signal (public,
connectionless). *Decision:* capture a play best-effort on the authenticated
track-stream endpoint (`listening_history`, one row per play, counted only on a
from-the-start request so `Range` seeks do not inflate it), and rank candidates in
a single SQL query (two CTEs): never-played first, then artist affinity, then
rediscovery, then recent additions, with cold-start handled by construction. The
candidate pool is the requester's own tracks plus other users' public tracks
(STR-248); a stranger's private track is never recommended, and `from_others`
drives a "public discovery" reason. *Consequence:* the endpoint always returns
something useful rather than an empty list, and the algorithm lives in the query
(validated by an integration test against a real PostgreSQL). Known limit: the
native player preloads the whole queue, so starting a queue records every track,
not only the one actually heard — acceptable for a simple reco, documented, with a
client-side fix left to a separate ticket.

**ADR 047 — Sign in with Google.** *Context:* the login screen had an inert Google
button, and a Google account has no local password while `users.password_hash` was
`NOT NULL`. *Decision:* a dedicated `POST /api/auth/google` verifies the Google ID
token with the official `idtoken` library (signature, expiry, audience =
`GOOGLE_CLIENT_ID`), finds-or-creates the account (first sign-in creates a `user`,
username derived from the email), and issues the usual StreamPulse token pair; the
`GoogleVerifier` is an injected interface and the route is mounted only when
`GOOGLE_CLIENT_ID` is set. Migration `000024` makes `password_hash` nullable, reads
using `COALESCE(password_hash, '')` so Go still gets a `string` and password login
stays safe (bcrypt fails on the empty hash).
*Consequence:* Google users have no local password, an existing email/password
account is reachable through Google by the same email, and the feature is optional
(the route is absent in dev without a client id); validated end-to-end on the iOS
simulator.

**ADR 048 — Restarting an ended stream.** *Context:* `StartStream` accepted `idle`
only, so an `ended` stream was permanently dead — and two of the three ways a
broadcast ends involve no decision by the broadcaster (an admin stop, or the
45-second ingest lease expiring). The dashboard had drawn the consequence: no
start button, no ingest URL, no key rotation, just "create a new stream". Since a
stream carries a title, a description and an ingest key, that meant losing the
channel and having to redistribute a fresh key. *Decision:* the transition accepts
`idle` **or** `ended` and resets `ended_at` to null — a stream is a reusable
channel, not a record of a past broadcast; the 409 message narrows to
`stream is already live`; mobile uses a `canStart` predicate instead of hard-coded
`isIdle`. *Consequence:* no migration is needed (the partial unique index
`streams_one_live_per_user` still enforces one live per broadcaster), `started_at`
is overwritten on restart so the tile measures the current broadcast rather than a
total, and an ended stream re-exposes its ingest URL to its owner.

**ADR 049 — Mobile broadcast lifecycle: leaving the app is not closing it.**
*Context:* the dashboard ended the live server-side on
`AppLifecycleState.hidden`, which on the web is produced by a plain browser tab
switch; because every `start` forks a fresh ffmpeg segmenter in a fresh temp
directory, segment numbering and `EXT-X-MEDIA-SEQUENCE` restarted at zero, sending
listeners back to the first segment; and releasing the microphone whenever the app
left the foreground meant that pressing Home stopped capture — with HLS timestamps
derived from the ADTS frame count rather than wall-clock time, listeners then heard
an abrupt jump rather than a silence, while the broadcaster's tile still read
"live". *Decision:* the lifecycle now distinguishes only "elsewhere"
(`inactive`/`hidden`/`paused` — nothing happens) from "closed" (`detached` — the
live is ended best-effort); an Android foreground service keeps capture alive
(`foregroundServiceType="microphone"`, plus `FOREGROUND_SERVICE_MICROPHONE` at
`targetSdk` 36), declared in the app manifest because the `record` plugin ships the
service class but not its declaration, with `stopWithTask="true"` so it dies with
the task; an ingest `409` becomes `IngestConflictException` so the publisher stops
retrying instead of ending an external encoder's broadcast. *Consequence:* a
permanent notification shows for the whole broadcast (the system price of
background microphone access); closing the app ends the live immediately for
capture and within the 45-second ingest lease for the server status; suspending
and resuming capture, and adopting a still-live stream on app start, were both
prototyped and rejected — the first still made listeners hear a jump, the second
relit a microphone without user action; **iOS is unverified**, no device was
available.

**ADR 050 — Measuring and announcing recovered broadcast outages.** *Context:* a
20-second network outage was staged on a real device while the broadcaster
counted aloud; listeners heard "…five, six, **twenty-five**, twenty-six…" with no
gap at all. Two mechanisms combine: losing the connection also stops capture (each
retry restarts the encoder so the server gets a self-contained AAC/ADTS stream),
and HLS timestamps derive from the ADTS frame count rather than wall-clock time,
so the segmenter splices the two ends without knowing twenty seconds passed. The
splice itself is the right trade for radio — dead air is worse than a cut
sentence — but nobody was told: `stream_interruptions_total` only counts
*terminated* broadcasts, so an outage that recovers before the ingest lease
expires incremented nothing (verified during the test), and the broadcaster, who
does see "Reconnexion audio…" during the outage, was never told afterwards how
much had been lost. *Decision:* two new series,
`streampulse_ingest_recoveries_total` (how often) and
`streampulse_ingest_outage_seconds` (how much time lost — a mean would conflate a
one-second hiccup with a thirty-second gap), measured at re-attach rather than at
detach because at detach it is not yet known whether the outage will recover or
end the broadcast; and the dashboard tells the broadcaster the duration on
recovery, derived from state transitions where only `reconnecting` opens an
outage — `connecting` is a broadcast's first attempt and counting it would
announce a loss at every start. Nothing is added for listeners: they have no
channel (SSE requires a JWT, listeners may be anonymous) and they felt nothing —
the ~60-second HLS window absorbed the outage. *Consequence:* recovered outages
appear in Grafana and become an alerting candidate, and the broadcaster can
repeat what was lost; the splice stays silent, so listeners still lose content
without knowing. `EXT-X-DISCONTINUITY` — the format's own marker, which signals a
broken timeline without inserting silence — is the correct answer and remains out
of scope. Note that the perceived resilience comes from the listener's buffer,
not the server: a longer outage, or a listener who just joined, would hear it.

> ADR 040 lands with the mobile distribution change; it is listed here because
> this index is meant to stay complete.
