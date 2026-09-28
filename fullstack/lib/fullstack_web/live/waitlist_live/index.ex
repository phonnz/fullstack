defmodule FullstackWeb.WaitlistLive.Index do
  use FullstackWeb, :live_view

  alias Fullstack.Waitlist
  alias Fullstack.Waitlist.Signup
  alias FullstackWeb.WaitlistLive.Countries

  @impl true
  def mount(_params, _session, socket) do
    changeset = Waitlist.change_signup(%Signup{})

    {:ok,
     socket
     |> assign(:country_options, Countries.options())
     |> assign(:signed_up, false)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"signup" => signup_params}, socket) do
    changeset =
      %Signup{}
      |> Waitlist.change_signup(signup_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"signup" => signup_params}, socket) do
    signup_params = Map.update(signup_params, "country", nil, &Countries.normalize/1)

    case Waitlist.create_signup(signup_params) do
      {:ok, _signup} ->
        changeset = Waitlist.change_signup(%Signup{})

        {:noreply,
         socket
         |> assign(:signed_up, true)
         |> assign(:form, to_form(changeset))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
