defmodule DatemWeb.TicketingLive.EventContent do
  @moduledoc "Manage the banner and links shown on an event's public ticket page."
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, {:require_role, [:owner, :admin, :operator]}}

  alias Datem.Ticketing
  alias Datem.Ticketing.EventContentItem

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    event = Ticketing.get_event_for_scope!(scope, id)

    {:ok,
     socket
     |> assign(:event, event)
     |> assign(:show_form, false)
     |> assign(:editing_item, nil)
     |> assign(:items, Ticketing.list_content_items(scope, event))
     |> assign_form()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
      <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
        <.pass_header
          icon="hero-link"
          title={"#{@event.name} · Public page content"}
          subtitle="Banner and links shown when attendees scan their ticket"
        >
          <.link navigate={~p"/events/#{@event.id}"}>
            <.button variant="secondary">Back to event</.button>
          </.link>
          <.button phx-click="new">Add content</.button>
        </.pass_header>

        <.table id="content-items" rows={@items}>
          <:col :let={i} label="Title">{i.title}</:col>
          <:col :let={i} label="Kind">
            <.badge kind={:info}>{(i.kind == "banner" && "Banner") || "Link"}</.badge>
          </:col>
          <:col :let={i} label="URL">
            <span class="break-all text-xs text-gray-500">{i.url}</span>
          </:col>
          <:col :let={i} label="Order">{i.position}</:col>
          <:col :let={i} label="Status">
            <.badge kind={(i.is_active && :success) || :neutral}>
              {(i.is_active && "Shown") || "Hidden"}
            </.badge>
          </:col>
          <:action :let={i}>
            <.link phx-click="edit" phx-value-id={i.id}>Edit</.link>
          </:action>
          <:action :let={i}>
            <.link phx-click="delete" phx-value-id={i.id} data-confirm="Remove this item?">
              Remove
            </.link>
          </:action>
          <:empty>Nothing added yet. Add a banner image or a link with the button above.</:empty>
        </.table>
      </div>

      <.modal :if={@show_form} id="content-modal" show on_cancel={JS.push("close_form")}>
        <.header>{if @editing_item, do: "Edit content", else: "Add content"}</.header>

        <.form for={@form} id="content_form" phx-submit="save" phx-change="validate">
          <.input field={@form[:title]} type="text" label="Title" required />
          <.input field={@form[:kind]} type="select" label="Kind" options={EventContentItem.admin_kind_options()} />
          <.input field={@form[:url]} type="text" label="URL" required />
          <p class="-mt-2 text-xs text-gray-500">
            For a banner, a direct image URL. For a link, any external page (programme, photo gallery, etc.).
          </p>
          <.input field={@form[:position]} type="number" label="Display order (lower shows first)" />
          <.input field={@form[:is_active]} type="checkbox" label="Show on the public ticket page" />

          <div class="mt-4 flex gap-3">
            <.button phx-disable-with="Saving...">
              {if @editing_item, do: "Save changes", else: "Add content"}
            </.button>
            <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply, socket |> assign(:editing_item, nil) |> assign(:show_form, true) |> assign_form()}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    item = Ticketing.get_content_item_for_scope!(scope, id)

    {:noreply,
     socket
     |> assign(:editing_item, item)
     |> assign(:show_form, true)
     |> assign_form(item)}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:editing_item, nil)}
  end

  def handle_event("validate", %{"event_content_item" => params}, socket) do
    item = socket.assigns.editing_item || %EventContentItem{}
    changeset = item |> Ticketing.change_content_item(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: "event_content_item"))}
  end

  def handle_event("save", %{"event_content_item" => params}, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event

    result =
      case socket.assigns.editing_item do
        nil -> Ticketing.create_content_item(scope, event, params)
        item -> Ticketing.update_content_item(scope, item, params)
      end

    case result do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved.")
         |> assign(:show_form, false)
         |> assign(:editing_item, nil)
         |> assign(:items, Ticketing.list_content_items(scope, event))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "event_content_item"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    event = socket.assigns.event
    item = Ticketing.get_content_item_for_scope!(scope, id)

    case Ticketing.delete_content_item(scope, item) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Removed.") |> assign(:items, Ticketing.list_content_items(scope, event))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't remove that.")}
    end
  end

  defp assign_form(socket, item \\ %EventContentItem{}),
    do: assign(socket, :form, to_form(Ticketing.change_content_item(item), as: "event_content_item"))
end
