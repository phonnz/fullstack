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
- [x] T2 — Unrecognized-shape guard (`market_validator.ex`, LLM parse path only).
  Decided by the user on 2026-10-23 (option 3 of 3, generalized). A decoded reply with no
  top-level key from the eleven fields AND at least one top-level key outside the metadata
  set `justification`, `output_language`, `language_switch_requested` returns
  `{:error, {:parse_failed, :unrecognized_shape}}` and leaves agent state unchanged. `{}`,
  a justification-only reply, a language-only reply, and field keys plus unknown extras
  stay valid "no new facts" or normal replies. Emit one `Logger.warning` naming only the
  sorted top-level keys, never values, prompt text or raw content. RED fixture: the exact
  `data`-envelope reply from the evidence above. `ExtractionOutput.normalize_map/1` and the
  map fast path are unchanged.
- [x] T3 — Persist the raw reply per turn.
  The LLM path of `extract_fields/2` records the raw content as `raw_response` in its new
  extraction history entry (the map path records `nil`). Add
  `MarketValidator.last_raw_response/1`. `Conversation.process_extraction/1` adds
  `raw_response` to the assistant message metadata in both the complete and incomplete
  branches when non-nil; broadcasts stay unchanged. Prove the persisted `Message`
  carries it for an LLM turn and omits it for a map-input turn.
- [x] T4 — Live verification with the sample message.
  (a) `MarketValidator.extract_fields/2` fills the six commercial fields and reports the
  five diagnosis fields missing. (b) `Conversations.start_or_resume/3` with the sample
  user persists an assistant message whose `metadata["raw_response"]` holds the reply and
  whose record `validated_data` holds the commercial fields.
- [x] T5 — Rejection log names only known keys (`market_validator.ex`).
  Added 2026-10-23 after a proposal accepted by the user (option 4 of 5). Evidence: the
  `inspect(limit: 20, printable_limit: 64)` caps bound size, which Logger's default
  truncation (about 8 KB, no `:truncate` config in this project) and the 1024-token reply
  budget already bound, but they log a model-authored key under 64 characters verbatim,
  which breaks the "no response values in logs" invariant. Replace the caps with an
  allowlist: log only top-level key names from a fixed set (the eleven field keys, the
  three metadata keys, and the observed wrapper keys `data`, `sufficient`,
  `missing_fields`), sorted, plus `unknown_key_count=N` for every other key. Remove the
  numeric caps. The observed `data`-envelope line keeps its key list and gains
  `unknown_key_count=0`.

## Acceptance criteria

- With the sample message, the commercial fields are populated and only the five
  diagnosis fields are missing.
- An LLM reply wrapped in any unrecognized shape (for example a `data` envelope or a
  `result` wrapper: no field key at top level, plus at least one non-metadata key) yields
  `{:error, {:parse_failed, :unrecognized_shape}}`; prior state is unchanged. `{}`,
  metadata-only replies, and field keys plus unknown extras stay valid.
- Validator assistant messages carry `metadata["raw_response"]` for LLM turns only.
- `check_completeness/1`, `assessment/1` keys, the map fast path, and broadcast payload
  keys are unchanged. Accepted deviation (T3): `payload.messages` carries the assistant
  message with its `metadata.raw_response`, as it already carries `assessment`; it stays
  server-side because the LiveViews render `content` only.
- No log line includes prompt text, response values, or credentials.
- The rejection log names only allowlisted keys (the eleven fields, the three metadata
  keys, and the wrapper keys `data`, `sufficient`, `missing_fields`) plus
  `unknown_key_count=N`; any other model-authored key is counted, never printed.

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
- 2026-10-23 T2 BLOCKED (decision gap, not changed). Applying the specified guard (no top-level
  field key, so `{:error, :unrecognized_shape}`) as a scratch experiment, reverted before any
  commit, made existing tests fail because they accept a reply with zero field keys as "no new
  facts": `market_validator_test.exs` "output language capture" (the `explicit switch` fake
  reply is only `output_language` plus `language_switch_requested`),
  `facade_send_message_test.exs:92` (stub reply `{}`, expects `extraction_complete`), and
  `jido_market_agents_test.exs:542` "empty JSON preserves previous fields" (reply `{}`; this is
  a dirty file outside the authorized set). `conversation_pipeline_test.exs:614` also failed
  once in that broad run but passes alone, so it is timing flakiness unrelated to the guard.
  T2 needs a parent decision on the rule before any production edit.
