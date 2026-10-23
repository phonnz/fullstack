defmodule Fullstack.Repo.Migrations.NarrowJidoConversationStatusToHealth do
  use Ecto.Migration

  def up do
    # Native enum type, mirroring `conversation_stage`. `status` now only says
    # whether automatic work is idle, in flight, or failed; the lifecycle
    # position lives in `stage`.
    execute("CREATE TYPE conversation_status AS ENUM ('idle', 'running', 'error');")
    execute("ALTER TABLE jido_conversations ALTER COLUMN status DROP DEFAULT;")

    execute("""
    ALTER TABLE jido_conversations
      ALTER COLUMN status TYPE conversation_status
      USING (#{health_sql("status")})::conversation_status;
    """)

    execute("ALTER TABLE jido_conversations ALTER COLUMN status SET DEFAULT 'idle';")
  end

  def down do
    execute("ALTER TABLE jido_conversations ALTER COLUMN status DROP DEFAULT;")

    execute("""
    ALTER TABLE jido_conversations
      ALTER COLUMN status TYPE varchar(255)
      USING (#{legacy_sql("status", "stage")});
    """)

    execute("ALTER TABLE jido_conversations ALTER COLUMN status SET DEFAULT 'active';")
    execute("DROP TYPE conversation_status;")
  end

  @doc """
  SQL expression mapping an old `status` value to its run health. Unknown and
  null values fall back to `idle`. Pure SQL so it never depends on application
  modules; tests run it against literal values.
  """
  def health_sql(column) do
    """
    CASE #{column}::text
      WHEN 'researching' THEN 'running'
      WHEN 'analyzing' THEN 'running'
      WHEN 'building_strategy' THEN 'running'
      WHEN 'error' THEN 'error'
      ELSE 'idle'
    END
    """
  end

  @doc """
  SQL expression rebuilding the old `status` value from run health and
  lifecycle stage. `running` has no other place to say which phase was in
  flight, so it is read back from the stage.
  """
  def legacy_sql(status_column, stage_column) do
    """
    CASE
      WHEN #{status_column}::text = 'error' THEN 'error'
      WHEN #{status_column}::text = 'running' AND #{stage_column}::text = 'strategy'
        THEN 'building_strategy'
      WHEN #{status_column}::text = 'running' AND #{stage_column}::text = 'proposal'
        THEN 'analyzing'
      WHEN #{status_column}::text = 'running' THEN 'researching'
      WHEN #{stage_column}::text = 'delivered' THEN 'completed'
      ELSE 'active'
    END
    """
  end
end
