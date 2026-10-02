defmodule DatemWeb.PassesLive.CarPassDecision do
  @moduledoc """
  Public, unauthenticated approve/decline page for a car pass, reached via
  the emailed review link. Deciding happens on explicit button click, not
  on mount — a link-scanning email client prefetching the URL would
  otherwise silently consume it before a human ever sees the page.
  """
  use DatemWeb, :live_view

  alias Datem.Passes
  alias Datem.NairobiTime

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    pass = Passes.get_car_pass_by_token(token)

    {:ok,
     socket
     |> assign(:pass, pass)
     |> assign(:decided, false)
     |> assign(:show_deny_reason, false)
     |> assign(:deny_reason, "")}
  end

  @impl true
  def render(%{pass: nil} = assigns) do
    ~H"""
    <.shell>
      <p class="text-gray-700">This link is invalid or has already been used.</p>
    </.shell>
    """
  end

  def render(%{decided: true} = assigns) do
    ~H"""
    <.shell>
      <p class="text-lg font-semibold text-gray-900">Request {@pass.status}.</p>
      <p class="mt-2 text-sm text-gray-600">
        The car pass "{@pass.serial}" requested by {@pass.requested_by.name} has been recorded.
      </p>
    </.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <.shell>
      <h2 class="text-base font-semibold text-gray-900">
        {@pass.requested_by.name} needs {vehicle_label(@pass)} — {@pass.serial}
      </h2>
      <p :if={@pass.carrying} class="mt-2 text-sm text-gray-600">Carrying: {@pass.carrying}</p>
      <p class="mt-3 text-sm text-gray-700">{@pass.reason}</p>
      <p class="mt-2 text-xs text-gray-500">
        Requested {NairobiTime.format(@pass.inserted_at, "%d %b %H:%M")}
      </p>

      <div class="mt-6 flex gap-3">
        <.button phx-click="approve">Approve</.button>
        <.button type="button" variant="secondary" phx-click="show_deny">Decline</.button>
      </div>

      <div :if={@show_deny_reason} class="mt-4">
        <label class="mb-1 block text-sm font-medium text-gray-700">Reason for declining</label>
        <textarea
          phx-blur="set_deny_reason"
          name="reason"
          class="w-full rounded-lg border-gray-300 text-sm"
          rows="3"
        >{@deny_reason}</textarea>
        <.button variant="danger" class="mt-3" phx-click="deny">Confirm decline</.button>
      </div>
    </.shell>
    """
  end

  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  defp shell(assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center bg-gray-50 px-4">
      <div class="w-full max-w-md rounded-xl border border-gray-200 bg-white p-8 shadow-sm">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("approve", _params, socket) do
    {:ok, pass} = Passes.decide_car_pass(socket.assigns.pass, "approved")
    {:noreply, socket |> assign(:pass, pass) |> assign(:decided, true)}
  end

  def handle_event("show_deny", _params, socket), do: {:noreply, assign(socket, :show_deny_reason, true)}
  def handle_event("set_deny_reason", %{"value" => reason}, socket), do: {:noreply, assign(socket, :deny_reason, reason)}

  def handle_event("deny", _params, socket) do
    {:ok, pass} = Passes.decide_car_pass(socket.assigns.pass, "denied", socket.assigns.deny_reason)
    {:noreply, socket |> assign(:pass, pass) |> assign(:decided, true)}
  end

  defp vehicle_label(%{vehicle: %{plate: plate}}), do: plate
  defp vehicle_label(_pass), do: "an unassigned vehicle"
end
