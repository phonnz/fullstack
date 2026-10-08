# Conversation start-or-resume with the first message

Replace `Fullstack.JidoMarketAgents.Conversations.start_conversation/2` with
`start_or_resume/3`, whose second argument is always a new user message, and make it the
single write entry point of the Business Discovery Evaluate LiveView.

## Objective, problem, why

Today creating or reopening a conversation and sending its first message are two round trips
joined by `push_patch`; every "New conversation" click leaves an empty `jido_conversations`
row and the runtime starts on every navigation. One validated write operation removes the
empty rows, the double start call, and the runtime start on read-only visits. Plan of record:
Engram `plan/conversations-start-or-resume-3` (revision 2, verified by the LiveView expert).

## Scope and constraints

- Contract: `start_or_resume(user_id, message, conversation_id)` with an explicit `nil` for a
  new conversation (no default, arity exactly 3). Returns `{:ok, %Record{}}` or
  `{:error, :invalid_user_id | :invalid_message | :invalid_conversation_id | :not_found |
  Ecto.Changeset.t() | {:conversation_start_failed, term()}}`. Validation order: user id,
  message (binary, non-blank after trim), conversation id; no side effect before all pass.
- The context never persists the message (D1) and never subscribes the caller (user decision
  2026-10-08). It enqueues through `Fullstack.JidoMarketAgents.send_message/4` (D7).
- Navigation is read-only: `handle_params` uses `get_for_user/2` + `list_messages/1`; no
  runtime start. "New conversation" only `push_patch`es to the base path. The first `send`
  creates the record and patches to its URL; `handle_params` skips reload and subscribe when the
  assigned record already has that id (function-head match). Malformed ids are guarded in the
  LiveView before the getter (cast error would be a 500).
- Known accepted loss: the `{:buffered, _}` broadcast of a new conversation's first message is
  emitted inside `MessageBuffer.append/3` before `start_or_resume/3` returns; the send clause
  assigns `:phase :buffering` itself. No test may assert that broadcast for a new conversation.
- Remove the per-send re-subscribe (phoenix_pubsub 2.2.0 stacks duplicate registrations).
- Hoist the message form out of the `if @conversation` branch; do not duplicate it.
- Do not change `conversation.ex`, `rate_limiter.ex`, or the admin evaluations LiveView. The
  `RateLimiter.forward/2` user-id drop is a separate work unit. Amendment 2026-10-08: T1's
  concurrency test exposed a pre-existing race in `MessageBuffer.find_or_start/1` (the loser of
  a concurrent same-user start gets `{:error, {:already_started, pid}}` and `append/3` raises
  `MatchError` in the caller). A rescue-and-retry workaround in the context was rejected
  (exception-driven control flow hiding a real defect). The normalization in
  `find_or_start/1` plus its test are authorized as work unit **T0** with their own commit.
- The working tree carries other uncommitted streams (telemetry, atom-role rendering, LLM CLI
  tests, waitlist). Writers edit in place and never stage or commit; the orchestrator stages
  this feature's hunks in isolation and verifies them with `git stash --keep-index`.

## Authorized files

- `lib/fullstack/jido_market_agents/message_buffer.ex` (`find_or_start/1` only, T0)
- `test/fullstack/jido_market_agents/message_buffer_test.exs` (T0)
- `lib/fullstack/jido_market_agents/conversations.ex`
- `lib/fullstack_web/live/business_discovery/evaluate.ex`
- `lib/fullstack_web/live/business_discovery/evaluate.html.heex`
- `test/fullstack/jido_market_agents/conversation_start_test.exs`
- `test/fullstack_web/live/business_discovery_evaluate_test.exs`
- `odd/tasks/business-discovery-design.md`, `odd/tasks/business-discovery-spec.md` (D10, S14.3)
- `odd/tasks/conversation-start-or-resume.md` (this tracker)

## Work units

- [x] **T0 — MessageBuffer: tolerate concurrent buffer starts for one user.** Route: delegated
  direct (same writer as T1, continued). RED: 10 concurrent `append/3` calls for a fresh user
  observed to raise `MatchError` under `--repeat-until-failure`; GREEN: `find_or_start/1`
  normalizes `{:error, {:already_started, pid}}` to `{:ok, pid}`. Files:
  `lib/fullstack/jido_market_agents/message_buffer.ex` (that function only),
  `test/fullstack/jido_market_agents/message_buffer_test.exs`. Commit: `91d6a74`.
- [x] **T1 — Context: add `start_or_resume/3`** next to `start_conversation/2` (kept until T2 so
  every commit compiles). Route: **delegated direct** (writer trigger: 2 non-trivial files;
  preparation reading). RED first in `conversation_start_test.exs`: blank message returns
  `{:error, :invalid_message}` with no row and no runtime; new conversation returns an owned
  record, binds the runtime to the user, and `buffer_status(user_id) == :buffering`; resume
  returns the same record and pid and preserves history; dead runtime rehydrates for
  active/researching/completed/error; foreign, missing and malformed ids return `:not_found` /
  `:invalid_conversation_id` with nothing buffered; supervisor down returns
  `{:conversation_start_failed, _}` with nothing buffered; concurrent first sends on one id keep
  one runtime. `@spec`/`@doc` added. Acceptance: focused runner green, format and whitespace
  checks exit 0. Commit: `2d2e824`.
