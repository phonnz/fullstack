defmodule Fullstack.EcosystemLogo do
  defstruct [:id, :logo_path, :name, :link]
end

defmodule Fullstack.EcosystemLogos do
  def list do
    [
      %Fullstack.EcosystemLogo{
        id: "phoenix",
        name: "Phoenix",
        logo_path: "/img/phoenix.svg",
        link: "https://phoenixframework.org"
      },
      %Fullstack.EcosystemLogo{
        id: "nx",
        name: "Nx",
        logo_path: "https://avatars.githubusercontent.com/u/74903619?s=200&v=4",
        link: "https://github.com/elixir-nx"
      },
      %Fullstack.EcosystemLogo{
        id: "nerves",
        name: "Nerves",
        logo_path: "https://hexdocs.pm/nerves/assets/logo.png",
        link: "https://nerves-project.org"
      },
      %Fullstack.EcosystemLogo{
        id: "livebook",
        name: "Livebook",
        logo_path: "/img/livebook.svg",
        link: "https://livebook.dev"
      }
    ]
  end
end
