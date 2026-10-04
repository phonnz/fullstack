defmodule FullstackWeb.EvaluationLive.Show do
  @moduledoc """
  Admin-only, read-only detail view of a single evaluation.

  Reads across users through `Conversations.get_any/1`, safe only because
  the route sits in a `live_session` gated on `:ensure_admin`.

  Deliberately **not** a mirror of `BusinessDiscoveryLive.Evaluate`:

  - It never calls `Conversation.ensure_started/2`. Opening an admin view
    must have no side effect on the user whose evaluation it is, so no
    GenServer is started and no PubSub subscription is made.
  - It offers no message form and no status mutation. Reviewing is not
    participating.
  - A missing id raises `Ecto.NoResultsError` (404) rather than
    redirecting, matching the rest of the admin surface.

  `validated_data` is a free-form `:map` with no schema behind it, so it
  is rendered defensively: `nil`, an empty map, and nested values all have
  to render without raising.
  """

  use FullstackWeb, :live_view

  alias Fullstack.JidoMarketAgents.Conversations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    record =
      Conversations.get_any(id) ||
        raise Ecto.NoResultsError, queryable: Conversations.Record

    {:ok,
     socket
     |> assign(:page_title, "Evaluation")
     |> assign(:evaluation, record)
     |> assign(:messages, Conversations.list_messages(record.id))
     |> assign(:validated_data, normalize_validated_data(record.validated_data))}
  end

  # Returns a sorted keyword-ish list of {key, rendered_value} pairs, or []
  # when there is nothing to show. Values that are not plain scalars are
  # inspected rather than interpolated, so a nested map or list renders as
  # readable text instead of raising in the template.
  defp normalize_validated_data(data) when is_map(data) and map_size(data) > 0 do
    data
    |> Enum.map(fn {key, value} -> {to_string(key), render_value(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize_validated_data(_data), do: []

  defp render_value(value) when is_binary(value), do: value
  defp render_value(value) when is_number(value), do: to_string(value)
  defp render_value(value) when is_boolean(value), do: to_string(value)
  defp render_value(nil), do: "—"
  defp render_value(value) when is_list(value), do: Enum.map_join(value, ", ", &render_value/1)
  defp render_value(value), do: inspect(value, pretty: true)
end
