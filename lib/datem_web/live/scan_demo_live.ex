defmodule DatemWeb.ScanDemoLive do
  @moduledoc """
  Design-system preview of the full-screen scanning view shell (dev only).
  """
  use DatemWeb, :live_view

  @results [
    idle: {"Ready to scan", nil},
    accepted: {"Jane Doe", "Checked in · 09:41"},
    duplicate: {"Jane Doe", "Already checked in at 09:12"},
    expired: {"Visitor pass #4821", "Pass expired at 18:00 yesterday"},
    denied: {"Unknown code", "Not registered for this event"}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, result: :idle, results: @results)}
  end

  def handle_event("set_result", %{"result" => result}, socket) do
    {:noreply, assign(socket, result: String.to_existing_atom(result))}
  end

  def render(assigns) do
    {title, subtitle} = assigns.results[assigns.result]
    assigns = assign(assigns, title: title, subtitle: subtitle)

    ~H"""
    <Layouts.scanning flash={@flash} title="Main Gate">
      <.scan_result result={@result} title={@title} subtitle={@subtitle} />

      <div class="flex flex-wrap justify-center gap-2">
        <.button
          :for={{result, _} <- @results}
          variant="secondary"
          phx-click="set_result"
          phx-value-result={result}
        >
          {Phoenix.Naming.humanize(result)}
        </.button>
      </div>
    </Layouts.scanning>
    """
  end
end
