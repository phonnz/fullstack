# Conversation lifecycle stage

Give each market discovery conversation one forward-only lifecycle field:
`inserted -> validating -> ready -> research -> proposal -> strategy -> delivered`.

## Objective and scope

- Add `stage` to `jido_conversations` as the single lifecycle source (option C, chosen by
  the user on 2026-10-23). `status` keeps its current values until a later slice narrows
  it to run health (`idle | running | error`).
- Only the seven stage values can be stored, enforced by `Ecto.Enum` and a native
  Postgres enum.
- From `research` onward the stage never moves backward, enforced by one pure transition
  table in the application and by a database trigger.
- While the stage is `inserted`, `validating`, or `ready`, new user messages update the
  collected data. User decision (2026-10-23): retries through new messages happen only
  before `research`, and nothing else retries a stage.
- Out of scope: the validator prompt work (tracked in `validator-extraction-shape.md`),
  UI redesign, and new pipeline stages.

## Problem and evidence

Mapped 2026-10-23 (read-only exploration, verified in code):

- `status` is a varchar column with default `active` and no database check
  (`priv/repo/migrations/20260925120000_create_jido_conversations.exs`). Its only guard
  is `validate_inclusion` over `active researching analyzing building_strategy completed
  error` (`conversations/record.ex`). It mixes lifecycle position and run health.
- The lifecycle is a loop today. Every drained user message resets `status` to `:active`
  and `pending_stage` to `nil` (`conversation.ex`, `drain_queue`). A complete validation
  always re-runs research and wipes later results (`stage_invalidated`). A message after
  `error` resets it to `active`.
- `status` gates little: only `error` and `completed` change rehydration behavior;
  `conversations/step.ex` checks `"error"`. Broadcast `status:` atoms (including
  `:needs_data`) are a separate wire contract matched by `business_discovery/evaluate.ex`.
  About 97 test lines in 10 files pin current status values.
- Project convention for enums: native Postgres enum types with `Ecto.Enum`
  (`user_role` in `20261004150000_add_user_role.exs`, `transaction_status`). Postgres
  enum values compare in declaration order.
- Stage commits already run under a `FOR UPDATE` row lock with a `boundary_version`
  compare-and-set (`Conversations.persist_stage_transition/4`).

## Decisions

- Option C: new `stage` field, `status` untouched in early slices (user, 2026-10-23).
- Stage mapping (proposed, not contradicted): pipeline `research` -> `research`,
  `analysis` -> `proposal`, `systems` and `tech_strategy` -> `strategy`, tech strategy
  finished -> `delivered`. `stage` names the phase the conversation is in or about to
  run, matching how `status` advances today when a stage commits.
- Transition table (application): the next adjacent stage only; staying on the same stage
  is a no-op and always allowed; `delivered` is terminal; skipping is invalid.
- Database guard: a `BEFORE UPDATE OF stage` trigger rejects `NEW.stage < OLD.stage`
  when `OLD.stage >= 'research'`, raised as a named check violation so Ecto can map it.
- Retries: new messages re-run validation only before `research`. A stage that fails at
  `research` or later is not retried by any mechanism (user, 2026-10-23). Resuming an
  interrupted stage after a process restart is continuation, not a retry, and never
  moves the stage backward.

## Open questions (ask one at a time)

- Q1 (resolved, user 2026-10-23): automatic. `ready` moves straight to `research` as
  today; no user action gates research.
- Q2 (resolved, user 2026-10-23): a user message at `research` or later is stored as a
  chat message and never re-runs the pipeline (no validation, no stage, no status reset).

## Tasks

