# Business Discovery — Implementation Tasks

**Status:** tasks — no source files modified.
**Date:** 2026-09-25
**Branch:** ft-agents
**Proposal:** `odd/tasks/business-discovery-liveview.md`
**Spec:** `odd/tasks/business-discovery-spec.md`
**Design:** `odd/tasks/business-discovery-design.md`

---

## Working agreement

- **TDD is strict.** Every task writes its tests first and observes them RED before any
  implementation exists. A task is not done until its scenarios are GREEN.
- **One commit per task**, Conventional Commits, on `ft-agents`. Record the commit SHA in
  the Progress log below as evidence.
- **Checkboxes are evidence, not intent.** Tick one only after its verification command has
  been run and observed. Failed or skipped checks get recorded honestly.
- **Delivery (user decision, 2026-09-26): ONE branch, NO PRs until all nine tasks are
  done.** All work stays on `ft-agents`. Slice gates below still run as checkpoints — full
  suite, format, warnings — but they no longer open a PR. This supersedes the per-slice PR
  instruction and the proposal's `ask-on-risk` chained-PR strategy; revisit slicing only
  when the whole feature is finished.

### Verification commands

```
mix test <path>                    # task-scoped, during the cycle
mix test                           # full suite, before each commit
mix format --check-formatted       # before each commit
mix compile --warnings-as-errors   # before each commit
```

`mix test` runs `ecto.create --quiet` and `ecto.migrate --quiet` first (`mix.exs:100`), so
migrations apply automatically.

### Sandbox constraint (applies to T3, T4, T7, T9)

`DataCase` starts the sandbox owner with `shared: not tags[:async]`
(`test/support/data_case.ex:39`). A `Conversation`, `MessageBuffer`, or `RateLimiter`
process is started by a supervisor — **not** by the test process — so it does not own the
sandbox connection. Any test where one of those processes touches Postgres must be
`async: false`, or it will fail with `DBConnection.OwnershipError`.

This is written down here because discovering it mid-task looks like a bug in the code
under test rather than a property of the test harness.

---

## Slice A — Persistence (~490 lines)

### T1 — Schemas and migration
**Satisfies:** R1 (S1.1, S1.2), R2 (S2.1)
**Files:** `conversations/record.ex`, `conversations/message.ex`,
`priv/repo/migrations/*_create_jido_conversations.exs`

- [ ] RED: schema tests — a record requires `user_id`; a message requires `role` and
      `content`; `role` is constrained to `user` / `assistant`.
- [ ] Migration per project convention: `table(..., primary_key: false)` with an explicit
      `add :id, :binary_id, primary_key: true` (`20241205133140_create_ulrs.exs`).
- [ ] Both schemas use `@primary_key {:id, :binary_id, autogenerate: true}` and
      `@foreign_key_type :binary_id` (`accounts/user.ex:4-5`).
- [ ] `validated_data` is a `:map` column, shaped like `extract_data/1`
      (`market_validator.ex:232`) — per design D3.
- [ ] FKs use `on_delete: :delete_all` (S1.2).
- [ ] Indexes: `user_id`, `[user_id, inserted_at]`, `[conversation_id, inserted_at]`.
- [ ] GREEN + `mix test test/fullstack/jido_market_agents/`
- [ ] Commit: `feat(jido): add conversation persistence schemas`

> Module is `Conversations.Record`, not `Conversations.Conversation` — design §4. A second
> module named `Conversation` in this namespace would collide with the existing GenServer.

### T2 — Conversations context
**Satisfies:** R1 (S1.3), R2 (S2.2), R3 (S3.4)
**Files:** `conversations.ex`

- [ ] RED: `get_for_user/2` returns `nil` for another user's conversation (S1.3).
- [ ] RED: `list_for_user/1` returns only that user's rows, newest first.
- [ ] RED: `list_messages/1` orders by `inserted_at` ascending (S3.4).
- [ ] Implement `list_for_user/1`, `create/2`, `get_for_user/2`, `append_message/2`,
      `update_state/2`.
- [ ] **No unscoped `get/1` exists** (design D8) — ownership is a `where` clause, so no
      call site can forget to guard.
