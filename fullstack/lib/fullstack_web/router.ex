defmodule FullstackWeb.Router do
  use FullstackWeb, :router

  import FullstackWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FullstackWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FullstackWeb do
    pipe_through :browser

    resources "/about", AboutController, only: [:index]
    get "/u/:key", UrlRedirectController, :index

    # The site header renders inside the LiveView, so these public routes need
    # :current_user assigned to show the right account links. mount_current_user
    # uses assign_new and does not require a session, so anonymous mounts are fine.
    live_session :public, on_mount: [{FullstackWeb.UserAuth, :mount_current_user}] do
      live "/fibonacci", Public.FibonacciLive.Index, :index
      live "/transactions/:id", Public.TransactionLive
      live "/transactions", Public.TransactionsTableLive
      live "/Analitics", Public.TransactionsLive.PublicTransactions, :public_transactions
      live "/devices", Public.DevicesLive.Index, :index
      live "/agent", Public.AgentLive

      live "/chat", ChatLive
      live "/channels-chat", ChannelsChatLive

      live "/urls", UrlLive.Index, :index
      live "/urls/new", UrlLive.Index, :new
      live "/urls/:id/edit", UrlLive.Index, :edit

      live "/urls/:id", UrlLive.Show, :show
      live "/urls/:id/show/edit", UrlLive.Show, :edit

      live "/", HomeLive.Index, :index
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:fullstack, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    # Storybook routes are compiled only in dev/test (see elixirc_paths in
    # mix.exs). `use`/`import` are expanded by the compiler even inside a dead
    # `if` branch, so the call is emitted via Module.eval_quoted/2 — the AST is
    # only built when the module actually exists.
    if Code.ensure_loaded?(FullstackWeb.StorybookRoutes) do
      Module.eval_quoted(
        __MODULE__,
        quote(do: use(FullstackWeb.StorybookRoutes)),
        [],
        __ENV__
      )
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FullstackWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Catch-all route MUST be last — matches any "/:key"
  scope "/", FullstackWeb do
    pipe_through :browser
    live "/:key", HomeLive.Urls, :index
  end

  ## Authentication routes

  scope "/", FullstackWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{FullstackWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/admin", FullstackWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{FullstackWeb.UserAuth, :ensure_authenticated}] do
      live "/posts", PostLive.Index, :index
      live "/posts/new", PostLive.Index, :new
      live "/posts/:id/edit", PostLive.Index, :edit
      live "/posts/:id", PostLive.Show, :show
      live "/posts/:id/show/edit", PostLive.Show, :edit
      live "/customers", CustomerLive.Index, :index
      live "/customers/new", CustomerLive.Index, :new
      live "/customers/:id/edit", CustomerLive.Index, :edit
      live "/poss", PosLive.Index, :index
      live "/poss/new", PosLive.Index, :new
      live "/poss/:id/edit", PosLive.Index, :edit

      live "/poss/:id", PosLive.Show, :show
      live "/poss/:id/show/edit", PosLive.Show, :edit
      live "/customers/:id", CustomerLive.Show, :show
      live "/customers/:id/show/edit", CustomerLive.Show, :edit
      live "/transactions", TransactionLive.Index, :index

      live "/transactions/new", TransactionLive.Index, :new
      live "/transactions/:id/edit", TransactionLive.Index, :edit

      live "/transactions/:id", TransactionLive.Show, :show
      live "/transactions/:id/show/edit", TransactionLive.Show, :edit
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
      live "/devices", DeviceLive.Index, :index
      live "/devices/new", DeviceLive.Index, :new
      live "/devices/:id/edit", DeviceLive.Index, :edit
      live "/devices/:id", DeviceLive.Show, :show
      live "/devices/:id/show/edit", DeviceLive.Show, :edit
    end
  end

  scope "/", FullstackWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{FullstackWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end
end
