defmodule Fullstack.Repo.Migrations.AddStageToJidoConversations do
  use Ecto.Migration

  @required_fields ~w(country business_market initial_budget final_product_proposal
                      product_price team_size current_tools_systems
                      repetitive_processes_pain_points digital_maturity metrics_baselines)

  def up do
    # Native enum type, mirroring `user_role`. Postgres compares enum values
    # in declaration order, which the forward-only trigger relies on.
    execute(
      "CREATE TYPE conversation_stage AS ENUM " <>
        "('inserted', 'validating', 'ready', 'research', 'proposal', 'strategy', 'delivered');"
    )

    alter table(:jido_conversations) do
      add :stage, :conversation_stage, null: false, default: "inserted"
    end

    execute(backfill_sql())

    execute("""
    CREATE FUNCTION jido_conversations_stage_forward_only() RETURNS trigger AS $$
    BEGIN
      IF OLD.stage >= 'research' AND NEW.stage < OLD.stage THEN
        RAISE EXCEPTION 'conversation stage cannot move backward from % to %', OLD.stage, NEW.stage
          USING ERRCODE = 'check_violation',
                CONSTRAINT = 'jido_conversations_stage_forward_only';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER jido_conversations_stage_forward_only
    BEFORE UPDATE OF stage ON jido_conversations
    FOR EACH ROW EXECUTE FUNCTION jido_conversations_stage_forward_only();
    """)
  end

  def down do
    execute("DROP TRIGGER jido_conversations_stage_forward_only ON jido_conversations;")
    execute("DROP FUNCTION jido_conversations_stage_forward_only();")

    alter table(:jido_conversations) do
      remove :stage
    end

    execute("DROP TYPE conversation_stage;")
  end

  @doc """
  Backfill SQL, first matching rule wins. Pure SQL so it never depends on
  application modules. `where` narrows the rows (tests use it to scope one
  record); the migration backfills every row.
  """
  def backfill_sql(where \\ "true") do
    # Present means the key exists, is not JSON null, and is not an empty string.
    complete =
      Enum.map_join(@required_fields, " AND ", fn field ->
        "(c.validated_data -> '#{field}') IS NOT NULL " <>
          "AND jsonb_typeof(c.validated_data -> '#{field}') <> 'null' " <>
          "AND (c.validated_data ->> '#{field}') <> ''"
      end)

    """
    UPDATE jido_conversations c
    SET stage = (CASE
      WHEN c.status = 'completed' OR c.tech_strategy IS NOT NULL THEN 'delivered'
      WHEN c.systems_strategy IS NOT NULL OR c.business_analysis IS NOT NULL THEN 'strategy'
      WHEN EXISTS (
        SELECT 1 FROM jido_conversation_messages m
        WHERE m.conversation_id = c.id AND m.metadata ->> 'type' = 'market_research'
      ) THEN 'proposal'
      WHEN (#{complete}) AND c.status IN ('researching', 'error') THEN 'research'
      WHEN (#{complete}) THEN 'ready'
      WHEN EXISTS (
        SELECT 1 FROM jido_conversation_messages m
        WHERE m.conversation_id = c.id AND m.role = 'user'
      ) THEN 'validating'
      ELSE 'inserted'
    END)::conversation_stage
    WHERE #{where}
    """
  end
end