- 2026-10-23 T3 (delegated writer, independent of T2). Strict TDD, runner `mix test`.
  - RED: after adding three validator tests and four pipeline tests, the focused set ran 61
    tests, 4 failures: `MarketValidator.last_raw_response/1` undefined (2) and
    `metadata["raw_response"]` absent from the persisted assistant message in the incomplete
    and complete branches (2). The map-turn and no-leak guards passed already, as expected.
  - GREEN: focused command 62 tests, 0 failures (one extra pipeline test, the map turn after
    an LLM turn does not inherit the previous reply, was added after GREEN as a regression
    guard and has no separate RED). Regression command
    (`test/fullstack/jido_market_agents` plus `jido_market_agents_test.exs`): 432 tests,
    0 failures (baseline 420 + 12 new). `mix format --check-formatted` on the four changed
    files: clean.
  - Stale-reply check: `process_extraction/1` has two callers (map input right after
    `extract_fields/2`, and the validator task result), and every successful
    `extract_fields/2` appends its own history entry last, so `last_raw_response/1` is the
    current turn's reply or `nil`.
  - Note: `broadcast/3` sends `state.messages`, so `payload.messages` now carries the assistant
    message with `metadata.raw_response`, like `assessment` already does. No dedicated payload
    key was added and the LiveViews render `content` only. Stripping it from the broadcast
    would require editing `broadcast/3`, outside the authorized files.
  - Commit: `feat(validator): persist the raw model reply on validator assistant messages`.
- 2026-10-23 parent spot check: regression command re-run, 432 tests, 0 failures. Commits
  `b78a175` and `f0fa061` contain only authorized files and no attribution trailer; the
  unrelated dirty files are untouched.
- 2026-10-23 T4 (parent, live MiMo `mimo-v2.6-pro`, sample message, PORT=4011).
  - (a) `extract_fields/2` returned a flat top-level reply; the six commercial fields
    were filled (country Mexico, city Mexico City, budget "300 euros", price "70 euros per
    carpet of 1.5 m x 0.30 m") and `missing_fields` was exactly the five diagnosis fields.
    `last_raw_response/1` returned the reply.
  - (b) `Conversations.start_or_resume/3` for user `1eb26e40-…` created conversation
    `e7b8e17b-73f7-44d9-b20c-db32d1659965`. The persisted assistant message has metadata
    keys `assessment` and `raw_response` (flat JSON reply); the record is `active` and its
    `validated_data` holds the six commercial fields with the diagnosis fields `nil`. The
    pipeline stopped at the validator, as expected for incomplete data.
- 2026-10-23 T2 (delegated writer). Decision source: the user chose option 3 of 3 (reject only
  a reply that has no field key and some non-metadata key), relayed by the coordinator. Strict
  TDD, runner `mix test`.
  - RED: after adding five tests in `market_validator_test.exs` (observed `data`-envelope
    reply, a `result` wrapper, a bounded-key-list check, the stay-valid metadata-only replies,
    and field keys plus extras), the file ran 26 tests, 3 failures. The three rejection tests
    got `{:ok, _}` back with every field silently `nil`, instead of
    `{:error, {:parse_failed, :unrecognized_shape}}`. The two stay-valid guards passed already.
    (A first run showed a fourth failure that was a bug in the new test, now fixed: a fresh
    agent has no `:country` key.)
  - GREEN: focused command 67 tests, 0 failures. Regression command
    (`test/fullstack/jido_market_agents` plus `jido_market_agents_test.exs`): 437 tests,
    0 failures (432 + 5). `conversation_pipeline_test.exs:614` did not fail in this run.
    `mix format --check-formatted` on the two changed files: clean.
  - The warning is `Validator reply rejected: :unrecognized_shape top_level_keys=[...]` with
    sorted keys; the list is bounded (`limit: 20`, `printable_limit: 64`) so a hostile or
    malformed reply cannot flood the log. The three tests that conflicted with the first
    version of the rule (`{}` and language-only replies) pass unchanged.
  - Commit: `fix(validator): reject extraction replies wrapped in an unrecognized shape`.
- 2026-10-23 T5 (delegated writer). Accepted by the user (option 4 of 5). Strict TDD, runner
  `mix test`.
  - RED: after updating the exact-line envelope test to expect `unknown_key_count=0`, adding
    a test for `{"Mexico City": {"country": "Mexico"}}`, and updating the long-keys test to
    expect `unknown_key_count=30`, `market_validator_test.exs` ran 27 tests, 4 failures. The
    new test showed the model-authored key `"Mexico City"` logged verbatim in the old
    `top_level_keys=[...]` list, and the other three lacked `unknown_key_count`. The
    existing `result` wrapper test also had to change: it asserted
    `top_level_keys=["result"]`, and `result` is not an allowlisted name, so it now expects
    `top_level_keys=[] unknown_key_count=1` (it was the fourth failure).
  - GREEN: focused command 68 tests, 0 failures. Regression command
    (`test/fullstack/jido_market_agents` plus `jido_market_agents_test.exs`): 438 tests,
    0 failures (437 + 1). `mix format --check-formatted` on the two changed files: clean.
  - `limit: 20, printable_limit: 64` are removed and no other numeric cap was added. The
    accept/reject decision is unchanged; only the logged text differs.
  - Commit: `fix(validator): log only allowlisted key names when rejecting a reply`.

## Next step

All tasks (T1-T5) are done. The next step is a delivery decision for the user: push the
branch and open a pull request, or hold. Nothing has been pushed.
