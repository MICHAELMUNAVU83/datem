defmodule DatemWeb.TicketingLive.Scan do
  @moduledoc """
  Full-screen check-in/out scanning view for an event, reusing the same
  camera hook and scanning layout as `DatemWeb.AccessLive.Scan`.
  """
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Ticketing

  @reset_after :timer.seconds(3)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    event = Ticketing.get_event_for_scope!(scope, id)

    {:ok,
     socket
     |> assign(:event, event)
     |> assign(:scanner_supported, true)
     |> assign(:manual_code, "")
     |> assign_idle()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.scanning flash={@flash} title={@event.name}>
      <div id="ticket-scanner" phx-hook=".QrScanner" phx-update="ignore" class="w-full max-w-sm">
        <video
          id="ticket-scanner-video"
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
    event = socket.assigns.event
    operator = scope.user

    case Ticketing.scan(scope, event, code, operator) do
      {:ok, _log, ticket, direction} ->
        Process.send_after(self(), :reset, @reset_after)

        assign_result(
          socket,
          :accepted,
          ticket.attendee_name,
          "Checked #{direction} · #{time_now()}"
        )

      {:error, reason, ticket} ->
        Process.send_after(self(), :reset, @reset_after)
        assign_result(socket, result_for(reason), ticket.attendee_name, message_for(reason))

      {:error, reason} ->
        Process.send_after(self(), :reset, @reset_after)
        assign_result(socket, :denied, "Unknown code", message_for(reason))
    end
    |> assign(:manual_code, "")
  end

  defp assign_idle(socket), do: assign_result(socket, :idle, "Ready to scan", nil)

  defp assign_result(socket, result, title, subtitle) do
    socket |> assign(:result, result) |> assign(:title, title) |> assign(:subtitle, subtitle)
  end

  defp result_for(:already_inside), do: :duplicate
  defp result_for(_), do: :denied

  defp message_for(:cancelled), do: "This ticket has been cancelled"
  defp message_for(:already_inside), do: "Already checked in"
  defp message_for(:not_inside), do: "Not currently checked in"
  defp message_for(:wrong_event), do: "This ticket is for a different event"
  defp message_for(:not_found), do: "Not registered at this organisation"
  defp message_for(_), do: "Not a recognised code"

  defp time_now, do: Calendar.strftime(DateTime.utc_now(), "%H:%M")
end
