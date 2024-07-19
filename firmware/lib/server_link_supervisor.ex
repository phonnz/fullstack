defmodule Firmware.ServerLinkSupervisor do
  use Supervisor

  @sockets_count 1000
  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      Supervisor.child_spec({Firmware.ServerLink, []}, id: :firmware_0),
      Supervisor.child_spec({Firmware.ServerLink, [id: "1", mac_addr: "a8:27:eb:5a:70:b2"]},
        id: :firmware_1
      ),
      Supervisor.child_spec({Firmware.ServerLink, [id: "2", mac_addr: "e4:5f:01:63:91:2b"]},
        id: :firmware_2
      ),
      Supervisor.child_spec({Firmware.ServerLink, [id: "3", mac_addr: "e4:5f:01:43:3e:6a"]},
        id: :firmware_3
      ),
      Supervisor.child_spec({Firmware.ServerLink, [id: "4", mac_addr: "e4:5f:01:a1:b1:f4"]},
        id: :firmware_4
      )
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  ## def children_spec do
  ##   0..(@sockets_count - 1)
  ##   |> Enum.map(fn i ->
  ##     process_name = String.to_atom("Firmware.ServerLink.#{i}")

  ##     Supervisor.child_spec({Firmware.ServerLink, name: process_name},
  ##       id: {Firmware.ServerLink, i}
  ##     )
  ##   end)
  ## end
end
