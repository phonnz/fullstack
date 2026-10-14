defmodule Fullstack.JidoMarketAgents.Knowledge do
  @moduledoc "Runtime grounding documents packaged in the application's release-safe priv directory."

  @files %{
    six_systems: "six-systems-to-scale-a-business.md",
    tech_adoption: "guia-implementacion-ia-pymes.md"
  }

  @doc "Resolves grounding before provider dispatch; missing or blank content is never usable."
  @spec fetch(atom()) :: {:ok, String.t()} | {:error, :not_configured | :unknown_knowledge}
  def fetch(key) do
    case Map.fetch(@files, key) do
      {:ok, filename} ->
        module = Application.get_env(:fullstack, :knowledge_module, __MODULE__)

        result =
          if module == __MODULE__ do
            File.read(Application.app_dir(:fullstack, "priv/knowledge/" <> filename))
          else
            configured_fetch(module, key)
          end

        validate_content(result)

      :error ->
        {:error, :unknown_knowledge}
    end
  end

  defp configured_fetch(module, key) when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :fetch, 1),
      do: module.fetch(key),
      else: {:error, :not_configured}
  end

  defp configured_fetch(_module, _key), do: {:error, :not_configured}

  defp validate_content({:ok, content}) when is_binary(content) do
    if String.valid?(content) and String.trim(content) != "",
      do: {:ok, content},
      else: {:error, :not_configured}
  end

  defp validate_content(_result), do: {:error, :not_configured}
end
