defmodule DatemWeb.AccessLive.PreRegistration do
  use DatemWeb, :live_view

  alias Datem.Access
  alias Datem.Access.Visitor
  alias Datem.GS1

  @impl true
  def render(%{visitor: nil} = assigns) do
    ~H"""
    <.public_shell>
      <div class="flex flex-col items-center gap-3 text-center">
        <div class="flex size-14 items-center justify-center rounded-full bg-red-50">
          <.icon name="hero-x-circle" class="size-7 text-red-500" />
        </div>
        <p class="text-gray-700">This pre-registration link is invalid or has already been used.</p>
      </div>
    </.public_shell>
    """
  end

  def render(%{awaiting_approval: true} = assigns) do
    ~H"""
    <.public_shell>
      <div class="flex flex-col items-center gap-3 text-center">
        <div class="flex size-14 items-center justify-center rounded-full bg-amber-50">
          <.icon name="hero-clock" class="size-7 text-amber-500" />
        </div>
        <p class="text-lg font-semibold text-gray-900">You're registered, {@visitor.name}</p>
        <p class="text-sm text-gray-600">
          {@visitor.host} needs to approve this visit before your pass is issued. You'll get an
          email with your QR code as soon as that happens.
        </p>
      </div>
    </.public_shell>
    """
  end

  def render(%{pass: pass} = assigns) when not is_nil(pass) do
    ~H"""
    <.public_shell>
      <div class="flex flex-col items-center gap-4 text-center">
        <div class="flex size-14 items-center justify-center rounded-full bg-green-50">
          <.icon name="hero-check-circle" class="size-7 text-green-500" />
        </div>
        <div>
          <p class="text-lg font-semibold text-gray-900">You're all set, {@visitor.name}</p>
          <p class="mt-1 text-sm text-gray-600">Show this QR code at the gate.</p>
        </div>
        <div class="rounded-2xl border border-gray-100 bg-gray-50 p-4">
          {Phoenix.HTML.raw(GS1.qr_svg(@pass.gs1_identifier.digital_link, width: 220))}
        </div>
        <p :if={@visitor.email} class="text-xs text-gray-400">
          We've also emailed your pass to {@visitor.email}.
        </p>
      </div>
    </.public_shell>
    """
  end

  def render(assigns) do
    ~H"""
    <.public_shell>
      <p class="mb-6 text-sm text-gray-600">
        Hosted by <span class="font-medium text-gray-900">{@visitor.host}</span>. Please fill in your details below.
      </p>

      <.form for={@form} id="pre_registration_form" phx-submit="save" phx-change="validate" class="space-y-4">
        <.input field={@form[:name]} type="text" label="Full name" required />
        <.input field={@form[:contact]} type="text" label="Contact (phone/email)" required />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:company]} type="text" label="Company" />
        <.input field={@form[:id_number]} type="text" label="ID / passport number" />
        <.input field={@form[:vehicle_reg]} type="text" label="Vehicle reg (if driving)" />
        <.input field={@form[:purpose]} type="textarea" label="Purpose of visit" />

        <.button phx-disable-with="Registering..." class="mt-2 w-full py-3 text-base">
          Get my pass
        </.button>
      </.form>
    </.public_shell>
    """
  end

  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  defp public_shell(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-gradient-to-b from-blue-50 to-gray-50 px-4 py-8 sm:items-center sm:justify-center sm:py-12">
      <div class="mx-auto w-full max-w-md">
        <div class="mb-6 flex justify-center">
          <span class="text-lg font-semibold tracking-tight text-blue-600">Datem</span>
        </div>

        <div class="rounded-2xl border border-gray-100 bg-white p-6 shadow-lg shadow-gray-200/50 sm:p-8">
          <h1 class="mb-4 text-xl font-semibold text-gray-900">Pre-registration</h1>
          {render_slot(@inner_block)}
        </div>

        <p class="mt-6 text-center text-xs text-gray-400">Powered by GS1 Kenya</p>
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
     |> assign(:awaiting_approval, false)
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
      {:ok, %{visitor: visitor, pass: nil}} ->
        {:noreply, socket |> assign(:visitor, visitor) |> assign(:awaiting_approval, true)}

      {:ok, %{visitor: visitor, pass: pass}} ->
        {:noreply, socket |> assign(:visitor, visitor) |> assign(:pass, pass)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "visitor"))}
    end
  end
end
