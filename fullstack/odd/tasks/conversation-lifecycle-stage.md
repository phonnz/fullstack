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

- Q1: Does `ready` wait for an explicit user action before research starts, or does
  automatic mode keep moving straight to `research` as today? Blocks T2.
- Q2: A user message at `research` or later: reject it (`{:error, :conversation_locked}`,
  nothing stored) or store it as chat only? Blocks T3.

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
- [ ] T2 — Pipeline writes the stage (slice 2). Blocked on Q1. Intake moves `inserted` to
  `validating`; a complete validation moves to `ready`; each stage start moves to its
  phase; tech strategy success moves to `delivered`. All writes go through the existing
  locked persistence paths. Rehydration restores `stage` and never resumes behind it.
- [ ] T3 — Message gating (slice 3). Blocked on Q2. `drain_queue` processes a user message
  only when `Lifecycle.accepts_messages?/1`; the `error`-reset retry applies only before
  `research`.
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
- Delivery: `ask-on-risk`. Forecast about 700-900 authored changed lines over four
  slices, above the 400-line budget, so each task is one pull request slice. The chain
  strategy (`stacked-to-main` or `feature-branch-chain`) is asked before the first pull
  request; nothing is pushed without the user.
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
  - Native assessment: risk `medium`, RDD off, so writer self-verification plus parent
    spot check.

## Next step

Q1 is asked (blocks T2). Commit identity for T1 is recorded in the next update.
