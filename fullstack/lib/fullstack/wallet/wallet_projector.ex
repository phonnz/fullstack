defmodule Fullstack.Wallet.WalletProjector do
  def start(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    {}
end

