defmodule Fullstack.Repo.Migrations.CreateChannelIdentities do
  use Ecto.Migration

  def change do
    # One row per external sender (for example a WhatsApp number), mapped to
    # the user created for it and to the conversation it is currently using.
    create table(:channel_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel, :string, null: false
      add :external_id, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :active_conversation_id,
          references(:jido_conversations, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:channel_identities, [:channel, :external_id])
    create index(:channel_identities, [:user_id])
    create index(:channel_identities, [:active_conversation_id])
    create index(:channel_identities, [:inserted_at])

    # Provider message ids already processed; the unique index makes a
    # retried webhook delivery a no-op.
    create table(:channel_inbound_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :channel, :string, null: false
      add :external_id, :string, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:channel_inbound_messages, [:channel, :external_id])
  end
end
