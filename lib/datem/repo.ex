defmodule Datem.Repo do
  use Ecto.Repo,
    otp_app: :datem,
    adapter: Ecto.Adapters.Postgres
end
