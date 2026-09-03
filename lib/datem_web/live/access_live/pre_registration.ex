defmodule DatemWeb.AccessLive.PreRegistration do
  use DatemWeb, :live_view

  alias Datem.Access
  alias Datem.Access.Visitor
  alias Datem.GS1

  @impl true
  def render(%{visitor: nil} = assigns) do
    ~H"""
    <.public_shell>
      <p class="text-gray-700">This pre-registration link is invalid or has already been used.</p>
    </.public_shell>
    """
  end

  def render(%{pass: pass} = assigns) when not is_nil(pass) do
    ~H"""
    <.public_shell>
      <p class="mb-4 text-gray-700">You're registered. Show this QR code at the gate.</p>
      <div class="flex justify-center rounded-lg border border-gray-200 p-4">
        {Phoenix.HTML.raw(GS1.qr_svg(@pass.gs1_identifier.digital_link, width: 220))}
      </div>
    </.public_shell>
    """
  end

  def render(assigns) do
    ~H"""
    <.public_shell>
      <p class="mb-4 text-sm text-gray-600">
        Hosted by {@visitor.host}. Please fill in your details.
      </p>

      <.form for={@form} id="pre_registration_form" phx-submit="save" phx-change="validate">
        <.input field={@form[:name]} type="text" label="Full name" required />
        <.input field={@form[:contact]} type="text" label="Contact (phone/email)" required />
        <.input field={@form[:company]} type="text" label="Company" />
        <div class="mt-4">
          <.button phx-disable-with="Registering...">Get my pass</.button>
        </div>
      </.form>
    </.public_shell>
    """
  end

  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  defp public_shell(assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-md rounded-xl border border-gray-200 bg-white p-8 shadow-sm">
        <h1 class="mb-1 text-lg font-semibold text-gray-900">Pre-registration</h1>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    visitor = Access.get_pending_pre_registration_by_token(token)

    {:ok,
     socket
     |> assign(:visitor, visitor)
     |> assign(:pass, nil)
     |> assign(
       :form,
       visitor && to_form(Visitor.self_registration_changeset(visitor, %{}), as: "visitor")
     )}
  end

  @impl true
  def handle_event("validate", %{"visitor" => params}, socket) do
    changeset =
      socket.assigns.visitor
      |> Visitor.self_registration_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "visitor"))}
  end

  def handle_event("save", %{"visitor" => params}, socket) do
    case Access.complete_pre_registration(socket.assigns.visitor, params) do
      {:ok, %{pass: pass}} ->
        {:noreply, assign(socket, :pass, pass)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "visitor"))}
    end
  end
end