- [x] T1 — Stage field, enum, transition table, and database guards (slice 1).
  Route: delegated direct (writer trigger: migration, schema, new module, tests).
  - Pure module `Fullstack.JidoMarketAgents.Conversations.Lifecycle`: ordered stages,
    `transition(from, to)` returning `:ok` or `{:error, {:invalid_transition, from, to}}`,
    and `accepts_messages?(stage)` (true only before `research`).
  - `Record`: `field :stage, Ecto.Enum` with the seven values in order, default
    `:inserted`; not castable through `changeset/2`; a `stage_changeset/2` that validates
    through `Lifecycle.transition/2` and maps the trigger's named check violation.
  - Migration: create the `conversation_stage` type, add `stage` (not null, default
    `inserted`), backfill existing rows, create the forward-only trigger; reversible.
  - Backfill rules, first match wins: `status = 'completed'` or `tech_strategy` present
    -> `delivered`; `systems_strategy` or `business_analysis` present -> `strategy`; a
    `market_research` message exists -> `proposal`; the ten required fields are all
    present in `validated_data` and `status` is `researching` or `error` -> `research`;
    the ten required fields are all present -> `ready`; any user message exists ->
    `validating`; otherwise `inserted`.
- [x] T2 — Pipeline writes the stage (slice 2). Intake moves `inserted` to
  `validating`; a complete validation moves to `ready`; each stage start moves to its
  phase; tech strategy success moves to `delivered`. All writes go through the existing
  locked persistence paths. Rehydration restores `stage` and never resumes behind it.
  Route: delegated direct (preparation trigger: `conversation.ex` and persistence paths).
  - Advance-only writes: a stage write happens only when the target is the next adjacent
    stage; a target at or behind the current stage is a no-op, never an error. Until T3
    gates messages, a message at `research` or later still re-runs the old loop, but
    `stage` stays where it is instead of hitting the trigger.
  - No new broadcast contract and no UI change in this slice.
- [x] T3 — Message gating (slice 3). `drain_queue` processes a user message through
  validation only when `Lifecycle.accepts_messages?/1`; the `error`-reset retry applies
  only before `research`. Route: delegated direct (preparation trigger: `conversation.ex`).
  - At `research` or later a user message is persisted and broadcast like any chat
    message, then nothing else happens: no validator run, no `status` or `pending_stage`
    reset, no result wipe, no stage change. A running stage is not interrupted.
  - Chat-only messages must not change pipeline inputs: not replayed into the validator
    on rehydration, not part of stage input fingerprints, not fed to later stage prompts.
    Mark them so every reader can tell them apart.
  - At `research` or later with `status` error, a message is stored and the error stays;
    nothing retries the failed stage.
  - Paths made unreachable by the gate (for example `stage_invalidated` after research)
    are reported, not removed, in this slice.
- [ ] T4 — Narrow `status` to run health (slice 4). Planned later; needs its own mapping
  review of every reader before starting.

## Acceptance criteria

- Writing a value outside the seven stages fails at the changeset and at the database.
- A backward stage change from `research` or later fails through `stage_changeset/2` and
  through `Repo.update_all`; backward changes before `research` are not blocked by the
  trigger.
- The backfill assigns every existing row a stage according to the rules above.
- The migration rolls back cleanly.
- Existing behavior and status values are unchanged in slice 1; the full suite stays
  green.

## Constraints and routing

- Branch: `ft-conversation-lifecycle`, created from `ft-maestro-agents` at `bf53cfd`
  (the validator work it builds on is not pushed). Preserve unrelated dirty work; stage
  files by explicit path only.
- Strict TDD: enabled (user global config). Runner: `mix test`.
- RDD: off (decided by global).
- Delivery: `ask-on-risk`, chain strategy `feature-branch-chain` (user, 2026-10-23).
  Each task is one child pull request slice; nothing is pushed without the user.
  - Tracker (integration, draft/no-merge PR to `main`): `ft-conversation-lifecycle` at
    `bf53cfd`. Its PR also carries the unpushed `ft-maestro-agents` validator commits
    unless that branch lands on `main` first.
  - Slice 1 (T1): `ft-conversation-lifecycle-01-stage-field`, base the tracker, commit
    `4233ae1`.
  - Slice 2 (T2): `ft-conversation-lifecycle-02-pipeline-stage`, base slice 1, commit `4fd46c5`.
  - Slice 3 (T3): `ft-conversation-lifecycle-03-message-gating`, base slice 2.
  - Slice 4 (T4): `ft-conversation-lifecycle-04-status-health`, base slice 3.
