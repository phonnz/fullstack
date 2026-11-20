defmodule FullstackWeb.WhatsAppLoginHTML do
  use FullstackWeb, :html

  def show(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm px-4 py-16 text-center">
      <h1 class="text-2xl font-semibold text-base-content">Open your results</h1>
      <p class="mt-2 text-base-content/70">
        You are signing in with the link we sent you on WhatsApp.
      </p>
      <.form
        for={to_form(%{}, as: :whatsapp_login)}
        action={~p"/whatsapp/login/#{@token}"}
        method="post"
        class="mt-6"
      >
        <input type="hidden" name="conversation_id" value={@conversation_id} />
        <button type="submit" class="btn btn-primary w-full">Continue</button>
      </.form>
    </div>
    """
  end
end
