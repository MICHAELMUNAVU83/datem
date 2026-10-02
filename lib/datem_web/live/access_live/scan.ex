defmodule DatemWeb.AccessLive.Scan do
  @moduledoc """
  Full-screen scanning view for an access point: decodes a GS1 Digital
  Link QR code (camera, via the browser's BarcodeDetector API, with a
  manual-entry fallback), resolves it, and records the scan.
  """
  use DatemWeb, :live_view

  alias Datem.Access
  alias Datem.Organizations


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
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:denied_visitor_id, nil)
     |> assign(:last_scanned_code, nil)
     |> assign(:employees, Organizations.list_employees(scope))
|> assign(:renew_host_employee_id, nil)
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

      <.button
        :if={@result == :expired and @denied_visitor_id}
        phx-click="renew_and_rescan"
        class="w-full max-w-sm"
      >
        Renew pass & retry
      </.button>
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

      <div class="w-full max-w-sm">
        <p class="mb-1 text-center text-xs text-gray-400">— or —</p>
        <input
          type="text"
          phx-keyup="search_visitors"
          phx-debounce="300"
          value={@search_query}
          placeholder="Search a visitor by name or ID"
          class="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm"
        />

        <ul
          :if={@search_results != []}
          class="mt-2 divide-y divide-gray-100 rounded-lg border border-gray-200 bg-white"
        >
          <li :for={v <- @search_results} class="flex items-center justify-between px-3 py-2">
            <span class="text-sm text-gray-900">{v.name}</span>
            <.button phx-click="manual_visitor_scan" phx-value-id={v.id}>Scan</.button>
          </li>
        </ul>
      </div>
      <div :if={@result == :expired and @denied_visitor_id} class="w-full max-w-sm space-y-2">
        <select
          name="renew_host_employee_id"
          phx-change="set_renew_host"
          class="w-full rounded-lg border border-gray-300 px-3 py-2 text-base shadow-sm focus:border-blue-600 focus:ring-1 focus:ring-blue-600 sm:text-sm"
        >
          <option value="">Same host as before</option>
          <option :for={e <- @employees} value={e.id}>{e.name}</option>
        </select>
        <.button phx-click="renew_and_rescan" class="w-full">Renew pass & retry</.button>
      </div>
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

  def handle_event("search_visitors", %{"value" => query}, socket) do
    scope = socket.assigns.current_scope
    results = if query == "", do: [], else: Access.search_visitors(scope, query)

    {:noreply, socket |> assign(:search_query, query) |> assign(:search_results, results)}
  end

  def handle_event("set_renew_host", %{"renew_host_employee_id" => id}, socket) do
  {:noreply, assign(socket, :renew_host_employee_id, id == "" && nil || String.to_integer(id))}
end

def handle_event("renew_and_rescan", _params, socket) do
  scope = socket.assigns.current_scope
  visitor = Access.get_visitor_for_scope!(scope, socket.assigns.denied_visitor_id)

  attrs =
    case socket.assigns.renew_host_employee_id do
      nil -> %{}
      employee_id ->
        employee = Enum.find(socket.assigns.employees, &(&1.id == employee_id))
        %{"host_employee_id" => employee_id, "host" => employee.name}
    end

  case Access.renew_pass(scope, visitor, attrs) do
    {:ok, _} ->
      {:noreply,
       socket
       |> assign(:denied_visitor_id, nil)
       |> assign(:renew_host_employee_id, nil)
       |> process_scan(socket.assigns.last_scanned_code)}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Couldn't renew that pass.")}
  end
end
  def handle_event("manual_visitor_scan", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    access_point = socket.assigns.access_point
    operator = scope.user
    visitor = Access.get_visitor_for_scope!(scope, id)

    socket =
      case Access.manual_scan_visitor(scope, visitor, access_point, operator) do
        {:ok, _log, direction} ->
          Process.send_after(self(), :reset, @reset_after)
          assign_result(socket, :accepted, visitor.name, "Checked #{direction} · #{time_now()}")

        {:error, :no_active_pass} ->
          Process.send_after(self(), :reset, @reset_after)
          assign_result(socket, :denied, visitor.name, "No active pass for this visitor")

        {:error, reason} ->
          Process.send_after(self(), :reset, @reset_after)
          assign_result(socket, :denied, visitor.name, message_for(reason))
      end

    {:noreply, socket |> assign(:search_query, "") |> assign(:search_results, [])}
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

        socket
        |> assign_result(result_for(reason), entity_name(entity), message_for(reason))
        |> maybe_track_expired(reason, entity, code)

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

  defp maybe_track_expired(socket, :expired, %Datem.Access.Visitor{id: id}, code) do
    socket |> assign(:denied_visitor_id, id) |> assign(:last_scanned_code, code)
  end

  defp maybe_track_expired(socket, _reason, _entity, _code),
    do: assign(socket, :denied_visitor_id, nil)

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

  defp time_now, do: Datem.NairobiTime.format(DateTime.utc_now(), "%H:%M")
end
