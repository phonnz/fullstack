defmodule FullstackWeb.Plugs.HostRewrite do
  @moduledoc """
  Rewrites the root path (`/`) to a per-host destination path.

  This lets a single Phoenix release serve different landing content per
  virtual host (e.g. `chat.agentson.live` -> `/chat`) without duplicating
  the endpoint or running separate routers.

  `Phoenix.Router.call/2` matches the request route by pattern-matching
  `conn.path_info` (the path already split into segments) — and it does
  this *before* running any pipeline plug. Pipelines only execute for
  whichever route already matched; they never influence the match itself.
  A plug placed inside a router pipeline (or one that only rewrites
  `conn.request_path`, a cosmetic string) therefore has no effect on which
  route is dispatched to. This plug must run on the `Phoenix.Endpoint`,
  before `plug MyAppWeb.Router`, so the rewritten `path_info` is what the
  router actually matches against. `request_path` is kept in sync purely
  for consistency with anything downstream that inspects it (redirects,
  logs, telemetry) — it plays no role in routing.

  The host -> path mapping is read from application config so it is data,
  not a hardcoded rule, and can differ between environments:

      config :fullstack, :host_roots, %{
        "chat.agentson.live" => "/chat",
        "agentson.live" => "/about"
      }

  Only the root path is rewritten. Any other path, and any host not present
  in the mapping, passes through unchanged.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: []} = conn, _opts) do
    host_roots = Application.get_env(:fullstack, :host_roots, %{})

    case Map.fetch(host_roots, conn.host) do
      {:ok, path} ->
        segments = path |> String.split("/", trim: true)

        conn
        |> Map.put(:path_info, segments)
        |> Map.put(:request_path, path)

      :error ->
        conn
    end
  end

  def call(conn, _opts), do: conn
end
