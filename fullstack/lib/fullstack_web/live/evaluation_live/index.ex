defmodule FullstackWeb.EvaluationLive.Index do
  @moduledoc """
  Admin-only listing of every user's market discovery evaluation.

  Reads across users through `Conversations.list_all/1`, which bypasses the
  ownership filter by design. That is only safe because the route sits in a
  `live_session` gated on `FullstackWeb.UserAuth`'s `:ensure_admin` — see
  the warning on `list_all/1` itself.

  Read-only: this view never mutates a conversation and never starts a
  `Conversation` GenServer, so opening it has no effect on the user whose
  evaluation is being reviewed.
  """

  use FullstackWeb, :live_view

  alias Fullstack.JidoMarketAgents.Conversations

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Evaluations")
     |> assign(:evaluations, Conversations.list_all())}
  end

  @impl true
  def handle_event("select_evaluation", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/evaluations/#{id}")}
  end
end
