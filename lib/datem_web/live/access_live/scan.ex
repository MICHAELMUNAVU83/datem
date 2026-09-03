defmodule DatemWeb.AccessLive.Scan do
  @moduledoc """
  Full-screen scanning view for an access point: decodes a GS1 Digital
  Link QR code (camera, via the browser's BarcodeDetector API, with a
  manual-entry fallback), resolves it, and records the scan.
  """
  use DatemWeb, :live_view

  alias Datem.Access

  @reset_after :timer.seconds(3)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    access_point = Access.get_access_point_for_scope!(scope, id)

    {:ok,
     socket
     |> assign(:access_point, access_point)
     |> assign(:scanner_supported, true)
     |> assign(:manual_code, "")
     |> assign_idle()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.scanning flash={@flash} title={@access_point.name}>
      <div id="qr-scanner" phx-hook=".QrScanner" phx-update="ignore" class="w-full max-w-sm">
        <video
          id="qr-scanner-video"
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
          value={@manual_code}
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

  defp process_scan(socket, ""), do: socket

  defp process_scan(socket, code) do
    scope = socket.assigns.current_scope
    access_point = socket.assigns.access_point
    operator = scope.user

    case Access.scan(scope, access_point, code, operator) do
      {:ok, _log, entity, direction} ->
        Process.send_after(self(), :reset, @reset_after)

        assign_result(
          socket,
          :accepted,
          entity_name(entity),
          "Checked #{direction} · #{time_now()}"
        )

      {:error, reason, entity} ->
        Process.send_after(self(), :reset, @reset_after)
        broadcast_denial(scope, access_point, entity_name(entity), reason)
        assign_result(socket, result_for(reason), entity_name(entity), message_for(reason))

      {:error, reason} ->
        Process.send_after(self(), :reset, @reset_after)
        broadcast_denial(scope, access_point, "Unknown code", reason)
        assign_result(socket, :denied, "Unknown code", message_for(reason))
    end
    |> assign(:manual_code, "")
  end

  defp broadcast_denial(scope, access_point, name, reason) do
    org_id = Datem.Tenancy.organization_id!(scope)

    Phoenix.PubSub.broadcast(
      Datem.PubSub,
      Access.access_logs_topic(org_id),
      {:access_denied,
       %{access_point: access_point, name: name, reason: reason, at: DateTime.utc_now()}}
    )
  end

  defp assign_idle(socket), do: assign_result(socket, :idle, "Ready to scan", nil)

  defp assign_result(socket, result, title, subtitle) do
    socket |> assign(:result, result) |> assign(:title, title) |> assign(:subtitle, subtitle)
  end

  defp result_for(:expired), do: :expired
  defp result_for(:already_inside), do: :duplicate
  defp result_for(_), do: :denied

  defp message_for(:expired), do: "Pass has expired"
  defp message_for(:revoked), do: "This pass has been revoked"
  defp message_for(:already_inside), do: "Already checked in"
  defp message_for(:not_inside), do: "Not currently checked in"
  defp message_for(:no_active_pass), do: "No active pass for this visitor"
  defp message_for(:not_found), do: "Not registered at this organisation"
  defp message_for(_), do: "Not a recognised code"

  defp entity_name(%Datem.Access.Visitor{name: name}), do: name
  defp entity_name(%Datem.Access.Vehicle{plate: plate}), do: plate

  defp time_now, do: Calendar.strftime(DateTime.utc_now(), "%H:%M")
end
