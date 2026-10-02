defmodule DatemWeb.TicketingLive.PublicTicket do
  @moduledoc """
  Public, unauthenticated page shown when a ticket's QR code is scanned
  directly with a phone camera (rather than at a staff checkpoint).
  Display-only — it never toggles check-in/out; that stays staff-only via
  `TicketingLive.Scan`.
  """
  use DatemWeb, :live_view

  alias Datem.NairobiTime
  alias Datem.Ticketing

  @impl true
  def mount(%{"gsrn" => gsrn}, _session, socket) do
    ticket = Ticketing.get_ticket_by_gsrn(gsrn)
    content_items = ticket && Ticketing.list_public_content_items(ticket.event_id)
    schedule_items = ticket && Ticketing.list_public_schedule_items(ticket.event_id)

    {:ok,
     socket
     |> assign(:ticket, ticket)
     |> assign(:banner, content_items && Enum.find(content_items, &(&1.kind == "banner")))
     |> assign(:links, content_items && Enum.filter(content_items, &(&1.kind == "link")))
     |> assign(:schedule_days, schedule_items && Ticketing.group_schedule_by_day(schedule_items))}
  end

  @impl true
  def render(%{ticket: nil} = assigns) do
    ~H"""
    <.public_shell>
      <div class="px-6 py-16 text-center">
        <.icon name="hero-ticket" class="mx-auto size-10 text-gray-300" />
        <p class="mt-4 text-base font-medium text-gray-900">Ticket not found</p>
        <p class="mt-1 text-sm text-gray-500">This ticket code isn't recognised.</p>
      </div>
    </.public_shell>
    """
  end

  def render(assigns) do
    event = assigns.ticket.event
    brand_start = event.brand_color_start || "#2563eb"
    brand_end = event.brand_color_end || "#1e40af"

    assigns =
      assigns
      |> assign(:brand_start, brand_start)
      |> assign(:brand_end, brand_end)
      |> assign(:event_when, event_when(event))

    ~H"""
    <.public_shell brand_start={@brand_start} brand_end={@brand_end}>
      <%!-- Hero --%>
      <header
        class="relative overflow-hidden px-6 pb-10 pt-8 text-white"
        style={"background: linear-gradient(145deg, #{@brand_start} 0%, #{@brand_end} 100%)"}
      >
        <div
          class="pointer-events-none absolute -right-8 -top-8 size-40 rounded-full opacity-20"
          style="background: radial-gradient(circle, white 0%, transparent 70%)"
        />
        <div
          class="pointer-events-none absolute -bottom-10 -left-6 size-32 rounded-full opacity-10"
          style="background: radial-gradient(circle, white 0%, transparent 70%)"
        />


        <h1 class="mt-3 text-2xl font-semibold leading-tight tracking-tight sm:text-3xl">
          {@ticket.event.name}
        </h1>
        <p :if={@ticket.event.venue} class="mt-2 flex items-start gap-1.5 text-sm text-white/85">
          <.icon name="hero-map-pin" class="mt-0.5 size-4 shrink-0 opacity-80" />
          <span>{@ticket.event.venue}</span>
        </p>
        <p :if={@event_when} class="mt-1.5 flex items-start gap-1.5 text-sm text-white/85">
          <.icon name="hero-calendar-days" class="mt-0.5 size-4 shrink-0 opacity-80" />
          <span>{@event_when}</span>
        </p>
      </header>

      <div class="space-y-6 px-5 pb-8 pt-5 sm:px-6">
        <img
          :if={@banner}
          src={@banner.url}
          alt={@banner.title}
          class="w-full rounded-xl object-cover shadow-sm"
        />

        <%!-- Attendee identity --%>
        <section class="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="text-[11px] font-semibold uppercase tracking-[0.14em] text-gray-400">
                Attendee
              </p>
              <p class="mt-1 truncate text-xl font-semibold text-gray-900">
                {@ticket.attendee_name}
              </p>
              <p class="mt-0.5 text-sm text-gray-500">{@ticket.ticket_type.name}</p>
            </div>
            <.status_pill status={@ticket.status} />
          </div>

          <dl
            :if={detail_fields(@ticket) != []}
            class="mt-4 grid gap-3 border-t border-gray-100 pt-4 sm:grid-cols-2"
          >
            <div :for={{label, value} <- detail_fields(@ticket)}>
              <dt class="text-[11px] font-medium uppercase tracking-wide text-gray-400">{label}</dt>
              <dd class="mt-0.5 text-sm font-medium text-gray-900">{value}</dd>
            </div>
          </dl>
        </section>

        <%!-- About --%>
        <section :if={present?(@ticket.event.description)} class="space-y-2">
          <h2 class="text-[11px] font-semibold uppercase tracking-[0.14em] text-gray-400">
            About
          </h2>
          <p class="text-sm leading-relaxed text-gray-700">{@ticket.event.description}</p>
        </section>

        <section :if={@schedule_days != []} class="space-y-4">
          <div class="flex items-baseline justify-between gap-3">
            <h2 class="text-[11px] font-semibold uppercase tracking-[0.14em] text-gray-400">
              Programme
            </h2>
            <p class="text-xs text-gray-400">
              {length(@schedule_days)} {if length(@schedule_days) == 1, do: "day", else: "days"}
            </p>
          </div>

          <div class="space-y-5">
            <div :for={day <- @schedule_days} class="space-y-3">
              <div class="flex items-end gap-2 border-b border-gray-100 pb-2">
                <div class="min-w-0 flex-1">
                  <p
                    :if={day.label}
                    class="text-sm font-semibold"
                    style={"color: #{@brand_start}"}
                  >
                    {day.label}
                  </p>
                  <p class={[
                    "text-sm",
                    if(day.label, do: "text-gray-500", else: "font-semibold text-gray-900")
                  ]}>
                    {Calendar.strftime(day.date, "%A, %d %b %Y")}
                  </p>
                </div>
              </div>

              <ol class="relative space-y-0 border-l-2 border-gray-100 ml-2">
                <li
                  :for={item <- day.items}
                  class="relative pl-5 pb-4 last:pb-0"
                >
                  <span
                    class="absolute -left-[5px] top-1.5 size-2 rounded-full ring-4 ring-white"
                    style={"background: #{@brand_start}"}
                  />
                  <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
                    <time class="text-xs font-semibold tabular-nums text-gray-500">
                      {NairobiTime.format(item.starts_at, "%H:%M")}
                      <%= if item.ends_at do %>
                        <span class="font-normal text-gray-400">
                          – {NairobiTime.format(item.ends_at, "%H:%M")}
                        </span>
                      <% end %>
                    </time>
                    <p :if={item.location} class="text-xs text-gray-400">
                      · {item.location}
                    </p>
                  </div>
                  <p class="mt-0.5 text-sm font-semibold text-gray-900">{item.title}</p>
                  <p
                    :if={present?(item.description)}
                    class="mt-1 text-sm leading-relaxed text-gray-600"
                  >
                    {item.description}
                  </p>
                </li>
              </ol>
            </div>
          </div>
        </section>

        <%!-- Links --%>
        <section :if={@links != []} class="space-y-3">
          <h2 class="text-[11px] font-semibold uppercase tracking-[0.14em] text-gray-400">
            More
          </h2>
          <div class="space-y-2">
            <a
              :for={link <- @links}
              href={link.url}
              target="_blank"
              rel="noopener noreferrer"
              class="group flex items-center justify-between gap-3 rounded-xl border border-gray-200 bg-white px-4 py-3.5 text-sm font-medium text-gray-900 shadow-sm transition hover:border-gray-300 hover:shadow"
            >
              <span class="truncate">{link.title}</span>
              <.icon
                name="hero-arrow-top-right-on-square"
                class="size-4 shrink-0 text-gray-400 transition group-hover:text-gray-600"
              />
            </a>
          </div>
        </section>
      </div>
    </.public_shell>
    """
  end

  attr :brand_start, :string, default: "#2563eb"
  attr :brand_end, :string, default: "#1e40af"
  slot :inner_block, required: true

  defp public_shell(assigns) do
    ~H"""
    <div
      class="min-h-screen"
      style={"background: linear-gradient(180deg, color-mix(in srgb, #{@brand_start} 8%, #f3f4f6) 0%, #f8fafc 28%, #f8fafc 100%)"}
    >
      <div class="mx-auto w-full max-w-lg px-3 py-6 sm:px-4 sm:py-10">
        <article class="overflow-hidden rounded-3xl border border-gray-200/80 bg-white shadow-xl shadow-gray-900/5">
          {render_slot(@inner_block)}
        </article>
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  defp status_pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex shrink-0 items-center rounded-full px-2.5 py-1 text-[11px] font-semibold",
      status_classes(@status)
    ]}>
      {status_label(@status)}
    </span>
    """
  end

  defp detail_fields(ticket) do
    [
      {"Company", ticket.company, "company"},
      {"Phone", ticket.phone_number, "phone_number"},
      {"Gender", ticket.gender, "gender"},
      {"ID number", ticket.id_number, "id_number"},
      {"Date of birth", format_dob(ticket.dob), "dob"}
    ]
    |> Enum.filter(fn {_label, value, key} ->
      key in ticket.event.required_attendee_fields and present?(value)
    end)
    |> Enum.map(fn {label, value, _key} -> {label, value} end)
  end

  defp format_dob(nil), do: nil
  defp format_dob(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")
  defp format_dob(other), do: other

  defp event_when(%{starts_at: nil}), do: nil

  defp event_when(%{starts_at: starts_at, ends_at: nil}) do
    NairobiTime.format(starts_at, "%d %b %Y · %H:%M")
  end

  defp event_when(%{starts_at: starts_at, ends_at: ends_at}) do
    start_local = NairobiTime.to_local(starts_at)
    end_local = NairobiTime.to_local(ends_at)

    cond do
      Date.compare(DateTime.to_date(start_local), DateTime.to_date(end_local)) == :eq ->
        "#{Calendar.strftime(start_local, "%d %b %Y")} · #{Calendar.strftime(start_local, "%H:%M")}–#{Calendar.strftime(end_local, "%H:%M")}"

      true ->
        "#{Calendar.strftime(start_local, "%d %b")} – #{Calendar.strftime(end_local, "%d %b %Y")}"
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: true

  defp status_classes("checked_in"), do: "bg-emerald-50 text-emerald-700"
  defp status_classes("checked_out"), do: "bg-gray-100 text-gray-600"
  defp status_classes("cancelled"), do: "bg-red-50 text-red-700"
  defp status_classes(_), do: "bg-sky-50 text-sky-700"

  defp status_label("registered"), do: "Not checked in"
  defp status_label("checked_in"), do: "Checked in"
  defp status_label("checked_out"), do: "Checked out"
  defp status_label("cancelled"), do: "Cancelled"
  defp status_label(status), do: status
end
