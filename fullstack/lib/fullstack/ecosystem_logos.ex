defmodule Fullstack.EcosystemLogo do
  defstruct [:id, :logo_path, :name]
end

defmodule Fullstack.EcosystemLogos do
  def list do
    [
      %Fullstack.EcosystemLogo{
        id: "phoenix",
        name: "Phoenix",
        logo_path: ""
      },
      %Fullstack.EcosystemLogo{
        id: "nx",
        name: "Nx",
        logo_path: ""
      },
      %Fullstack.EcosystemLogo{
        id: "nerves",
        name: "Nerves",
        logo_path: ""
      },
      %Fullstack.EcosystemLogo{
        id: "livebook",
        name: "Livebook",
        logo_path: ""
      }
    ]
  end
end