- Migrations run only against the test database. The dev database is migrated by the
  user (`mix ecto.migrate`), never by an agent.
- Commits: Conventional Commits, no AI attribution trailer.
- Artifact language: English.

## Checks

Focused: `mix test test/fullstack/jido_market_agents/conversations_schema_test.exs test/fullstack/jido_market_agents/conversations_test.exs` plus new lifecycle tests.

Regression: `mix test test/fullstack/jido_market_agents test/fullstack/jido_market_agents_test.exs test/fullstack_web` (baseline to be recorded before T1).

Format: `mix format --check-formatted` on changed files.

## Progress and evidence

- 2026-10-23: exploration mapped, plan accepted with option C, retry rule decided.
  Tracker created.
- 2026-10-23: regression baseline at `bf53cfd` plus unrelated dirty work: 631 tests,
  7 failures, all pre-existing and outside the lifecycle: `FullstackWeb.GroupChannelTest`
  (3), `FullstackWeb.PageControllerTest` "GET /", `FullstackWeb.ChatLiveTest` "page shell
  has no inline style attributes", `FullstackWeb.TransactionLiveTest` (2). Flaky:
  `ConversationPipelineTest` "stage error persists and broadcasts once without retry or
  descendant scheduling" (failed once, passed on rerun).
- 2026-10-23: T1 started, delegated to one writer.
- 2026-10-23: T1 done (route: delegated direct). Files: `conversations/lifecycle.ex`,
  `conversations/record.ex`, migration `20261023120000_add_stage_to_jido_conversations`,
  `conversations/lifecycle_test.exs` (8), `conversations_stage_test.exs` (24).
  - TDD: lifecycle RED observed (8/8 failing, module undefined), then GREEN. Schema,
    trigger, and backfill: RED was a compile failure of the whole test file (`unknown key
    :stage`), not one RED per test; GREEN 24/24.
  - Checks: focused 74 tests, 0 failures (re-run by parent); regression 663 tests, 7
    failures, exactly the baseline set; rollback and re-migrate on the test DB clean;
    format clean on all five files. `mix compile --warnings-as-errors` fails only on
    pre-existing warnings in unrelated files (parent confirmed none from the new files).
  - Backfill as built: "present" means key exists, not JSON null, not `''` (matches
    `MarketValidator.missing?/2`); research messages match `metadata->>'type' =
    'market_research'`, superseded ones included. Ten fields: five commercial
    (`country business_market initial_budget final_product_proposal product_price`) plus
    the five `ExtractionOutput.diagnosis_fields/0`.
  - Commit `4233ae1`. Native assessment: risk `medium`, RDD off, so writer self-verification plus parent
    spot check.
- 2026-10-23: chain strategy `feature-branch-chain` chosen. T1 moved to its slice branch
  (`ft-conversation-lifecycle-01-stage-field`); the tracker branch pointer reset to
  `bf53cfd` (local only, nothing was pushed).
