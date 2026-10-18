# Validator structured assessment

## Objective
Return an evidence-based completeness decision, structured collected data, missing fields, and a reusable next question from the Validator.

## Problem and scope
The extraction prompt requests fields only; its closed output contract and normalizer discard justification. Update the prompt, metadata retention, assessment API, and Conversation delivery without changing existing tuple APIs, domain fields, or completeness policy. Preserve all pre-existing dirty work, especially Conversation telemetry. No remote operations, migrations, UI redesign, or SDD artifacts.

## Constraints and routing
- Branch: `ft-maestro-agents`; preserve unrelated changes.
- Route: delegated direct. Mapping required more than three files; implementation spans non-trivial production and test files.
- Strict TDD: enabled by explicit user instructions. Observe RED before production edits, then GREEN and REFACTOR.
- RDD: globally off; do not enable or launch review.
- Delivery strategy: `ask-on-risk`. Forecast: approximately 300 authored changed lines; 400 is advisory, never a code-golf target.
- Engram mirror: PENDING. Runtime session identity is unavailable and attributed memory writes are prohibited.

## Tasks
- [ ] T1 — Add structured Validator assessment end to end, with prompt/context, separately retained factual model justification, deterministic sufficiency, merged data and missing fields, and complete/incomplete Conversation delivery. Include regression tests and one scoped Conventional Commit after verified checks.

## Acceptance criteria
- Assessment exposes `sufficient`, `data`, `missing_fields`, `justification`, and `next_question`; complete assessments have no next question.
- Model justification remains separate from business facts and cannot override completeness.
- Subsequent text calls see accumulated data; absent diagnosis values do not overwrite prior answers or manufacture explicit unknown answers.
- Explicit user unknown diagnosis answers retain existing answered semantics.
- Complete and incomplete extraction events expose assessment; existing extraction tuple API remains compatible.
- Extraction summary agrees with actual completeness.

## Checks
Focused runner: `mix test test/fullstack/jido_market_agents/agents/market_validator_test.exs test/fullstack/jido_market_agents/agents/extraction_output_test.exs test/fullstack/jido_market_agents/agents/backend_dispatch_test.exs test/fullstack/jido_market_agents/conversation_pipeline_test.exs test/fullstack/jido_market_agents_test.exs`

Regression runner: `mix test test/fullstack/jido_market_agents test/fullstack/jido_market_agents_test.exs`

Run scoped `mix format` before final verification; check with `mix format --check-formatted` on changed files. Tests use fake backends, not paid provider calls. Mix test alias creates/migrates the local test database.

## Progress and evidence
Implementation complete; T1 remains open until independent verification and the scoped work-unit commit.

- RED: focused runner observed 123 tests, 5 failures before production changes (missing assessment API, justification schema, and event payload).
- Additional regression RED: Validator and ExtractionOutput tests observed 34 tests, 6 failures before production changes, including initial assessment and preserved prior diagnosis context.
- GREEN: focused runner observed 125 tests, 0 failures.
- Writer regression runner: 414 tests, 0 failures.
- Parent structural readback found no correctness issue; parent spot check of Validator and ExtractionOutput tests passed 34 tests, 0 failures.
- Independent verification: initial full regression had 414 tests, 1 failure (ConversationRehydrationTest legacy six-field restart timed out at conversation_rehydration_test.exs:353, seed 419919). Targeted `mix test test/fullstack/jido_market_agents/conversation_rehydration_test.exs:288 --seed 419919` passed 1 test, 0 failures; full same-seed regression rerun passed 414 tests, 0 failures. The timeout's root cause and pre-existing status are unproven.
- RDD risk assessment was unassessable because the native command rejected unrelated undeclared untracked inventory. Independent verification was used; RDD remains off, with no review lifecycle.
- Scoped `mix format` and `mix format --check-formatted` completed; scoped `git diff --check` passed.
- Existing compiler warnings and intentional provider-crash test logs remain. Regression also logged SQL Sandbox owner-exit disconnects, with no test failures. Global diff whitespace warnings are confined to unrelated `.elixir-tools/next-ls.log`; that file was not edited by this feature.
- Runtime harness: fake-backend Conversation tests observed both complete/incomplete `:extraction_complete` assessments and reloaded the assistant metadata from the database. No real model/provider call was made; real-model prompt adherence is unverified.
- Feature source/test diff: 287 authored changed lines, excluding the 24-line pre-existing unrelated Conversation telemetry change. The new feature document is additional; no unrelated file is included.
- Engram mirror remains PENDING because no authoritative runtime session identity is available. No memory write was attempted.
- Work-unit commit: PENDING; RDD is disabled and no review lifecycle was launched.

## Usage and rationale
`MarketValidator.extract_fields(agent, message)` still returns `{:ok, updated_agent}`. Call `MarketValidator.assessment(updated_agent)` to receive `sufficient`, `data`, `missing_fields`, deterministic `justification`, separate untrusted `model_justification`, and `next_question` (nil when complete). The same report is present in extraction history, Conversation extraction events, and persisted assistant-message metadata. Next text turns receive only accumulated structured data and completeness context, never extraction history or model commentary.

The model extracts supporting facts and factual justification; deterministic domain rules own sufficiency. Absent diagnosis values do not invent explicit unknown answers. Explicit user unknown answers retain the existing completeness semantics.

Rollback boundary: remove only this feature's prompt/assessment/metadata/event additions and accompanying tests; retain unrelated existing Conversation edits.

Next step: parent independently verifies, excludes the pre-existing telemetry hunk from the feature commit, records its commit identity, and closes T1 only after the commit is verified.