- [ ] GREEN + `mix test test/fullstack/jido_market_agents/conversations_test.exs`
- [ ] Commit: `feat(jido): add Conversations context with user-scoped queries`

### T3 — Persist from the GenServer
**Satisfies:** R3 (S3.1, S3.2, S3.3), R4 (S4.1, S4.2)
**Files:** `conversation.ex` (modified)

- [ ] RED (`async: false`, see sandbox note): after a user message, a row exists with
      `role: "user"` (S3.1); after an agent reply, `role: "assistant"` with metadata
      preserved (S3.2).
- [ ] RED: on receiving a broadcast, the payload's messages are already committed (S3.3).
- [ ] RED: status transitions are persisted before broadcast (S4.1, S4.2).
- [ ] Change `broadcast/3` (`conversation.ex:245`) to persist-then-broadcast. This is the
      single funnel — all 6 transitions route through it, and there is exactly one
      `Phoenix.PubSub.broadcast` call (`conversation.ex:259`).
- [ ] On persistence failure: log and broadcast anyway (design D2). Assert this explicitly
      — the user must still receive their answer.
- [ ] Extend the existing Bandit LLM stub test rather than building a new harness
      (`jido_market_agents_test.exs:8`).
- [ ] GREEN + `mix test test/fullstack/`
- [ ] Commit: `feat(jido): persist conversation state before broadcasting`

### T4 — Rehydration
**Satisfies:** R5 (S5.1, S5.2, S5.3)
**Files:** `conversation.ex` (modified)

- [ ] RED (`async: false`): kill a conversation process, send another message, assert prior
      messages are intact and the new one is appended after them (S5.1).
- [ ] RED: a rehydrated conversation restores `validated_data`, so the user is **not**
      re-asked for fields already provided (S5.2). This is the scenario that makes
      rehydration worth building.
- [ ] RED: an id with no persisted row still starts empty (S5.3).
- [ ] Add the third case to `find_or_start/1`: miss → load → start with restored state.
- [ ] Rebuild the validator via `MarketValidator.new/1` + `set/2` — both public, generated
      by `use Jido.Agent` (`deps/jido/lib/jido/agent.ex:753,996`). Never deserialize the
      struct (design D3).
- [ ] GREEN + `mix test test/fullstack/`
- [ ] Commit: `feat(jido): rehydrate conversations from the database`

**Slice A gate:** `mix test` green, `mix format --check-formatted`,
`mix compile --warnings-as-errors`. PASSED at `71717fa`. No PR — continuing on `ft-agents`.

---

## Slice B — Throttling (~480 lines)

Independent of Slice A; may land before or after it. Must precede Slice C.

### T5 — RateLimiter
**Satisfies:** R7 (all), R8 (S8.1, S8.2), R9 (all)
**Files:** `rate_limiter.ex`

- [ ] Add config block (design D5) so tests use short durations instead of waiting 30
      minutes (spec N3):
      `debounce_ms`, `rate_limit_count`, `rate_limit_window_ms`, `cooldown_ms`.
- [ ] RED: batches under the limit are allowed and recorded (S7.1).
- [ ] RED: the batch over the limit is denied and broadcasts `{:rate_limited, ...}` with
      `retry_at` (S7.2).
- [ ] RED: entries older than the window are pruned — the window *slides* (S7.3).
- [ ] RED: users are counted independently (S7.4).
- [ ] RED: a denied batch is queued and one cooldown timer starts (S9.1).
- [ ] RED: further batches during cooldown queue and broadcast
      `{:queued_during_cooldown, ...}`; nothing is discarded (S9.2).
- [ ] RED: on expiry, queued batches forward **in order received** (S9.3) and status
      returns to `:active` (S9.4).
- [ ] RED: map input consumes no entry and is not queued during cooldown (S8.1, S8.2) —
      `extract_fields/2`'s `is_map/1` clause makes no LLM call (`market_validator.ex:87`).
- [ ] Single GenServer owning an ETS bag of `{user_id, timestamp}` (design D6).
- [ ] GREEN + `mix test test/fullstack/jido_market_agents/rate_limiter_test.exs`
- [ ] Commit: `feat(jido): add RateLimiter with ETS sliding window and cooldown`

