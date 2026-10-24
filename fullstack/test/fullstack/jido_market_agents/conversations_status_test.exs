defmodule Fullstack.JidoMarketAgents.ConversationsStatusTest do
  use Fullstack.DataCase, async: true

  # The mapping SQL lives in the migration so it never depends on application
  # modules; the test loads the migration to run it against literal values.
  @migration_path Path.wildcard(
                    "priv/repo/migrations/*_narrow_jido_conversation_status_to_health.exs"
                  )
                  |> List.first()

  setup do
    module = Fullstack.Repo.Migrations.NarrowJidoConversationStatusToHealth

    unless Code.ensure_loaded?(module), do: Code.compile_file(@migration_path)

    %{module: module}
  end

  describe "status to health mapping (up)" do
    test "maps every old value to idle, running, or error", %{module: module} do
      expected = [
        {"active", "idle"},
        {"completed", "idle"},
        {"researching", "running"},
        {"analyzing", "running"},
        {"building_strategy", "running"},
        {"error", "error"},
        {"unknown_value", "idle"},
        {nil, "idle"}
      ]

      for {old, health} <- expected do
        assert query_one(module.health_sql("c.status"), "c.status", [old]) == health
      end
    end
  end

  describe "health to status mapping (down)" do
    test "rebuilds the old value from health and stage", %{module: module} do
      expected = [
        {"error", "research", "error"},
        {"running", "research", "researching"},
        {"running", "ready", "researching"},
        {"running", "proposal", "analyzing"},
        {"running", "strategy", "building_strategy"},
        {"idle", "delivered", "completed"},
        {"idle", "research", "active"},
        {"idle", "inserted", "active"}
      ]

      for {status, stage, old} <- expected do
        sql = module.legacy_sql("c.status", "c.stage")
        assert query_one(sql, "c.status, c.stage", [status, stage]) == old
      end
    end
  end

  # Runs `expression` over one synthetic row with text columns.
  defp query_one(expression, columns, params) do
    placeholders =
      params |> Enum.with_index(1) |> Enum.map_join(", ", fn {_, i} -> "$#{i}::text" end)

    names = columns |> String.replace("c.", "")

    %{rows: [[value]]} =
      Repo.query!(
        "SELECT (#{expression}) FROM (VALUES (#{placeholders})) AS c(#{names})",
        params
      )

    value
  end
end
