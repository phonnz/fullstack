# Fix validator extraction shape and persist the raw model reply

Make the validator's LLM reply reliably populate the extraction fields, fail loudly when
the reply shape is unrecognized, and keep the raw model reply per turn for diagnosis.

## Objective and scope

- The validator prompt and its prior-state context must lead the model to return the
  eleven extraction fields as top-level JSON keys.
- A reply that carries none of the eleven field keys must fail as a tagged parse error,
  never as a silent empty merge.
- Each validator assistant message stores the raw model reply in
  `metadata.raw_response` (decision: user, 2026-10-23, option 1 of 3; alternatives were a
  record column with a migration, or not storing it).
- Sufficiency stays application-owned (`MarketValidator.check_completeness/1`). The model
  never decides completeness; its justification stays untrusted metadata.
- Out of scope: researcher/analyzer/systems/strategy stages, the MiMo transport and its
  request wire contract, UI, the admin `/evaluations` screen, and storing the raw reply on
  failed turns.

## Problem and evidence

Live probe on 2026-10-23 (`mimo-v2.6-pro`, validator config `temperature: 0.3`,
`max_tokens: 1024`, `thinking: :disabled`) with the sample message:

> Mexico city, Mexico, Cutom carpets for the main saloon. Initial budget fort the busines
> 300 euros. The price for a carpet of 1.5 m x .30 m is 70 euros. Delivery in 2 weeks.

The model extracted every commercial field correctly but nested them:

```json
{"data": {"country": "Mexico", "city": "Mexico City", "business_market": "...", "initial_budget": "300 euros", "...": "..."},
 "sufficient": false, "missing_fields": ["team_size", "..."], "justification": "..."}
```

`ExtractionOutput.normalize_map/1` reads top-level keys only, so all eleven fields
normalized to `nil` and the assessment reported all ten required fields missing. Only
`justification` survived because it was top-level.

Causes:

1. The second system message in `MarketValidator.extract_fields/2` sends prior state as
   `{"sufficient", "data", "missing_fields"}`; the model mirrors that shape.
2. The MiMo adapter discards `ExtractionOutput.schema()` (`llm/mimo.ex`, `put_json_mode/2`),
   yet the prompt says "matching the supplied schema" and never shows the output shape.
3. No guard distinguishes "no recognized keys" from "user stated nothing new".

Counter-probe (scratchpad only, same message): an explicit top-level output shape in the
prompt plus prior state sent as `{prior_facts, still_missing}` labelled "not an output
template" produced all six commercial fields at top level; `normalize_map/1` filled them
and left the five diagnosis fields `nil`.

## Authorized files

- `lib/fullstack/jido_market_agents/agents/market_validator.ex`
- `lib/fullstack/jido_market_agents/conversation.ex` (`process_extraction/1` only)
- `test/fullstack/jido_market_agents/agents/market_validator_test.exs`
- `test/fullstack/jido_market_agents/conversation_pipeline_test.exs` or
  `conversation_persistence_test.exs` (raw reply persistence)
- This tracker

## Constraints and routing

- Branch: `ft-maestro-agents`. Preserve unrelated dirty work and never stage it:
  `llm/mimo_client.ex`, `llm/mimo_test.exs`, `config/config.exs`, `.iex.exs`,
  `test/fullstack/jido_market_agents_test.exs`, `odd/tasks/waitlist-landing-page.md`,
  `.atl/*`, and all untracked files except this tracker.
- Route: delegated direct for T1–T3 (writer trigger: two non-trivial production files plus
  tests). T4 runs in the parent as a bounded live check.
- Strict TDD: enabled (user global config). Runner: `mix test`. Observe RED before each
  production edit, then GREEN and REFACTOR.
- RDD: off (decided by global). No review ceremony.
- Delivery strategy: `ask-on-risk`. Forecast: about 200 authored changed lines, under the
  400-line budget; no slicing expected.
- Commits: one Conventional Commit per task, files staged by explicit path, no AI
  attribution trailer (user global rule).
- Live provider calls: authorized only for T4, with the sample message and user
  `1eb26e40-1602-40dc-8114-8fbbc0ef54c8`. Unit tests use fake backends.
