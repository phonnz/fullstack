defmodule Fullstack.JidoMarketAgents.LLM.FutureProviderTest do
  # The role-selection test mutates
  # Application.get_env(:fullstack, Fullstack.JidoMarketAgents, ...) and
  # restores it in on_exit; must not run concurrently with other tests
  # touching the same application env key.
  use ExUnit.Case, async: false

  alias Fullstack.JidoMarketAgents.LLM
  alias Fullstack.Support.FutureProvider

  @app :fullstack
  @scope Fullstack.JidoMarketAgents

  # -- Shared Backend contract (T7) ---------------------------------------
  #
  # Proves the plan's "no provider switch statement" extension claim: a
  # brand-new, never-before-seen provider satisfies the exact same shared
  # contract as Mimo/ClaudeCode/Codex with zero changes to the contract
  # macro itself.

  use Fullstack.Support.BackendContract,
    backend: FutureProvider,
    valid_config: [mode: :text],
    json_config: [mode: :json_object]

  # -- Independent role selection ------------------------------------------

  setup do
    original = Application.get_env(@app, @scope, [])

    on_exit(fn ->
      Application.put_env(@app, @scope, original)
    end)

    :ok
  end

  defp put_backends(validator, researcher) do
    base = Application.get_env(@app, @scope, [])

    Application.put_env(
      @app,
      @scope,
      Keyword.merge(base, validator_backend: validator, researcher_backend: researcher)
    )
  end

  test "FutureProvider is independently selectable for either role via configuration alone" do
    put_backends(
      {FutureProvider, mode: :text, canned_response: "future-validator-reply"},
      {FutureProvider, mode: :text, canned_response: "future-researcher-reply"}
    )

    assert {:ok, {FutureProvider, validator_opts}} = LLM.backend(:validator)
    assert Keyword.get(validator_opts, :canned_response) == "future-validator-reply"

    assert {:ok, {FutureProvider, researcher_opts}} = LLM.backend(:researcher)
    assert Keyword.get(researcher_opts, :canned_response) == "future-researcher-reply"

    assert {:ok, "future-validator-reply"} =
             LLM.chat_completion(:validator, [], response_format: :text)

    assert {:ok, "future-researcher-reply"} =
             LLM.chat_completion(:researcher, [], response_format: :text)
  end
end