- [ ] **T2 — LiveView and template migration; remove `start_conversation/2`.** Route:
  **delegated direct** (writer trigger: 3 non-trivial files). RED first in
  `business_discovery_evaluate_test.exs`: empty state renders the composer; first send creates
  a record, patches to its URL, keeps the optimistic message after the patch; navigating to an
  id renders history without starting a runtime (Registry empty); malformed and foreign ids
  404; repeated sends keep exactly one Registry entry for the topic; blank input creates no row
  (`list_for_user(user.id) == []`); S14.3 rewritten; `start_conversation/2` tests folded into
  `start_or_resume/3` tests. Docs: D10 in `business-discovery-design.md`, S14.3 wording in
  `business-discovery-spec.md`. Acceptance: focused runner green, format and whitespace checks
  exit 0, `JidoMarketAgents.resume/1` callers unaffected. Commit: pending.

## Verification and delivery

- TDD: **strict**, source: session `Strict TDD Mode: enabled` marker. Runner:
  `mix test <focused files>`; observe RED, then GREEN, then REFACTOR.
- Focused runner:

```sh
mix test test/fullstack/jido_market_agents/conversation_start_test.exs test/fullstack/jido_market_agents/conversations_test.exs test/fullstack/jido_market_agents/conversation_rehydration_test.exs test/fullstack/jido_market_agents/conversation_persistence_test.exs test/fullstack_web/live/business_discovery_evaluate_test.exs test/fullstack/jido_market_agents/facade_send_message_test.exs
```

- Additional checks: scoped `mix format --check-formatted` on the touched files; `git diff --check`.
- Baseline on the restored tree after `db2d025`: see Progress.
- Branch: `ft-maestro-agents`. Base boundary: `db2d025`. Delivery strategy: `single-pr` (session
  preflight choice); forecast ~300 source/test lines for T1 and ~300 for T2 plus docs, so the
  feature exceeds the 400-line review budget. PR slicing or a `size:exception` is the user's
  call at PR time; commits stay one per work unit. No push, no PR.
- RDD: **off** (`gentle-ai review mode status`: global off). Ordinary verification applies.
- Known environmental noise: dev `mix compile --warnings-as-errors` fails on pre-existing
  warnings in unrelated modules; `mix test` regenerates `priv/static/assets/app.css`, so reset
  `priv/static/assets/` before any `git stash pop`.

## Progress and evidence

- 2026-10-08: tracker created after plan revision 2. T1 of the predecessor tracker committed as
  `db2d025`.
- 2026-10-08: T1 writer (sonnet) reported done: +70 `conversations.ex`, +155
  `conversation_start_test.exs`; RED 17 tests / 8 failures (UndefinedFunctionError), GREEN 17/0,
  focused runner 77/0, format and whitespace checks exit 0. Native assess over the whole dirty
  tree: `high` for reasons outside this feature (generated `app.js`, `chatty.sh`); treated as high
  for this work unit, so an independent verifier runs before commit. Writer continued for T0 and
  for removing the rescue from `start_or_resume/3`.
- 2026-10-08: writer follow-up done. T0: RED observed on the first repetition of the new
  10-way concurrent `append/3` test (`MatchError` at `message_buffer.ex:66`), GREEN across 30
  repetitions after normalizing `already_started` in `find_or_start/1` (+7/-1, single hunk; the
  three telemetry hunks untouched). T1: `enqueue_message/3` rescue removed; `start_or_resume/3`
  calls `send_message/4` directly; 5-way concurrency test stable across 20 repetitions.
  Eight-file runner: 93 tests, 0 failures; format and whitespace checks exit 0. Independent
  read-only verifier launched (high tier) before staging and commit.

- 2026-10-08: independent verifier (sonnet, read-only): pass, no defects; 16 repetitions of the two
  new suites green; `buffer_status/1` is not timing-dependent (the buffer process never terminates
  after a flush); one pre-existing flake observed in `facade_send_message_test.exs` (1 of 4 full
  runs, unrelated to this diff). Staged in isolation (`git stash --keep-index`, assets excluded):
  eight-file runner **92 tests, 0 failures** (the stashed atom-role LiveView test accounts for the
  difference from 93), format and whitespace checks exit 0. Commits: T0 `91d6a74`, T1 `2d2e824`.
  Running count of authored lines committed for this feature: 246 (T0 35, T1 211), docs excluded.

## Next step

Delegate T2 (LiveView, template, test rewrite, D10/S14.3 docs, removal of `start_conversation/2`)
to a bounded writer with this tracker and the plan; base boundary for T2 is `2d2e824`.
