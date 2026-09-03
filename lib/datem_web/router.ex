defmodule DatemWeb.Router do
  use DatemWeb, :router

  import DatemWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DatemWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  defp require_export_role(conn, _opts), do: require_role(conn, [:owner, :admin])

  scope "/", DatemWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", DatemWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:datem, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DatemWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview

      live "/scan-demo", DatemWeb.ScanDemoLive
    end
  end

  ## Authentication routes

  scope "/", DatemWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{DatemWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/dashboard", ReportingLive.Dashboard, :index
      live "/reports/access", ReportingLive.AccessReport, :index
      live "/reports/events", ReportingLive.EventReport, :index
      live "/exports", ReportingLive.Exports, :index
      live "/organization/members", OrganizationLive.Members, :index
      live "/organization/settings", OrganizationLive.Settings, :edit
      live "/sites", AccessLive.Sites, :index
      live "/access-points", AccessLive.AccessPoints, :index
      live "/visitors", AccessLive.Visitors, :index
      live "/visitors/:id", AccessLive.VisitorShow, :show
      live "/vehicles", AccessLive.Vehicles, :index
      live "/onsite", AccessLive.OnSite, :index
      live "/scan", AccessLive.ScanPicker, :index
      live "/scan/:id", AccessLive.Scan, :show
      live "/events", TicketingLive.Events, :index
      live "/events/:id", TicketingLive.EventShow, :show
      live "/events/:id/scan", TicketingLive.Scan, :show
      live "/scan-types", ScanningLive.ScanTypes, :index
      live "/checkpoints", ScanningLive.ScanPicker, :index
      live "/checkpoints/:id", ScanningLive.Scan, :show
    end

    post "/users/update-password", UserSessionController, :update_password
    get "/organizations/switch/:organization_id", OrganizationController, :switch
  end

  # Export downloads are tenant data served from outside priv/static, so they
  # get the same owner/admin gate as the exports list itself.
  scope "/", DatemWeb do
    pipe_through [:browser, :require_authenticated_user, :require_export_role]

    get "/exports/:id/download", ExportController, :download
  end

  scope "/", DatemWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{DatemWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/invitations/:token", OrganizationLive.AcceptInvitation, :new
      live "/visit/:token", AccessLive.PreRegistration, :new
      live "/join/:token", TicketingLive.Join, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
