defmodule FullstackWeb.Public.WalletLive.Index do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :stocks, [%{"$LIBRE" => 2.23}, %{"TRUMP" => 4.5}])}
  end

  def render(assigns) do
    ~H"""
    <div class="container px-4 py-8 mx-auto">
  <%# Chart placeholder %>
  <div class="flex justify-center items-center p-4 mb-8 h-64 bg-gray-100 rounded-lg">
    <p class="text-gray-500">Price Chart Coming Soon</p>
  </div>

  <%# Crypto list %>
  <div class="bg-white rounded-lg shadow">
    <div class="grid grid-cols-5 gap-4 p-4 font-semibold bg-gray-50 border-b border-gray-200">
      <div>Rank</div>
      <div>Name</div>
      <div>Price</div>
      <div>24h Change</div>
      <div>Market Cap</div>
    </div>

      <div :for={{coin, index} <- Enum.with_index(@stocks, 1)} id={to_string(index)} >
     <div :for={{name, price} <- coin } id={name} class="grid grid-cols-5 gap-4 p-4 border-b border-gray-100 hover:bg-gray-50">
        <div class="text-gray-600">#<%= name %></div>
        <div class="flex items-center">
          <span class="font-medium"><%= name %></span>
        </div>
        <div class="font-mono">
          $<%= price %>
        </div>
        <div class={if price >= 0, do: "text-green-600", else: "text-red-600"}>
          $ <%= Float.round(price, 2) %>
        </div>
        <div class="font-mono">
          $<%= price %>
        </div>
      </div>
      </div>
  </div>
</div>
    """
  end
end
