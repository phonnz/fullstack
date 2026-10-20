# Restore reliable MiMo business-data extraction

Disable thinking for validator extraction and correctly parse MiMo's final JSON answer.
Verify the user's carpet-business message, including an explicit market, at 1x and 5x length.

## Objective and scope

- Fix empty/invalid extraction handling without treating it as missing business data.
- Preserve ownership, conversation persistence, other providers, and researcher behavior.
- Authorized: MiMo client/adapter, validator role configuration, MarketValidator parser,
  their focused tests, and this tracker. No UI, schema, dependency, or unrelated dirty edits.
- No live API calls or ambient credentials: remote destination and credential use are
  not authorized. Local HTTP-stub evidence must not be presented as live generation.
- Artifact language: English. Preserve all other working-tree changes.

## Work unit

- [x] **T1 — Make validator extraction deterministic and parse final JSON reliably.**
  Route: delegated direct; writer/preparation triggers (multiple non-trivial files).
  1. Observe failing regressions before implementation (strict TDD).
  2. Disable thinking for validator extraction; use the documented completion-token
     wire parameter while preserving the internal backend options contract.
  3. Parse plain and fenced JSON; return explicit errors for empty/null, malformed,
     non-object, and truncated responses rather than consuming reasoning as an answer.
  4. Add the explicit business market to the test message; exercise 1x and 5x input
     through the transport/parser/completeness boundary with local stub responses.
  5. Run focused verification, independent verification if native risk requires it,
     and commit only this work unit with its tests and this tracker.

## Test message

Mexico city, Mexico, Cutom carpets for the main saloon. Initial budget fort the busines
300 euros. The price for a carpet of 1.5 m x .30 m is 70 euros. Delivery in 2 weeks.
Business market: custom home furniture.

## Acceptance and checks

- Validator sends explicit disabled thinking and JSON-object mode; researcher remains
  unchanged unless sharing the corrected token-parameter spelling.
- Plain/fenced JSON produce complete data when all five required fields are present;
  missing business_market produces incomplete; provider failures remain errors.
- 5x input reaches the local stub intact. Record character/byte lengths and distinguish
  input/context capacity from output-token budget; do not invent exact token counts.
- TDD: enabled; source: session Strict TDD Mode marker. Runner: focused ExUnit via
  mix test where available, otherwise the previously demonstrated current-source
  in-memory ExUnit harness without app/database startup. Preserve exact commands.
- Scoped mix format --check-formatted and git diff --check.
- Parent spot check and applicable independent check before delivery.
- Runtime proof: local HTTP-stub integration only; live MiMo generation pending consent.

## Delivery and recovery

- Branch: ft-maestro-agents. Base: 936337f.
- Forecast: approximately 250-350 authored changed lines, excluding unrelated changes.
- Strategy: ask-on-risk; no push or PR. One coherent work-unit commit.
- RDD: off, global deciding source (observed this session); no receipt review.
- Rollback: revert this unit's MiMo wire handling, parser, and focused regressions together.
- Engram topic: odd/mimo-extraction-response/tasks. Mirror pending: runtime session
  identity unavailable; agent-attributed memory writes are prohibited.
- Progress: T1 complete; writer, parent spot check, and independent checks passed; committed as 1efab9d.
- Next step: restart the running Phoenix application to load validator configuration; live MiMo verification needs explicit destination/credential authorization.
- Commit evidence: 1efab9d, fix(mimo): restore reliable business-data extraction; 348 additions and 25 deletions (373 authored lines including this tracker).

## Implementation and observed evidence

- Validator role now configures `thinking: :disabled`; the MiMo adapter validates
  and forwards explicit modes. Researcher still omits thinking and keeps its default.
- Internal `:max_tokens` remains unchanged; only MiMo HTTP spelling changes to
  `max_completion_tokens`. Output limit stays 1,024; this is not an input limit.
- Final answer must be nonblank text. Empty/null/non-text or truncated responses
  return tagged errors with bounded finish reason and numeric token counts only.
  Reasoning is never parsed as the answer, and raw prompt/response debug logs are removed.
- Plain or enclosing fenced JSON is decoded once; malformed/non-object JSON remains
  an explicit parse failure. Completeness still requires the same five business fields.
- Fixture uses the original message plus ` Business market: custom home furniture.`.
  1x: **212 characters / 212 bytes**; exact 5x via `String.duplicate(message, 5)`:
  **1,060 characters / 1,060 bytes**, no separators. Both plain and fenced canned
  responses are complete; omission of business_market is genuinely incomplete.
