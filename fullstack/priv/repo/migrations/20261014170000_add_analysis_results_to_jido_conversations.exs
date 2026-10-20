defmodule Fullstack.Repo.Migrations.AddAnalysisResultsToJidoConversations do
  use Ecto.Migration

  def change do
    alter table(:jido_conversations) do
      add :business_analysis, :map
      add :systems_strategy, :map
      add :tech_strategy, :map
    end
  end
end
