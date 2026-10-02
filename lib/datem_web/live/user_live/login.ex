defmodule DatemWeb.UserLive.Login do
  use DatemWeb, :live_view

  alias Datem.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="space-y-8">
        <.header>
          <p>Log in</p>
          <:subtitle>
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Don't have an account? <.link
                navigate={~p"/users/register"}
                class="font-semibold text-blue-600 hover:underline"
                phx-no-format
              >Sign up</.link> for an account now.
            <% end %>
          </:subtitle>
        </.header>

        <div class="flex items-center gap-2 text-xs font-medium text-gray-400">
          <.icon name="hero-lock-closed" class="size-3.5" /> Secure sign-in
        </div>

        <div class="grid grid-cols-2 gap-1 rounded-lg bg-gray-50 p-1 text-sm font-medium">
          <button
            type="button"
            phx-click="switch_method"
            phx-value-method="magic"
            class={[
              "rounded-md px-3 py-2 transition-colors",
              (@login_method == "magic" && "bg-white text-gray-900 shadow-sm") ||
                "text-gray-500 hover:text-gray-700"
            ]}
          >
            Email link
          </button>
          <button
            type="button"
            phx-click="switch_method"
            phx-value-method="password"
            class={[
              "rounded-md px-3 py-2 transition-colors",
              (@login_method == "password" && "bg-white text-gray-900 shadow-sm") ||
                "text-gray-500 hover:text-gray-700"
            ]}
          >
            Password
          </button>
        </div>

        <.form
          :if={@login_method == "magic"}
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
          class="space-y-5"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="w-full">
            Log in with email <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <.form
          :if={@login_method == "password"}
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
          class="space-y-5"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
          />
          <div class="space-y-2">
            <.button class="w-full" name={@form[:remember_me].name} value="true">
              Log in and stay logged in <span aria-hidden="true">→</span>
            </.button>
            <.button variant="secondary" class="w-full">
              Log in only this time
            </.button>
          </div>
        </.form>
      </div>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false, login_method: "magic")}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("switch_method", %{"method" => method}, socket) do
    {:noreply, assign(socket, :login_method, method)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end
end