### T6 — MessageBuffer
**Satisfies:** R6 (all)
**Files:** `message_buffer.ex`, `message_buffer_supervisor.ex`

- [x] RED: three messages inside the window produce exactly one forwarded batch joined by
      `\n\n` (S6.1).
- [x] RED: each new message **resets** the timer — flush occurs a full window after the
      *last* message, not the first (S6.2).
- [x] RED: two conversations in one window get separate batches; content never crosses
      (S6.3).
- [x] RED: `append` returns `{:ok, :buffered, id}` immediately (S6.4).
- [x] RED: `{:buffered, ...}` is broadcast so the UI can show collection (S6.5).
- [x] One process per `user_id` under `MessageBufferSupervisor` (design D6), found via
      `ConversationRegistry` namespaced with `{:message_buffer, user_id}` — no new registry
      added; T7 supervision wiring needs no extra registry step for this.
- [x] Unique ids per test via `System.unique_integer`. `async: false`, not `true` as
      originally assumed here — every test starts a real `RateLimiter` (a single named
      GenServer) via `start_supervised!/1` to drive the pipeline end-to-end, so concurrent
      tests would collide on that name. Same constraint as `rate_limiter_test.exs`.
- [x] GREEN + `mix test test/fullstack/jido_market_agents/message_buffer_test.exs`
- [ ] Commit: `feat(jido): add MessageBuffer with per-user debounce` — NOT committed per
      instruction; left in working tree for review.

### T7 — Wire into the facade and supervision tree
**Satisfies:** R10 (S10.1, S10.2)
**Files:** `jido_market_agents.ex`, `application.ex` (both modified)

- [ ] RED: legacy `send_message/3` still reaches the conversation directly and returns
      `{:ok, :accepted, id}` (S10.1).
- [ ] RED: new `send_message/4` goes through buffer + limiter and returns
      `{:ok, :buffered, conversation_id}` (S10.2).
- [ ] RED (`async: false`): end-to-end — rapid messages merge, flush, extract, broadcast.
- [ ] Add `send_message/4`, `user_status/1`, `buffer_status/1`.
- [ ] Supervise `RateLimiter` then `MessageBufferSupervisor` **before**
      `ConversationSupervisor` (design §5) — a flushing buffer must find the limiter alive.
- [ ] Confirm the existing suite still passes unchanged; `send_message/3` is load-bearing
      for current tests (design D7).
- [ ] GREEN + `mix test`
- [ ] Commit: `feat(jido): add buffered send_message/4 to the public API`

**Slice B gate:** `mix test` green, format, warnings-as-errors. Checkpoint only — no PR.

---

## Slice C — Interface (~480 lines)

Requires A (sidebar reads persisted rows) and B (chat must not ship unthrottled).

### T8 — Subdomain routing and landing page
**Satisfies:** R11 (all), R12 (S12.1, S12.2)
**Files:** `config/config.exs`, `router.ex`, `business_discovery/index.ex`

- [ ] RED: extend `test/fullstack_web/plugs/host_rewrite_test.exs` — a root request to
      `discover.agentson.live` rewrites to `/business-discovery` (S11.1); a deeper path is
      untouched (S11.2); an unmapped host is untouched (S11.3).
- [ ] RED: anonymous visitors see the landing page with a log-in CTA (S12.1); signed-in
      users see a link into `/business-discovery/evaluate` (S12.2).
- [ ] Add `"discover.agentson.live" => "/business-discovery"` to `:host_roots`
      (`config/config.exs:17`). No new plug — `HostRewrite` already handles this.
- [ ] Route under the existing `:public` live_session so `current_user` is assigned.
- [ ] **Placeholder copy** — structure and routing are what this task fixes, not wording.
- [ ] GREEN + `mix test test/fullstack_web/`
- [ ] Commit: `feat(web): add business discovery landing page and subdomain route`

### T9 — Evaluate LiveView
**Satisfies:** R13 (S13.1, S13.2), R14 (all), R15 (S15.1, S15.2), R16 (all), R17 (all)
**Files:** `business_discovery/evaluate.ex`, `evaluate.html.heex`, `router.ex`

