defmodule Fullstack.Wallet.Wallet do
  defstruct(:customer, :assets, credits: 213)

  def init(customer) do
    %__MODULE__{customer: customer}
  end
end
