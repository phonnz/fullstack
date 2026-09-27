# Feature: Pluggable LLM Backend (Mimo / ClaudeCode / Codex)

**Status:** PLAN ONLY — plan completion authorized; source implementation is not.
**Review:** 2026-09-27 — code, installed CLI help and official documentation checked; no inference run.
**Date:** 2026-09-27
**Route:** delegated direct (writer trigger fires: 5+ non-trivial files)

---

## Objective

Introduce a `Backend` behaviour in the market-agents pipeline so the LLM used by
each agent role is selected by config. Two adapter families:

- `Mimo` — existing HTTP chat-completions client (default, unchanged behaviour)
- `Cli` — local `claude` / `codex` binaries in non-interactive mode

Updated scope (user, 2026-09-28): **both validator and researcher independently
select Mimo, ClaudeCode or Codex**, with their own model and optional CLI effort.
Mimo remains the default for both. Future providers implement the same shared
`Backend` behaviour; new models normally require configuration and compatibility
metadata/tests, not a new adapter or behaviour.

## Problem

Both agents call `Fullstack.JidoMarketAgents.LLM.MimoClient` directly:
`MarketValidator.extract_fields/2` and `MarketResearcher.research/1`.
Swapping the provider currently requires source edits.

## Why per-role, not global

Separate role configuration preserves a fast extraction default while allowing
the user to choose another provider for either role. Selecting CLI validation
adds subprocess latency; this is an explicit tradeoff, not a reason to prohibit
it. Mimo's current client sends JSON-object mode and already reads `opts[:model]`
with fallback `"mimo-v2.5-pro"`; no model hardcoding fix is needed in that client.