- 2026-10-23: T2 implemented, verified, and committed on
  `ft-conversation-lifecycle-02-pipeline-stage` as `4fd46c5`. Route: delegated direct. Native assessment on the commit: risk `medium` (`slice_budget_reached`), RDD off, so writer self-verification plus parent spot check.
  - Writes: `drain_queue` -> `:validating`; complete validation (`commit_validation`) ->
    `:ready`; `start_stage` -> phase via `stage_phase/1`; `tech_strategy` success ->
    `:delivered` inside `persist_stage_transition` (row lock plus `boundary_version`
    check). Boundary writes ride `persist_owned_boundary`, which runs in a transaction
    but does not take `FOR UPDATE`; single-owner GenServer writes keep it safe today.
    All writes go through `Conversations.advance_stage/3` and `Lifecycle.advance/2`.
  - Skip targets (only seen with fixtures created at `:inserted` that resume at
    analysis) log a warning and write nothing; the boundary still commits.
  - Rehydration copies `record.stage` and never resumes a pipeline stage whose phase is
    behind it (`maybe_enqueue_resume`); `resume_point` only yields the four pipeline
    stages, so `stage_phase/1` is total there (parent checked).
  - User-less conversations (`user_id: nil`) keep `:inserted` in memory; nothing persists.
  - TDD: RED observed per group (lifecycle 4 failing `UndefinedFunctionError`; pipeline
    7/7 failing on stale `:inserted`; rehydration `KeyError :stage`), then GREEN.
  - Checks: focused six files 126 tests, 0 failures (parent re-run); regression 677
    tests, 7 failures, exactly the baseline set; format clean; no compile warning from
    touched files.
  - More flaky tests, pre-existing (failed 2 of 12 runs with T2 stashed):
    `ConversationPipelineTest` "an incomplete LLM turn persists the raw reply..." and
    "worker failure is contained and terminal"; both read `List.last(list_messages)`
    and `inserted_at` has one-second resolution.
- 2026-10-23: T3 implemented, verified, and committed on
  `ft-conversation-lifecycle-03-message-gating`. Route: delegated direct (writer
  interrupted once by a usage limit and resumed), plus one inline parent fix.
  - Gate: `Lifecycle.accepts_messages?(state.stage)` in `handle_call({:send_message, ..})`
    (a closed gate stores at once, even while a stage task runs) and in `:drain_queue`
    (a message queued before research and drained after it). Open gate keeps the old
    body, now `admit_user_message/2`.
  - Chat-only messages: role `user`, `metadata.type = "chat_only"`, persisted through
    `persist_owned_boundary/2` with no stage target (same `boundary_version`, so a running
    stage's commit check still matches), then broadcast as `:message_received` with no
    `status:`.
  - Readers checked, none changed: validator rehydration uses `validated_data` only;
    fingerprints use data, results, language, and `stage_refinement` messages; stage
    prompts use data and result maps; research/result lookups filter by
    `metadata["type"]`.
  - Parent inline fix: `Evaluate` handles `:message_received` (replace transcript, phase
    `:idle`). Without it the "Thinking..." indicator set on submit never cleared, since
    no pipeline event follows a chat-only message. Tradeoff: a chat message sent while a
    stage runs clears the "researching" indicator until that stage's event arrives.
  - Existing tests changed for Q2: the two T2 interim loop tests (replaced); "changed
    facts publish committed invalidation..." (now: results kept, no invalidation);
    "blocked provider keeps reads admission..." (mid-research turn stored as chat);
    rehydration "legacy six-field ... waits for missing diagnosis" (post-research message
    expects `message_received`, waits for `research_complete` before the kill).
  - Unreachable now, reported not removed: `commit_validation` with `changed == true`
    (result wipe, `rebuild_analysis_agents(results: %{})`, `:stage_invalidated`
    broadcast and its `invalidated: @stages` payload). Manual-mode
    `__pipeline_request__` messages after research are stored as chat too; stages after
    research run through `run_stage`, so only stray validator requests are affected.
  - TDD: six new pipeline/rehydration gating tests RED ("no matching message" for
    `:message_received`), two before-research tests passed on old code as guards, then
    GREEN; Evaluate test RED (`refute html =~ "phase-buffering"`), then GREEN 25/25.
  - Checks: regression 683 tests, 7 failures, exactly the baseline set (parent run);
    format clean on all five files; no compile warning from touched files.
  - More pre-existing flakes (same one-second ordering): `ConversationPipelineTest`
    "successful pipeline emits the five adopted events..." and "a map turn after an LLM
    turn does not inherit the previous raw reply".

## Next step

Decide between T4 (narrow `status` to run health, needs its own reader mapping first)
and a small cleanup slice removing the paths T3 made unreachable.
