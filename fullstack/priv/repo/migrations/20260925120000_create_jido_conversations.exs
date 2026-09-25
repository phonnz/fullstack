defmodule Fullstack.Repo.Migrations.CreateJidoConversations do
  use Ecto.Migration

  def change do
    create table(:jido_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string
      add :status, :string, null: false, default: "active"
      add :validated_data, :map

      timestamps()
    end

    create index(:jido_conversations, [:user_id])
    create index(:jido_conversations, [:user_id, :inserted_at])

    create table(:jido_conversation_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:jido_conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map

      timestamps(updated_at: false)
    end

    create index(:jido_conversation_messages, [:conversation_id, :inserted_at])
  end
end
