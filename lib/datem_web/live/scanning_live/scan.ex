defmodule DatemWeb.ScanningLive.Scan do
  @moduledoc """
  Full-screen scanning view for a configurable checkpoint. Shows the engine's
  verdict — accepted / duplicate / expired / denied — with the operator-facing
  message the rule engine produced, plus a live tally for the checkpoint.

  Reuses the same camera hook and scanning layout as the access and event
  scanning views.
  """
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Scanning

  @reset_after :timer.seconds(3)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    scan_type = Scanning.get_scan_type_for_scope!(scope, id)

    if connected?(socket), do: Scanning.subscribe(scope)

    {:ok,
     socket
     |> assign(:scan_type, scan_type)
     |> assign(:scanner_supported, true)
     |> assign_tally()
     |> assign_idle()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.scanning flash={@flash} title={@scan_type.name}>
      <p class="text-sm text-gray-500">{tally_label(@tally)}</p>

      <div id="scan-type-scanner" phx-hook=".QrScanner" phx-update="ignore" class="w-full max-w-sm">
        <video
          id="scan-type-scanner-video"
          class={["w-full rounded-2xl bg-black", !@scanner_supported && "hidden"]}
          autoplay
          muted
          playsinline
        />
        <script :type={Phoenix.LiveView.ColocatedHook} name=".QrScanner">
          export default {
            mounted() {
              this.cooldownUntil = 0

              if (!("BarcodeDetector" in window)) {
                this.pushEvent("scanner_unsupported", {})
                return
              }

              this.detector = new BarcodeDetector({formats: ["qr_code"]})
              this.video = this.el.querySelector("video")

              navigator.mediaDevices
                .getUserMedia({video: {facingMode: "environment"}})
                .then(stream => {
                  this.stream = stream
                  this.video.srcObject = stream
                  this.scan()
                })
                .catch(() => this.pushEvent("scanner_unsupported", {}))
            },

            scan() {
              if (!this.stream) return

              this.detector
                .detect(this.video)
                .then(codes => {
                  const now = Date.now()
                  if (codes.length > 0 && now >= this.cooldownUntil) {
                    this.cooldownUntil = now + 2000
                    this.pushEvent("scan", {code: codes[0].rawValue})
                  }
                })
                .catch(() => {})
                .finally(() => {
                  this.timer = setTimeout(() => this.scan(), 300)
                })
            },

            destroyed() {
              clearTimeout(this.timer)
              if (this.stream) this.stream.getTracks().forEach(track => track.stop())
            }
          }
        </script>
      </div>

      <.scan_result result={@result} title={@title} subtitle={@subtitle} />

      <form phx-submit="manual_scan" class="flex w-full max-w-sm gap-2">
        <input
          type="text"
          name="code"
          value=""
          placeholder="Or paste/type a Digital Link"
          class="flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm"
        />
        <.button type="submit">Scan</.button>
      </form>
    </Layouts.scanning>
    """
  end

  @impl true
  def handle_event("scan", %{"code" => code}, socket), do: {:noreply, process_scan(socket, code)}

  def handle_event("manual_scan", %{"code" => code}, socket) do
    {:noreply, process_scan(socket, String.trim(code))}
  end

  def handle_event("scanner_unsupported", _params, socket) do
    {:noreply, assign(socket, :scanner_supported, false)}
  end

  @impl true
  def handle_info(:reset, socket), do: {:noreply, assign_idle(socket)}

  def handle_info({:scan_logged, log}, socket) do
    if log.scan_type_id == socket.assigns.scan_type.id do
      {:noreply, assign_tally(socket)}
    else
      {:noreply, socket}
    end
  end

  defp process_scan(socket, ""), do: socket

  defp process_scan(socket, code) do
    scope = socket.assigns.current_scope

    result =
      case Scanning.scan(scope, socket.assigns.scan_type, code, scope.user) do
        {:ok, %{result: result, message: message, label: label}} ->
          assign_result(socket, result, label, message)

        {:error, reason} ->
          assign_result(socket, :denied, "Unknown code", message_for(reason))
      end

    Process.send_after(self(), :reset, @reset_after)
    result
  end

  defp assign_idle(socket), do: assign_result(socket, :idle, "Ready to scan", nil)

  defp assign_result(socket, result, title, subtitle) do
    socket |> assign(:result, result) |> assign(:title, title) |> assign(:subtitle, subtitle)
  end

  defp assign_tally(socket) do
    [tally] = Scanning.tallies(socket.assigns.current_scope, [socket.assigns.scan_type])
    assign(socket, :tally, tally)
  end

  defp tally_label(%{claimed: claimed, eligible: nil}), do: "#{claimed} scanned"

  defp tally_label(%{claimed: claimed, eligible: eligible}),
    do: "#{claimed} of #{eligible} claimed"

  defp message_for(:wrong_event), do: "This code is for a different event"
  defp message_for(:wrong_scope), do: "This code isn't valid at this checkpoint"
  defp message_for(:no_active_pass), do: "No active pass"
  defp message_for(:not_found), do: "Not registered at this organisation"
  defp message_for(_), do: "Not a recognised code"
end
