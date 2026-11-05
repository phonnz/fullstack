if Code.ensure_loaded?(PhoenixStorybook) do
  defmodule FullstackWeb.Storybook do
    @moduledoc false
    use PhoenixStorybook,
      otp_app: :fullstack,
      content_path: Path.expand("../../storybook", __DIR__),
      sandbox_class: "fullstack-sandbox"
  end
end