Both CLIs support structured output: Claude `--json-schema`, Codex
`--output-schema`. This plan includes their translation and extraction tests so
validator switching is a real supported path, not a promised follow-up.
See [Claude CLI reference](https://code.claude.com/docs/en/cli-reference) and
[Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode).
No inference latency or provider availability was measured in this review.

The researcher stays text-in/text-out. A CLI is not automatically web-grounded:
its search tool must be explicitly enabled and permitted. Preserve the existing
research prompt for this behaviour-neutral adapter change; improved citations
or research-quality guarantees are separate product work.

## Evidence and compatibility baseline

Verified in this second-opinion pass: current call sites, synchronous conversation
callbacks, application startup, Bandit test setup, and local CLI help/version.
The existing repository-root CodeGraph index returned no relevant symbols, so
these checks used targeted source reads. No paid CLI smoke test was repeated.

| Binary | Version observed now | Resolution caveat |
|---|---|---|
| `claude` | 2.1.261 | Explicit `~/.nvm/versions/node/v24.9.0/bin/claude` works; bare `claude` hits an unconfigured version-manager shim |
| `codex` | codex-cli 0.157.1 | Earlier plan reported 0.156.1; version-specific help must be checked at deployment |

Require a configurable executable path and deterministic child PATH. Merely
finding a shim is not proof it launches under the service account. Help probes
check local compatibility, not authentication, account access or billing.

### `claude` non-interactive contract

Minimal protocol example only; add the execution/isolation policy below before use.

```
claude -p --output-format json --restricted --no-session-persistence \
       --model sonnet --system-prompt <sys> <user-prompt>
```

Returns a single JSON object on stdout. Relevant fields:

- `result` — assistant text for researcher/text requests
- `structured_output` — parsed schema output for validator requests
- `is_error` — boolean
- `api_error_status` — e.g. `400`
- `subtype` — `"success"`

**Previously reported smoke result (not rerun):** exit status was zero with `is_error: true`, `api_error_status: 400`, `result: "Credit balance is too low"`.

A naive `exit_status == 0` success check would return `{:ok, "Credit balance is
too low"}` and that string would be **stored and displayed as market research**.
Success requires exit status zero **and** a valid success envelope: `is_error: false`,
`subtype: "success"`, and the field appropriate to the requested format. Text
requires nonempty `result`; structured mode requires a valid `structured_output`
object, encoded back to JSON text for the shared return contract. Do not require
a nonempty `result` in structured mode or fall back to it when the structured
field is missing. Nonzero exit, error envelope or malformed output is an error.
The structured field is documented in
[Claude programmatic usage](https://code.claude.com/docs/en/headless).

**Previously reported auth-precedence warning** (not reproduced here):

> claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth
> source is set and takes precedence over your claude.ai login

The subprocess inherits the parent env. Behaviour therefore differs between a
developer shell and the running app. The runner must construct a sanitized child environment; `Port` env entries
overlay the inherited environment rather than replace it (see execution design).

### `codex` non-interactive contract

Minimal protocol example only; add the execution/isolation policy below before use.

```
codex exec --skip-git-repo-check --ephemeral --sandbox read-only \
           --color never -o <tmpfile> <prompt>
```

The earlier plan reports a successful smoke test producing `PONG` in its output
file. This review verified flag availability only, not that historical run.

`-o/--output-last-message <FILE>` is the selected output contract. The earlier
plan reports noisy stdout, including:

```
session id: 01a0e34b-...
warning: Codex's Linux sandbox uses bubblewrap and needs access to create user namespaces.
hook: SessionStart
hook: UserPromptSubmit Completed
ERROR: Reconnecting... 2/5
codex
PONG
tokens used
27,124
```

Note `ERROR: Reconnecting... 2/5` on a **successful** run. Scraping stdout is
not viable; read the `-o` file.

Codex has `--json` (JSONL events) as an alternative. `-o` is simpler for
"same job, different brains" and is what this plan uses.

### Asymmetry to encode

| | claude | codex |
|---|---|---|
| Success signal | zero exit + validated success JSON | zero exit + fresh, bounded, nonempty output file |
| Text location | `result`, or JSON-encoded `structured_output` | `-o` file contents, parsed/validated for structured requests |
| System prompt | `--system-prompt <text>` | must be folded into the prompt |
| No-persist flag | `--no-session-persistence` | `--ephemeral` |

Two adapters, not one parameterised module. Shared Port/timeout logic is
extracted; argv construction and result extraction are per-CLI.

### Reference scope

Maestro was a prior design reference, not a dependency. Its external repository,
license, runtime requirements and defaults were not rechecked in this review;
none is required to justify this design. Copy no Maestro code. Keep only the
small local behaviour, config validation and test double needed by these callers.
Sessions and streaming remain deferred.

---

## Design

### The behaviour

`lib/fullstack/jido_market_agents/llm/backend.ex`

```elixir
defmodule Fullstack.JidoMarketAgents.LLM.Backend do
  @type message :: %{required(String.t()) => String.t()}
  @type capability :: :json_object | :json_schema | :temperature | :max_tokens | :effort

  @callback chat_completion([message()], keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback capabilities(keyword()) :: [capability()]
  @callback validate_config(keyword()) :: :ok | {:error, term()}
end
```

Validate the `"role"` and `"content"` keys at runtime. CLI support initially covers
the actual system/user text messages; reject unsupported roles rather than
silently flattening them. Codex prompt folding does not recreate API role priority.
All adapters preserve `{:ok, text} | {:error, reason}`; JSON output is JSON text,
not a provider envelope or an Elixir map. No provider-specific branch belongs in
either agent. Capabilities describe the **configured model/client combination**,
not every feature a provider has ever supported.

### Dispatch and option ownership

`lib/fullstack/jido_market_agents/llm.ex` exposes:

```elixir
LLM.chat_completion(:validator, messages,
  response_format: {:json_object, ExtractionOutput.schema()})
LLM.chat_completion(:researcher, messages, response_format: :text)
```

Resolve `{module, backend_opts}` at runtime through `Application.get_env/3` and
retain all configured options when calling the adapter. A module-only resolver
would discard model, effort and runner settings. `response_format` is required by
the caller; model, effort, sampling and execution settings come from the role's
trusted config. Reject unknown call/config keys, invalid roles and malformed
modules with tagged errors; never create atoms from config strings.

Move the callers' current numeric controls into their **Mimo default role
configs**: validator `temperature: 0.3, max_tokens: 1024`; researcher
`max_tokens: 1024` (Mimo client retains temperature default 0.7). CLI role configs
omit these controls because this adapter does not provide equivalent switches.
An explicitly configured unsupported temperature/token limit is a validation
error, not a discarded hint or fabricated cost cap. This removes provider knobs
from agents without silently dropping user settings when a backend changes.

After `validate_config/1` succeeds, call `capabilities(backend_opts)` and validate
the format required by that role. Mimo exposes JSON-object mode plus its existing
numeric controls; supported CLI profiles expose JSON-object/schema output and
optional effort, not temperature/max_tokens. CLI profiles used for the validator
must support schema output. Never silently fall back to Mimo, another model or a
lower effort when validation or provider execution fails.

Wire `LLM.validate_config/0` into `Fullstack.Application.start/2` before supervision.
Check both roles, callback availability, model/effort/format compatibility, limits
and selected CLI prerequisites. Runtime dispatch repeats semantic validation so
test/config overrides cannot bypass boot. Defaults must not require unused CLIs
or live Mimo credentials; boot performs no inference or remote auth probes.
Config-mutating tests use `async: false` and restore application environment.

### Per-role models and effort

| Adapter | Model mapping | Optional `effort` mapping | Unsupported settings |
|---|---|---|---|
| Mimo | pass `model:` to existing `MimoClient.chat_completion/2` → request body `model` | not implemented; reject if supplied | effort and unrecognized options |
| ClaudeCode | argv `--model <model>` | argv `--effort <level>` | temperature/max_tokens; levels unsupported by model, pinned CLI or deployment policy |
| Codex | argv `--model <model>` | argv `-c` followed by TOML `model_reasoning_effort="<level>"` | temperature/max_tokens; levels unsupported by model/client |

`effort: nil` or omitted means no effort override; the isolated provider's default
applies. Use strings, not a shared atom enum: level names and support differ by
model/client. Installed Claude help advertises `low`, `medium`, `high`, `xhigh`,
`max`; this does **not** mean every model accepts all five. Codex documents a
model-advertised string rather than a universal list. See
[Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference)
and [Claude effort configuration](https://code.claude.com/docs/en/model-config).

Each adapter owns small, versioned compatibility descriptors for supported model
IDs/aliases: capabilities, allowed efforts and client-version/policy prerequisites.
Populate them from pinned-version documentation or already available authorized
metadata, with source/version evidence and contract tests. Do not invent a model
matrix or query live accounts at boot. Unknown CLI model/effort combinations fail
with `{:unsupported_model_config, ...}` until a descriptor is added. Preserve
Mimo's current default model, while extra models need an explicit descriptor for
the options/format used. Provider/account rejection at execution is still possible
and must propagate honestly. Aliases can drift; prefer exact IDs in deployment.

Claude organization/managed effort caps can silently clamp JSON-mode requests.
For explicit effort, validate the effective service policy/cap before enabling
that configuration; if it cannot be established, reject it as unverified rather
than promise the requested level was applied. Do not bypass policy, log secrets,
or infer applied effort from answer length. No automatic fallback model is set.

### Validator output contract

Own the six extraction fields in one `ExtractionOutput` helper used by the
validator and its schema builder: `country`, `city`, `business_market`,
`initial_budget`, `final_product_proposal`, `product_price`. It is a domain
contract, not a behaviour per provider. Preserve current normalization/merge:
missing/null/empty values never erase accumulated fields; numeric/boolean scalar
values become strings; unknown keys are ignored; nested values normalize to nil.
Business completeness remains separate: five fields are required eventually,
while `city` is optional. Partial turns must not invent missing business data.

`response_format: {:json_object, schema}` means machine-readable extraction JSON;
the schema is the domain's generation contract, not a claim that every provider
uses native constrained decoding. For CLI generation use a closed object schema:
all six keys appear in `properties` and `required`, `additionalProperties: false`,
each property has `type: ["string", "null"]`. All-null output is valid. Requiring
keys in the wire schema does not require known values: prompts explicitly use
null for absent information and strings for known values. This nullable form
supports strict schema providers while preserving incremental extraction.

- **Mimo:** translate the requested object format to existing `json_mode: true`;
  retain the existing extraction prompt and partial-object parser/normalizer.
  Do not send an unsupported JSON-schema API parameter, reject `{}` or demand
  all wire keys from legacy Mimo responses. The CLI generation schema does not
  replace current Mimo parsing or business completeness checks.
- **ClaudeCode:** append `--json-schema <encoded-schema>` with JSON output;
  validate success metadata, extract `structured_output`, validate the fixed
  closed nullable-string schema locally, then `Jason.encode/1` it for the caller.
- **Codex:** write the schema to a private per-call file and pass
  `--output-schema <path>`; read the fresh final-output file, decode and validate
  against that same fixed schema, then return JSON text. No stdout scraping.

Put the schema-specific null instructions in the CLI prompt renderer, not the
legacy Mimo prompt. The fixed six-property schema needs only bounded validation
of object/keys/string-or-null values, not a new general-purpose schema engine.
Reject missing structured output, wrong roots/types/keys, refusal/error envelopes
and malformed JSON. Preserve the validator map fast path (no LLM), existing Mimo
scalar coercion and accumulation, and fail-loud parse errors. These distinctions
are required regression cases, not an excuse to declare all provider semantics
identical.

### Config

Use `alias Fullstack.JidoMarketAgents.LLM` in config files. Default config:

```elixir
config :fullstack, Fullstack.JidoMarketAgents,
  # Preserve existing debounce/rate-limit keys.
  validator_backend:
    {LLM.Mimo, model: "mimo-v2.5-pro", temperature: 0.3, max_tokens: 1024},
  researcher_backend:
    {LLM.Mimo, model: "mimo-v2.5-pro", max_tokens: 1024}
```

Illustrative `runtime.exs` opt-in for **different CLI providers on both roles**;
model/effort values must pass adapter compatibility validation. Absence of an
effort environment variable is intentional, not an instruction to invent a value:

```elixir
config :fullstack, Fullstack.JidoMarketAgents,
  validator_backend:
    {LLM.Cli.ClaudeCode,
     command: System.fetch_env!("CLAUDE_BIN"),
     model: System.fetch_env!("VALIDATOR_MODEL"),
     effort: System.get_env("VALIDATOR_EFFORT"),
     timeout_ms: 300_000,
     env: %{"ANTHROPIC_API_KEY" => System.fetch_env!("ANTHROPIC_API_KEY")}},
  researcher_backend:
    {LLM.Cli.Codex,
     command: System.fetch_env!("CODEX_BIN"),
     model: System.fetch_env!("RESEARCHER_MODEL"),
     effort: System.get_env("RESEARCHER_EFFORT"),
     timeout_ms: 300_000,
     env: %{"CODEX_API_KEY" => System.fetch_env!("CODEX_API_KEY")}}
```

Runner isolation policy below also applies; this fragment is not permission to
inherit credentials/config. Either tuple can instead use Mimo or the other CLI.
Missing CLI model/path or empty effort strings are invalid. An omitted Mimo
model resolves to its current default for backward compatibility. Secrets stay
in runtime environment, not checked-in config or errors.

### Extending providers and models

1. New provider: add one adapter implementing **this existing `Backend` behaviour**,
   its config validation, model descriptors, request mapping and output/error
   normalization. Reuse the runner only if it is actually CLI-based.
2. Add contract tests covering text, required validator JSON support (or explicit
   rejection), model/options, errors and cleanup. No change to agent logic or a
   provider switch statement in dispatch should be necessary.
3. Select `{NewAdapter, opts}` for either role. Unsupported validator format is
   rejected at configuration time, not discovered after losing extraction data.
4. New model on an existing protocol: extend its compatibility descriptor/tests
   and change the role's `model`. Change adapter mapping only when the protocol
   actually differs. Never add a new behaviour just because the model changed.

### Modules

| File | Purpose |
|---|---|
| `llm/backend.ex` | behaviour (new) |
| `llm.ex` | role dispatch, option policy and config validation (new) |
| `lib/fullstack/application.ex` | invoke validation before supervision starts |
| `llm/mimo.ex` | `@behaviour`; wraps existing client (new, thin) |
| `llm/cli/runner.ex` | bounded subprocess lifecycle and output/temp cleanup (new) |
| `llm/cli/claude_code.ex` | argv + `is_error`/`result` parsing (new) |
| `llm/cli/codex.ex` | argv + `-o` file read (new) |
| `llm/mimo_client.ex` | existing configurable-model transport; unchanged unless a verified forwarding gap appears |
| `agents/extraction_output.ex` | shared field normalization + CLI generation schema (new) |
| `agents/market_validator.ex` | format request + shared extraction contract, preserve merge semantics |
| `agents/market_researcher.ex` | text-format request; move Mimo numeric defaults to role config |

### Subprocess execution and isolation

Use `Port.open({:spawn_executable, path}, ...)` with separate argv elements, never
a shell command assembled from messages. Resolve the executable before changing
cwd. Prefer stdin for user text where the pinned CLI supports it; never put
credentials in argv. Do not merge stderr into Claude's JSON stdout.

- **Environment:** OTP `env:` extends inherited variables. Explicitly unset
  inherited keys not in the approved allowlist using `{name, false}`, then add
  the allowed environment with OTP-compatible names/values. Never mutate the
  BEAM's global environment per request. Choose service-owned auth explicitly;
  do not reuse a developer's login/config/home implicitly. Verify with a fake
  executable that sentinel secrets are absent. See
  [OTP open_port](https://www.erlang.org/doc/apps/erts/erlang.html#open_port/2).
- **Isolation:** fresh private per-call directory, restrictive permissions and
  dedicated service HOME/config roots. Scratch cwd and read-only sandbox alone
  do not disable user hooks, plugins, MCP, credential loading or outside reads.
  Claude's installed help supports `--restricted`, `--bare`,
  `--disable-slash-commands`, `--strict-mcp-config` and explicit `--tools`;
  use an audited API-key-only configuration, no ambient MCP, and only intended
  research tools. Restricted mode removes WebFetch unless explicitly selected.
  Codex's installed help exposes `--ignore-user-config` and `--ignore-rules`,
  but these are not universal hook/plugin isolation. Use a dedicated empty
  service config root, explicit auth and audited settings. No permission-bypass
  flags. Validate pinned-version behaviour before enabling the adapter.
- **Search policy:** tool-free text completion is the safe initial baseline.
  If search is enabled, select only intended web tools (Claude) or an explicit
  web-search setting (Codex; top-level `--search` is exposed by local help).
  Do not advertise live research when disabled/unavailable. Search availability
  and provider account permissions remain deployment checks, not proven here.
- **Deadline/output:** one monotonic deadline covers launch, collection and
  result reading; incoming chunks must not reset it. Bound stdout, stderr and
  final-file bytes. Overflow is an error and triggers the same cleanup. Read
  only this run's regular output file, reject missing/empty/oversized output,
  and remove temporary files on success, failure and timeout.
- **Termination:** closing a Port or killing a BEAM Task does **not establish**
  termination/reaping of a CLI's OS descendants. Before T4 ships, select and
  document a supported-OS process-group/container lifecycle mechanism, including
  TERM, bounded grace, KILL and exit confirmation. Cover caller death and
  descendant processes in fake-executable tests. A new OS helper or dependency
  needs explicit approval; if no safe dependency-free mechanism is demonstrated,
  ship T1–T3 only and leave CLI enablement blocked rather than claim cleanup.

The synchronous caller remains blocked until the adapter returns. A worker can
own the Port and monitor caller death, but `Task.yield/2` still blocks the caller
and `Task.shutdown/2` is not OS-process-tree management. Do not add a Task merely
to claim responsiveness. Moving inference out of `Conversation.handle_info/2`
and handling results asynchronously remains deferred; timeout only bounds waiting.

Return bounded tagged errors (`:timeout`, invalid config/output, nonzero exit,
provider failure, output limit, cleanup failure). Never include raw env, prompts
or stderr in error terms: current conversation code logs and displays inspected
reasons. Cleanup failure must not be reported as successful termination.

---

## Testing (strict TDD — mode enabled)

Existing idiom is **not module mocking**. There is no Mimic/Mox/Bypass in
`mix.exs`. Tests stand up a real `Bandit` server and repoint `MIMO_BASE_URL` at
it (`test/fullstack/jido_market_agents_test.exs:9-40`), faking at the transport
boundary.

That idiom **cannot test a subprocess adapter** — there is no HTTP to intercept.

Strategy per layer:

1. **Resolution** (`llm.ex`) — pure config reads. Plain unit tests.
2. **`Mimo` adapter** — reuses the existing Bandit harness untouched. Proves the
   refactor changed no behaviour.
3. **CLI adapters** — inject a **fake executable**: a shell/elixir script
   fixture in `test/support/` that emits canned stdout (or writes the `-o` file)
   and exits with a chosen status. `command:` already points at a configurable
   binary, so this needs no production seam beyond what the design has.
   Required cases:
   - both roles independently select each adapter; model/effort settings do not leak between roles;
   - Mimo model reaches HTTP body; Claude/Codex model and effort reach exact argv;
   - omitted effort emits no override; unknown model/effort, explicit unsupported
     temperature/max_tokens and unverified Claude effort caps fail before spawn;
   - Claude structured_output succeeds even with empty result; schema file/flags
     and Codex JSON output are correct, including all-null/partial-known fields;
   - CLI schema violations/refusals fail; existing Mimo `{}`, scalar coercion,
     ignored unknown keys, empty/null non-overwrite and map fast path remain;
   - valid success, nonzero exit, exit-zero error envelope, malformed/empty output;
   - Codex noisy stdout with fresh valid output; missing/stale/oversized file;
   - option propagation/precedence and unsupported required capability;
   - env allowlist, literal metacharacters, distinct concurrent scratch dirs;
   - deadline despite continuous output, output overflow, caller death;
   - hung parent plus grandchild termination and cleanup after every outcome.
4. **A test backend** in `test/support/` for deterministic conversation-level
   success and failure, independent of HTTP or subprocesses.

No automated test may invoke a real `claude`/`codex`, use paid inference or depend
on login state. Offline fake-process tests prove mechanics, not provider access
or answer quality; a later live probe requires separate authorization.

**Existing test evidence:** `setup_all` in `jido_market_agents_test.exs` redirects
Mimo to a local Bandit server for this entire module, with a default `{}` response.
The earlier claim that the cited tests require live credentials was incorrect.
Some comments still mention availability and one error test accepts success or
failure; add deterministic backend success/error coverage rather than broadening
this work into unrelated test cleanup.

---

## Tasks

- [ ] T1 — Shared behaviour, role dispatch, configured-model capabilities and
      boot/runtime validation; test unknown options/model/effort/format rejection.
- [ ] T2 — Mimo adapter and role-specific numeric defaults; prove per-role model
      forwarding and unchanged default Bandit requests/results.
- [ ] T3 — Both agent format requests and shared extraction schema/normalizer;
      prove independent overrides, partial-turn accumulation and Mimo compatibility.
- [ ] T4 — Resolve the OS termination prerequisite, then implement the bounded
      runner, sanitized env, private scratch lifecycle and descendant tests.
      Block CLI enablement if that prerequisite cannot be met safely.
- [ ] T5 — Claude model/effort descriptors, isolated argv and text/structured
      output parsing; test both roles, policy validation and failure envelopes.
- [ ] T6 — Codex model/effort descriptors, isolated argv, schema file and bounded
      text/JSON output; test both roles, noisy stdout and missing/stale outputs.
- [ ] T7 — Shared backend contract tests, test-only future-provider adapter and
      deterministic conversation success/error coverage for independent role configs.
- [ ] T8 — Document per-role provider/model/effort configuration, extension steps,
      rejected controls, auth/tool/search policy and remaining OS/async gates.

T1–T3 together are an independently useful abstraction slice and keep Mimo as
both defaults. Stage startup wiring only once the Mimo adapter exists; do not
commit a default configuration pointing to a missing module. T4 gates T5–T6;
T7–T8 complete whichever slice is actually delivered. All implementation tasks
use delegated direct work: multi-file logic, tests and write preparation trigger
that route. No implementation task was completed by this plan review.

Strict TDD is enabled by project instructions: observe RED → GREEN → REFACTOR.
Planned checks are focused `mix test <changed-test-file>`, existing
`mix test test/fullstack/jido_market_agents_test.exs`, `mix test`,
`mix compile --warnings-as-errors`, and `mix format --check-formatted` for touched
Elixir files. The test alias creates/migrates the test database; provision it
before running. These checks were **not run** for this Markdown-only pass.

Upon separate implementation authorization, use work-unit Conventional Commits
and record commit/check evidence here. Current branch is `ft-maestro-agents`, not
the previously named `ft-agents`; recheck branch before implementation. Delivery
strategy remains `ask-on-risk`; estimate the authored diff before the first
source write and resolve the PR boundary if it exceeds approximately 400 lines.
No commit, push or PR is authorized by this second-opinion request.

## Constraints

- Default config must keep today's behaviour exactly (Mimo both roles)
- No new dependencies without approval; `Port`, `Jason` and `Req` are available,
  but Port alone is not proof of complete OS descendant cleanup
- No Maestro code copied or dependency added. Design reference only.
- Elixir `~> 1.18` / Phoenix 1.8 unchanged
- `MIMO_API_KEY`/`MIMO_BASE_URL` keep reading from `System.get_env` inside the
  Mimo client — out of scope to relocate

## Acceptance criteria

- Both validator and researcher can independently use Mimo, ClaudeCode or Codex
  through role config; model and optional supported CLI effort propagate exactly.
  One role's settings never affect the other; request data cannot override policy.
- Mimo remains the default for both roles with current model/sampling/token
  values. CLI validator schema output works with nullable missing fields, while
  existing Mimo partial/scalar normalization and map fast path stay unchanged.
- Unsupported or unverified model/effort/format/control combinations fail clearly
  without silently dropping settings, clamping in the adapter or changing models.
- A test-only additional provider satisfies the same behaviour and is selectable
  without changing agents; supported new models use descriptors/config.
- Boot detects invalid selected config without making network calls or requiring
  unused CLI installations. Runtime overrides cannot bypass validation.
- CLI success requires valid output plus successful process status. Errors are
  bounded and sanitized before current logging/UI paths receive them.
- Hung/overflowing/cancelled subprocesses and their descendants terminate within
  the documented timeout plus cleanup grace on the supported OS, with evidence;
  all scratch artifacts are removed. Failed cleanup is explicit.
- Fake executable tests prove env isolation, literal argv, output limits and
  concurrent-call independence. No test invokes a real paid CLI.
- Run planned functional checks under default config, reporting actual failures
  and baseline/environment blockers rather than equating plan review with PASS.

## Risks

- **R1 — synchronous conversation:** timeout bounds delay, not responsiveness;
  queued calls and status reads still wait. Async redesign stays deferred.
- **R2 — model/client/policy drift:** aliases, effort support and structured-output
  support vary. Versioned descriptors fail closed; Claude policy can clamp effort.
  JSON-object mode is not identical to native schema enforcement. Temperature
  and token limits without a supported mapping are rejected, not approximated.
- **R3 — output contract drift:** pin/test CLI versions; neither exit zero nor
  an output file alone is enough. Historical smoke reports are not current proof.
- **R4 — deployment:** user-local paths/shims, child runtime PATH and OS cleanup
  support must be validated for the service account before CLI enablement.
- **R5 — credentials/tools:** env overlays, user config, managed settings and
  tool access can leak data or alter behaviour; no ambient-session reuse.
- **R6 — cost/concurrency:** independent conversations can spawn multiple CLIs;
  current limiter controls string inputs while maps bypass it and may still
  trigger research. Timeout/output limits are not billing or concurrency caps.
  Keep CLI opt-in; broader admission/budget control is deferred, not solved.

## Out of scope (deferred)

- Streaming / progress reporting (option 2)
- Moving inference off the `Conversation` process
- Sessions, multi-turn, `run_turn`/`stop_session`
- Running Maestro as an external service
- `Fullstack.Llms.Client.Local` (Ollama demo path, `llms/client.ex`) — separate
  feature, untouched
- Removing the stray `dbg/1` and `IO.inspect/1` in `mimo_client.ex:27,38,42`
  (pre-existing; fires on every live call)
- Broad cleanup of legacy test assertions unrelated to adapter coverage
