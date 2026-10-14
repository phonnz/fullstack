defmodule Fullstack.JidoMarketAgents.Knowledge do
  @moduledoc "Runtime grounding documents packaged in the application's release-safe priv directory."

  @files %{six_systems: "six-systems-to-scale-a-business.md"}

  def fetch(key) do
    case Map.fetch(@files, key) do
      {:ok, filename} -> File.read(Application.app_dir(:fullstack, "priv/knowledge/" <> filename))
      :error -> {:error, :unknown_knowledge}
    end
  end
end