- Strict TDD: RED **54 tests, 10 failures (28 excluded)** before source edits;
  GREEN **54 tests, 0 failures (28 excluded)** before and after normalization.
  Existing unused subscriber_pid warning remains unrelated.
- Normal Mix test invocation was not run: its alias creates/migrates a database and
  starts the complete application. The direct runner below exercises the focused
  source and HTTP boundary without unrelated infrastructure or live API access.
  The 28 conversation/research integration tests remain unrun in this task.
- Scoped `mix format --check-formatted` and scoped `git diff --check`: passed.
  Whole-tree `git diff --check` reports existing trailing whitespace in unrelated
  `.elixir-tools/next-ls.log`; that file is outside this unit.
- No live MiMo call, provider cost/context-limit measurement, push, or PR occurred.
  Local canned output proves transport/parser/completeness behavior, not model generation.

### Reproduce focused checks

Run from the Phoenix app root with existing compiled test dependencies:

```sh
elixir -pa '_build/test/lib/*/ebin' -e '
Code.compiler_options(ignore_module_conflict: true)
for path <- ["llm/backend.ex", "llm.ex", "llm/mimo_client.ex", "llm/mimo.ex", "agents/extraction_output.ex", "agents/market_validator.ex"], do: Code.compile_file("lib/fullstack/jido_market_agents/" <> path)
{:ok, _} = Application.ensure_all_started(:mix)
{:ok, _} = Application.ensure_all_started(:req)
{:ok, _} = Application.ensure_all_started(:bandit)
Logger.configure(level: :warning)
System.put_env("MIMO_API_KEY", "local-test-key")
System.put_env("MIMO_BASE_URL", "http://127.0.0.1:1/v1")
config = Config.Reader.read!("config/config.exs", env: :test)
Application.put_env(:fullstack, Fullstack.JidoMarketAgents, config[:fullstack][Fullstack.JidoMarketAgents])
ExUnit.start(autorun: false)
Code.require_file("test/fullstack/jido_market_agents_test.exs")
Code.require_file("test/fullstack/jido_market_agents/llm/mimo_test.exs")
excluded = for test <- Fullstack.JidoMarketAgentsTest.__ex_unit__().tests, not String.starts_with?(to_string(test.tags[:describe]), ["MarketValidator", "MimoClient"]), do: {:test, Atom.to_string(test.name)}
ExUnit.configure(exclude: excluded)
owner = self()
output = ExUnit.CaptureIO.capture_io(fn -> send(owner, {:test_stats, ExUnit.run()}) end)
receive do
  {:test_stats, stats} ->
    IO.inspect(stats, label: "Focused offline tests (no app/DB/live API)")
    if stats.failures > 0 do
      output |> String.split("\n") |> Enum.filter(&Regex.match?(~r/(^\s+\d+\)|^\s+(code:|left:|right:|test\/)|\d+ tests, \d+ failures)/, &1)) |> Enum.each(&IO.puts/1)
      System.halt(1)
    end
end
'
mix format --check-formatted config/config.exs lib/fullstack/jido_market_agents/llm/mimo_client.ex lib/fullstack/jido_market_agents/llm/mimo.ex lib/fullstack/jido_market_agents/agents/market_validator.ex test/fullstack/jido_market_agents_test.exs test/fullstack/jido_market_agents/llm/mimo_test.exs
git diff --check -- config/config.exs lib/fullstack/jido_market_agents/llm/mimo_client.ex lib/fullstack/jido_market_agents/llm/mimo.ex lib/fullstack/jido_market_agents/agents/market_validator.ex test/fullstack/jido_market_agents_test.exs test/fullstack/jido_market_agents/llm/mimo_test.exs odd/tasks/mimo-extraction-response.md
```

### Source contract

MiMo documents enabled-by-default thinking and the shared reasoning/final-answer
completion budget: [Chat Completions API](https://mimo.mi.com/docs/en-US/api/chat)
and [Deep Thinking](https://mimo.mi.com/docs/en-US/quick-start/usage-guide/other/deep-thinking).

## Independent verification

- Parent spot check: 54 selected tests passed, 28 excluded, using current source.
- Independent exact-index check: 48 selected tests passed, 28 excluded; no HEAD fallback.
  Six extra dirty-tree BackendContract tests are unrelated and intentionally unstaged.
- Indexed configuration matched; exact-index formatting and staged whitespace checks passed.
- Native risk assessment unavailable (untracked inventory declaration); treated conservatively
  as high and independently verified. RDD remained off; no review lifecycle was started.
