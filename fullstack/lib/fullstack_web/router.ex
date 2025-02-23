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
    live "/fibonacci", Public.FibonacciLive.Index, :index
    live "/transactions", Public.TransactionsLive.PublicTransactions, :public_transactions
    live "/devices", Public.DevicesLive.Index, :index
    live "/wallet", Public.WalletLive.Index, :index

    resources "/about", AboutController, only: [:index]
    live "/chat", ChatLive
    live "/devices", DeviceLive.Index, :index
    live "/devices/new", DeviceLive.Index, :new
    live "/devices/:id/edit", DeviceLive.Index, :edit

    live "/devices/:id", DeviceLive.Show, :show
    live "/devices/:id/show/edit", DeviceLive.Show, :edit

    live "/urls", UrlLive.Index, :index
    live "/urls/new", UrlLive.Index, :new
    live "/urls/:id/edit", UrlLive.Index, :edit

    live "/urls/:id", UrlLive.Show, :show
    live "/urls/:id/show/edit", UrlLive.Show, :edit
    get "/u/:key", UrlRedirectController, :index
    live "/:key", HomeLive.Urls, :index

    live "/", HomeLive.Index, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", FullstackWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:fullstack, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FullstackWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
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

  scope "/", FullstackWeb do
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
