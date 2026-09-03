defmodule DatemWeb.PageController do
  use DatemWeb, :controller

  # A signed-in user's home is their organisation dashboard; the marketing
  # page is only for visitors who aren't in an organisation yet.
  def home(conn, _params) do
    case conn.assigns.current_scope do
      %{organization: %{}} -> redirect(conn, to: ~p"/dashboard")
      _ -> render(conn, :home)
    end
  end
end