- Logs carry no prompt text, response values, or credentials.
- Artifact language: English.

## Tasks

- [x] T1 — Prompt and prior-state context contract (`market_validator.ex`).
  Replace "matching the supplied schema" with an explicit top-level output shape listing
  the eleven field keys plus `justification`, `output_language`, and
  `language_switch_requested`; forbid wrapping fields in `data` or any other object and
  forbid emitting `sufficient` or `missing_fields`; require every field key, `null` when
  absent. Define `output_language` (language code of the latest user message) and
  `language_switch_requested` (true only on an explicit request to change reply
  language). Send prior state as `{"prior_facts": ..., "still_missing": [...]}` labelled
  as context only and not an output template, without `sufficient`.
- [ ] T2 — Unrecognized-shape guard (`market_validator.ex`).
  A decoded reply with none of the eleven field keys at top level returns
  `{:error, {:parse_failed, :unrecognized_shape}}` and leaves agent state unchanged. Emit
  one `Logger.warning` naming only the sorted top-level keys, never values. RED fixture:
  the exact `data`-envelope reply from the evidence above.
- [ ] T3 — Persist the raw reply per turn.
  The LLM path of `extract_fields/2` records the raw content as `raw_response` in its new
  extraction history entry (the map path records `nil`). Add
  `MarketValidator.last_raw_response/1`. `Conversation.process_extraction/1` adds
  `raw_response` to the assistant message metadata in both the complete and incomplete
  branches when non-nil; broadcasts stay unchanged. Prove the persisted `Message`
  carries it for an LLM turn and omits it for a map-input turn.
- [ ] T4 — Live verification with the sample message.
  (a) `MarketValidator.extract_fields/2` fills the six commercial fields and reports the
  five diagnosis fields missing. (b) `Conversations.start_or_resume/3` with the sample
  user persists an assistant message whose `metadata["raw_response"]` holds the reply and
  whose record `validated_data` holds the commercial fields.

## Acceptance criteria

- With the sample message, the commercial fields are populated and only the five
  diagnosis fields are missing.
- A `data`-envelope reply yields `{:error, {:parse_failed, :unrecognized_shape}}`; prior
  state is unchanged.
- Validator assistant messages carry `metadata["raw_response"]` for LLM turns only.
- `check_completeness/1`, `assessment/1` keys, the map fast path, and broadcast payloads
  are unchanged.
- No log line includes prompt text, response values, or credentials.

## Checks

Focused: `mix test test/fullstack/jido_market_agents/agents/market_validator_test.exs test/fullstack/jido_market_agents/conversation_pipeline_test.exs test/fullstack/jido_market_agents/conversation_persistence_test.exs`

Regression: `mix test test/fullstack/jido_market_agents test/fullstack/jido_market_agents_test.exs`
(baseline 2026-10-23 before T1: 420 tests, 0 failures).

Format: `mix format --check-formatted` on changed files.

## Progress and evidence

- 2026-10-23: exploration, live probe, and counter-probe recorded above. Tracker created.
- 2026-10-23 T1 (delegated writer, route: delegated direct, trigger: writer rule). Strict TDD,
  runner `mix test`. Baseline focused set: 50 tests, 0 failures.
  - RED: after adding five prompt/context tests and updating the `Accumulated assessment`
    assertion, `market_validator_test.exs` ran 18 tests, 6 failures: the prompt still said
    "matching the supplied schema" and had no output shape, no wrap/`sufficient` prohibitions
    and no language-key definitions; the second system message was still the
    `Accumulated assessment` `{data, sufficient, missing_fields}` payload.
  - GREEN: focused command (market_validator + conversation_pipeline +
    conversation_persistence tests): 55 tests, 0 failures. `mix format --check-formatted` on the
    two changed files: clean.
  - Prior state is now `{"prior_facts": <known facts only>, "still_missing": [...]}`, labelled
    context only and not an output template; `sufficient` is not sent.
  - Commit: `fix(validator): state the extraction output shape and send prior state as context`.

## Next step

T2 (unrecognized-shape guard).