- [ ] RED: anonymous access redirects to `/users/log_in` with an error flash (S13.1) —
      this is `:ensure_authenticated`'s existing behavior (`user_auth.ex:152`), so the test
      pins it rather than implementing it.
- [ ] RED: the sidebar lists only the user's conversations, newest first (S14.1, S14.2);
      an empty state still allows starting one (S14.3).
- [ ] RED: another user's conversation id returns **404** — not a redirect, which would
      confirm the id exists (S14.4, design D8).
- [ ] RED: selecting a conversation renders its history in order and distinguishes user
      from assistant (S15.1); subscribes to the new topic and unsubscribes from the old
      (S15.2).
- [ ] RED: a submitted message appears immediately (S16.1); subscribe happens **before**
      send so no broadcast can be missed (S16.2); empty input sends nothing (S16.3);
      transcript re-renders from `payload.messages` (S16.4).
- [ ] RED: the indicator appears on submit and persists through the debounce window
      (S17.1).
- [ ] RED: `:needs_data` **clears** the indicator — the agent is waiting on the user, not
      working (S17.2).
- [ ] RED: `{:research_complete, ...}` clears it (S17.3); `{:error, ...}` clears it and
      renders the error (S17.4).
- [ ] RED: `{:rate_limited, ...}` renders the limit notice with `retry_at` and leaves no
      spinner running (S17.5) — a stuck spinner makes "throttled" and "broken" look
      identical to the user.
- [ ] Optimistic render for S16.1: the LiveView renders the user's message into its own
      assigns **without persisting**; the authoritative `payload.messages` replaces it.
      Single writer preserved (design D1).
- [ ] Indicator is a derived `:phase` assign set by the last `handle_info`, never a
      boolean flag (design D9) — every terminal event clears it by construction.
- [ ] Follow `ChannelsChatLive`'s sidebar/streams layout rather than inventing one.
- [ ] GREEN + `mix test`
- [ ] Commit: `feat(web): add business discovery evaluate chat with conversation history`

**Slice C gate:** `mix test` green, format, warnings-as-errors. Final checkpoint; delivery decided after T9.

---

## Progress log

| Task | Route | Status | Commit | Checks observed |
| --- | --- | --- | --- | --- |
| T1 | delegated | done | `9c93030` | migrate+rollback+migrate ok; 7/7 green; suite 287 tests 9 failures (9 pre-existing, verified by stash); format clean; no new warnings |
| T2 | delegated | done | `5847c57` | 14/14 green (21/21 with T1); suite 301 tests, same 9 pre-existing failures; format clean on touched files; no new warnings |
| T3 | delegated | done | `24661e8` | 8/8 green; suite 309 tests, same 9 pre-existing failures; D2 rescue branch mutation-tested (removing `rescue` fails the test); format clean |
| T4 | delegated | done | `71717fa` | 4/4 green (33/33 jido); suite 313 tests, same 9 pre-existing; S5.2 mutation-tested (reverting partial-persistence fails it); format clean |
| T5 | delegated | done | `b9ce9a9` | 10/10 green; suite 323 tests, same 9 pre-existing; ETS dedup fix mutation-tested (reverting fails 7/10); format clean |
| T6 | delegated | done (uncommitted) | — | 5/5 green; suite 328 tests, same 9 pre-existing failures, 0 new; format clean; no new warnings (independently re-verified) |
| T7 | — | not started | — | — |
| T8 | — | not started | — | — |
| T9 | — | not started | — | — |

Route is `inline` or `delegated`, recorded per the ODD delegation triggers: 2+ non-trivial
files delegates to one writer; 4+ files for understanding delegates one mapper. T1, T5, T6,
T8, and T9 each touch 2+ non-trivial files and are expected to be `delegated`.

## Acceptance

The feature is done when every box above is ticked with observed evidence, all 53 scenarios
in the spec are GREEN, and the three slice gates have passed. Known limits in spec N4
(node-local rate limiting, volatile cooldown queue, resetting debounce window) are accepted
and do not block completion.
