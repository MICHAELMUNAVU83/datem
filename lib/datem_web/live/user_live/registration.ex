defmodule DatemWeb.UserLive.Registration do
  use DatemWeb, :live_view

  alias Datem.{Accounts, Organizations, Repo}
  alias Datem.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
     <Layouts.auth flash={@flash}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-blue-600 hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            name="organization[name]"
            value={@organization_name}
            type="text"
            label="Organisation name"
            placeholder="Acme Inc."
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />

          <.button phx-disable-with="Creating account..." class="w-full">
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: DatemWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, socket |> assign(:organization_name, "") |> assign_form(changeset),
     temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params} = params, socket) do
    organization_name = get_in(params, ["organization", "name"]) || ""

    result =
      Repo.transact(fn ->
        with {:ok, user} <- Accounts.register_user(user_params),
             {:ok, _} <- Organizations.create_organization_with_owner(user, organization_name) do
          {:ok, user}
        end
      end)

    case result do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{data: %User{}} = changeset} ->
        {:noreply,
         socket |> assign(:organization_name, organization_name) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:organization_name, organization_name)
         |> put_flash(
           :error,
           "Couldn't create your organisation: #{changeset_error_summary(changeset)}"
         )}
    end
  end

  def handle_event("validate", %{"user" => user_params} = params, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)

    {:noreply,
     socket
     |> assign(:organization_name, get_in(params, ["organization", "name"]) || "")
     |> assign_form(Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end

  defp changeset_error_summary(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
  end
end
