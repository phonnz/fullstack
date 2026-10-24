defmodule Fullstack.JidoMarketAgents.ConversationsStageTest do
  use Fullstack.DataCase, async: true

  import Ecto.Query
  import Fullstack.AccountsFixtures

  alias Fullstack.JidoMarketAgents.Conversations.Message
  alias Fullstack.JidoMarketAgents.Conversations.Record

  @required_fields ~w(country business_market initial_budget final_product_proposal
                      product_price team_size current_tools_systems
                      repetitive_processes_pain_points digital_maturity metrics_baselines)

  # The backfill SQL lives in the migration so it never depends on
  # application modules; the test loads the migration to exercise it.
  @migration_path Path.wildcard("priv/repo/migrations/*_add_stage_to_jido_conversations.exs")
                  |> List.first()

  setup do
    module = Fullstack.Repo.Migrations.AddStageToJidoConversations

    unless Code.ensure_loaded?(module), do: Code.compile_file(@migration_path)

    %{user: user_fixture(), backfill: &module.backfill_sql/1}
  end

  defp insert_record(user, attrs \\ %{}) do
    Repo.insert!(Record.changeset(%Record{}, Map.put(attrs, :user_id, user.id)))
  end

  defp set_stage(record, stage) do
    Repo.update_all(from(r in Record, where: r.id == ^record.id), set: [stage: stage])
    Repo.get!(Record, record.id)
  end

  defp stage_of(record), do: Repo.get!(Record, record.id).stage

  defp raw_stage(record) do
    %{rows: [[stage]]} =
      Repo.query!("SELECT stage::text FROM jido_conversations WHERE id = $1", [
        Ecto.UUID.dump!(record.id)
      ])

    stage
  end

  defp complete_data(overrides \\ %{}) do
    @required_fields |> Map.new(&{&1, "value"}) |> Map.merge(overrides)
  end

  defp add_message(record, role, metadata \\ nil) do
    Repo.insert!(%Message{
      conversation_id: record.id,
      role: role,
      content: "hi",
      metadata: metadata
    })
  end

  defp run_backfill(sql), do: Repo.query!(sql)

  describe "stage field" do
    test "new records default to inserted", %{user: user} do
      record = insert_record(user)
      assert record.stage == :inserted
      assert raw_stage(record) == "inserted"
    end

    test "changeset/2 ignores :stage", %{user: user} do
      changeset = Record.changeset(%Record{}, %{user_id: user.id, stage: "research"})
      refute Map.has_key?(changeset.changes, :stage)
      assert Repo.insert!(changeset).stage == :inserted
    end

    test "an invalid stage value fails at the changeset", %{user: user} do
      record = insert_record(user)
      changeset = Record.stage_changeset(record, :bogus)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :stage)
    end

    test "an invalid stage value fails at the database", %{user: user} do
      record = insert_record(user)

      error =
        assert_raise Postgrex.Error, fn ->
          Repo.query!(
            "UPDATE jido_conversations SET stage = 'bogus' WHERE id = $1",
            [Ecto.UUID.dump!(record.id)],
            mode: :savepoint
          )
        end

      assert error.postgres.code == :invalid_text_representation
      assert stage_of(record) == :inserted
    end
  end

  describe "stage_changeset/2" do
    test "moves to the next stage", %{user: user} do
      record = insert_record(user)

      assert {:ok, %Record{stage: :validating}} =
               Repo.update(Record.stage_changeset(record, :validating))

      assert stage_of(record) == :validating
    end

    test "rejects a skipped stage with a :stage error", %{user: user} do
      record = insert_record(user)
      changeset = Record.stage_changeset(record, :ready)
      refute changeset.valid?
      assert {"invalid transition from inserted to ready", _} = changeset.errors[:stage]
    end

    test "backward change from research or later returns an error, not a raise", %{user: user} do
      for {from, to} <- [research: :ready, proposal: :research, delivered: :strategy] do
        record = set_stage(insert_record(user), from)
        assert {:error, changeset} = Repo.update(Record.stage_changeset(record, to))
        assert Keyword.has_key?(changeset.errors, :stage)
        assert stage_of(record) == from
      end
    end

    test "the trigger maps to a changeset error when the application check is bypassed", %{
      user: user
    } do
      record = set_stage(insert_record(user), :proposal)

      changeset =
        record
        |> Ecto.Changeset.change(stage: :research)
        |> Ecto.Changeset.check_constraint(:stage,
          name: :jido_conversations_stage_forward_only,
          message: "cannot move backward"
        )

      assert {:error, changeset} = Repo.update(changeset)
      assert {"cannot move backward", _} = changeset.errors[:stage]
    end
  end

  describe "forward-only trigger" do
    test "update_all backward from research or later raises a check violation", %{user: user} do
      for {from, to} <- [research: :ready, proposal: :research, strategy: :inserted] do
        record = set_stage(insert_record(user), from)

        error =
          assert_raise Postgrex.Error, fn ->
            Repo.update_all(
              from(r in Record, where: r.id == ^record.id),
              [set: [stage: to]],
              mode: :savepoint
            )
          end

        assert error.postgres.code == :check_violation
        assert error.postgres.constraint == "jido_conversations_stage_forward_only"
        assert stage_of(record) == from
      end
    end

    test "backward changes before research are not blocked", %{user: user} do
      record = set_stage(insert_record(user), :ready)
      assert stage_of(set_stage(record, :validating)) == :validating
      assert stage_of(set_stage(record, :inserted)) == :inserted
    end

    test "forward and same-stage updates pass", %{user: user} do
      record = set_stage(insert_record(user), :research)
      assert stage_of(set_stage(record, :research)) == :research
      assert stage_of(set_stage(record, :delivered)) == :delivered
    end
  end

  describe "backfill" do
    test "empty conversation is inserted", %{user: user, backfill: sql} do
      record = insert_record(user)
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :inserted
    end

    test "a user message makes it validating", %{user: user, backfill: sql} do
      record = insert_record(user)
      add_message(record, "user")
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :validating
    end

    test "assistant-only messages stay inserted", %{user: user, backfill: sql} do
      record = insert_record(user)
      add_message(record, "assistant")
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :inserted
    end

    test "all ten required fields make it ready", %{user: user, backfill: sql} do
      record = insert_record(user, %{validated_data: complete_data()})
      add_message(record, "user")
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :ready
    end

    test "city is optional and extra keys do not matter", %{user: user, backfill: sql} do
      record = insert_record(user, %{validated_data: complete_data(%{"_pipeline" => %{}})})
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :ready
    end

    test "a missing, null, or empty required field is not complete", %{user: user, backfill: sql} do
      for override <- [%{"product_price" => nil}, %{"product_price" => ""}] do
        record = insert_record(user, %{validated_data: complete_data(override)})
        run_backfill_from_scratch(record, sql)
        assert stage_of(record) == :inserted
      end

      data = Map.delete(complete_data(), "metrics_baselines")
      record = insert_record(user, %{validated_data: data})
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :inserted
    end

    # The backfill ran when `status` held the old vocabulary. The column now
    # only holds `idle | running | error`, so only `error` can still be built.
    test "complete data with error status is research", %{user: user, backfill: sql} do
      record = insert_record(user, %{validated_data: complete_data(), status: :error})
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :research
    end

    test "complete data with any other status is ready, not research", %{
      user: user,
      backfill: sql
    } do
      for status <- [:idle, :running] do
        record = insert_record(user, %{validated_data: complete_data(), status: status})
        run_backfill_from_scratch(record, sql)
        assert stage_of(record) == :ready
      end
    end

    test "a market_research message makes it proposal", %{user: user, backfill: sql} do
      record = insert_record(user)
      add_message(record, "assistant", %{"type" => "market_research", "result" => %{}})
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :proposal
    end

    test "other message types do not count as research", %{user: user, backfill: sql} do
      record = insert_record(user)
      add_message(record, "assistant", %{"type" => "business_analysis"})
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :inserted
    end

    test "business_analysis or systems_strategy makes it strategy", %{user: user, backfill: sql} do
      for attrs <- [%{business_analysis: %{"a" => 1}}, %{systems_strategy: %{"a" => 1}}] do
        record = insert_record(user, attrs)
        run_backfill_from_scratch(record, sql)
        assert stage_of(record) == :strategy
      end
    end

    test "tech_strategy makes it delivered", %{user: user, backfill: sql} do
      record = insert_record(user, %{tech_strategy: %{"a" => 1}})
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :delivered
    end

    test "first match wins", %{user: user, backfill: sql} do
      record =
        insert_record(user, %{
          validated_data: complete_data(),
          status: :running,
          business_analysis: %{"a" => 1},
          tech_strategy: %{"a" => 1}
        })

      add_message(record, "assistant", %{"type" => "market_research"})
      run_backfill_from_scratch(record, sql)
      assert stage_of(record) == :delivered

      strategy =
        insert_record(user, %{validated_data: complete_data(), systems_strategy: %{"a" => 1}})

      add_message(strategy, "assistant", %{"type" => "market_research"})
      run_backfill_from_scratch(strategy, sql)
      assert stage_of(strategy) == :strategy

      proposal = insert_record(user, %{validated_data: complete_data(), status: :error})
      add_message(proposal, "assistant", %{"type" => "market_research"})
      run_backfill_from_scratch(proposal, sql)
      assert stage_of(proposal) == :proposal
    end
  end

  # Runs the backfill against one record only, so rows committed by other
  # tests never take part. A fresh record starts at `inserted`, so every
  # backfill move is forward and the trigger stays out of the way.
  defp run_backfill_from_scratch(record, backfill) do
    run_backfill(backfill.("c.id = '#{record.id}'"))
  end
end
