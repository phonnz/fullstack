# Centralize conversation start validation

Move authenticated conversation creation and reopening from Evaluate into the
Conversations context, preserving ownership, persisted history, and current UI behavior.

## Objective and scope

The LiveView currently coordinates create/load, ownership, and runtime startup.
Expose `start_conversation(user_id, conversation_id \\ nil)` with guard/`with`
validation in one context boundary; leave navigation, subscriptions, and rendering in Evaluate.

- Success: `{:ok, record}`; no public pid or transcript needed.
- `nil` conversation ID creates a record; an existing UUID ID loads only through `get_for_user/2`.
- Validate UUID string user/conversation IDs before Ecto queries; schema evidence:
  `lib/fullstack/accounts/user.ex:4` and
  `lib/fullstack/jido_market_agents/conversations/record.ex:13-14` use `:binary_id`.
- Preserve `create/2` foreign-key validation; do not add a separate user-existence query.
- Ensure runtime is running/restored; preserve all statuses.
- Load transcript in the LiveView only after subscription, preserving subscribe-before-history
  ordering without duplicate queries or a needless transcript read on creation.
- Missing, foreign-owned, and malformed conversation IDs produce identical UI 404 behavior.
- Tag runtime-start errors; present failures safely instead of crashing on pattern matches.
- No required title, status restrictions, message-send whitespace changes, MiMo fixes, or remote calls.

## Authorized files

- `lib/fullstack/jido_market_agents/conversations.ex`
- `lib/fullstack_web/live/business_discovery/evaluate.ex`
- `test/fullstack/jido_market_agents/conversation_start_test.exs` (new)
- `test/fullstack_web/live/business_discovery_evaluate_test.exs`
- `odd/tasks/conversation-start-validation.md` (this tracker)

Preserve existing dirty telemetry and atom-role rendering/test changes. Do not change
runtime `conversation.ex` without first reporting why it is necessary.

## Work unit

- [ ] **T1 — Centralize authenticated create/resume/ownership validation**, wire Evaluate,
  and add context/LiveView regressions. Route: **delegated direct**; triggers: mapping
  required 4+ files, preparation reading, and 2+ nontrivial source/test files.
  Acceptance: create works, reopening restores owned history and reuses runtime,
  invalid arguments cannot reach Ecto queries, foreign IDs disclose nothing, and
  startup failures are explicit. Implementation and writer checks: passed; independent
  verification: passed; work-unit commit: pending. Keep T1 unchecked until commit evidence exists.

## Verification and delivery

- TDD: **enabled**, source: supplied AGENTS strict-TDD marker. Observe RED → GREEN → REFACTOR.
- Focused runner (local test DB and localhost LLM stubs only):

```sh
mix test test/fullstack/jido_market_agents/conversation_start_test.exs test/fullstack/jido_market_agents/conversations_test.exs test/fullstack/jido_market_agents/conversation_rehydration_test.exs test/fullstack/jido_market_agents/conversation_persistence_test.exs test/fullstack_web/live/business_discovery_evaluate_test.exs
```

- Additional checks: scoped `mix format --check-formatted` and `git diff --check`.
- Runtime proof: focused context and LiveView tests; no external service or credential use.
- Branch: `ft-maestro-agents` (existing feature branch). Delivery: `ask-on-risk`; no push/PR.
- Original forecast: 220–330 authored source/test lines plus tracker. Current source/test
  delta: **344 authored lines**, excluding pre-existing dirty edits; committed count: 0.
  Total including this tracker exceeds 400; resolve delivery strategy before commit.
- RDD: **off**, parent observed `gentle-ai review mode status`, global deciding source.
  Native review is not started; ordinary verification and repository policy apply.
- Rollback: remove only this feature's hunks in the four scoped source/test files and
  this tracker, preserving pre-existing dirty changes.
- Writer verification evidence (exact focused runner above):
  - Initial test compilation failed on nonexistent `refute_patch/1`; corrected to installed `refute_patched/1`.
  - RED: exit 2, seed 492161, **63 tests, 14 failures**; missing API, malformed-ID and
    startup failures included three cascading failures from the linked LiveView crash.
    Added exit-safe test cleanup; no production changes preceded this RED.
  - Initial GREEN: exit 0, seed 522245, **63 tests, 0 failures**, after scoped formatting.
  - Ordering RED: exit 2, seed 392715, **64 tests, 1 failure**; history-query telemetry
    measured subscription as false. Return contract revised to record-only, restoring
    subscribe-before-history ordering rather than adding duplicate queries.
  - Final normalized GREEN: exit 0, seed 666538, **64 tests, 0 failures**.
  - Four-file `mix format`, scoped `mix format --check-formatted`, and `git diff --check`: exit 0.
- Existing fixtures emit persistence/SQL Sandbox noise and compiler warnings; no assertion failures remain.
- Independent verification: exact focused runner exit 0, seed 455003, **64 tests, 0 failures**;
  check-only formatting and scoped whitespace check: exit 0. No candidate-caused defects found.
- Native risk assessment unavailable: undeclared untracked-file inventory; treated as high/unassessable.
  RDD remains off; independent verification completed instead of launching review.
- Parent spot check: scoped git diff --check exit 0 after independent verification.
- Isolated staging and work-unit commit: pending; no staging/commit performed.

## Recovery and next step

Engram mirror `odd/conversation-start-validation/tasks`: **PENDING / UNAVAILABLE**.
No authoritative runtime identity is available; attributed memory writes and CLI
substitutes are forbidden. Local tracker is preserved; mirror must be synchronized
only after the host restores runtime registration.

Next: resolve delivery strategy, then isolate this
feature from existing dirty edits and record the work-unit commit before checking T1 complete.
