defmodule DatemWeb.AdminLive.Organizations do
  use DatemWeb, :live_view

  on_mount {DatemWeb.UserAuth, :require_platform_admin}

  alias Datem.Organizations
  alias Datem.Organizations.Organization

  @impl true
  def render(assigns) do
    ~H"""
       <Layouts.app flash={@flash} current_scope={@current_scope} max_width="max-w-full">
       <.header>
      Companies
      <:subtitle>Grant or revoke module access for each company.</:subtitle>
      <:actions>
        <.button phx-click="new">New company</.button>
      </:actions>
    </.header>

      <.table id="organizations" rows={@organizations}>
        <:col :let={org} label="Company">{org.name}</:col>
        <:col :let={org} label="Plan"><.badge>{org.plan}</.badge></:col>
        <:col :let={org} label="Access">
          <input
            type="checkbox"
            checked={"access" in org.modules}
            phx-click="toggle_module"
            phx-value-id={org.id}
            phx-value-module="access"
            class="size-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600"
          />
        </:col>
        <:col :let={org} label="Ticketing">
          <input
            type="checkbox"
            checked={"ticketing" in org.modules}
            phx-click="toggle_module"
            phx-value-id={org.id}
            phx-value-module="ticketing"
            class="size-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600"
          />
        </:col>
        <:empty>No companies yet.</:empty>
      </.table>
         <.modal :if={@show_form} id="new-org-modal" show on_cancel={JS.push("close_form")}>
      <.header>New company</.header>

      <.form for={@form} id="new_org_form" phx-submit="create" phx-change="validate">
        <.input field={@form[:name]} type="text" label="Company name" required />

        <fieldset class="mt-4">
          <legend class="mb-1 block text-sm font-medium text-gray-700">Modules</legend>
          <input type="hidden" name="organization[modules][]" value="" />
          <label class="flex items-center gap-2 py-1">
            <input
              type="checkbox" name="organization[modules][]" value="access"
              checked={"access" in (@form[:modules].value || [])}
              class="size-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600"
            />
            <span class="text-sm text-gray-700">Access</span>
          </label>
          <label class="flex items-center gap-2 py-1">
            <input
              type="checkbox" name="organization[modules][]" value="ticketing"
              checked={"ticketing" in (@form[:modules].value || [])}
              class="size-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600"
            />
            <span class="text-sm text-gray-700">Ticketing</span>
          </label>
        </fieldset>

        <div class="mt-4 flex gap-3">
          <.button phx-disable-with="Creating...">Create company</.button>
          <.button type="button" variant="secondary" phx-click="close_form">Cancel</.button>
        </div>
      </.form>
    </.modal>
    </Layouts.app>
    """
  end
@impl true
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:organizations, Organizations.list_all_organizations())
   |> assign(:show_form, false)
   |> assign(:form, to_form(Ecto.Changeset.change(%Organization{modules: ["access"]}), as: "organization"))
   |> assign(:page_title, "Companies")}
end
def handle_event("new", _params, socket) do
  {:noreply,
   socket
   |> assign(:show_form, true)
   |> assign(:form, to_form(Ecto.Changeset.change(%Organization{modules: ["access"]}), as: "organization"))}
end

def handle_event("close_form", _params, socket), do: {:noreply, assign(socket, :show_form, false)}

def handle_event("validate", %{"organization" => params}, socket) do
  changeset =
    %Organization{}
    |> Organization.changeset(normalize_modules(params))
    |> Map.put(:action, :validate)

  {:noreply, assign(socket, :form, to_form(changeset, as: "organization"))}
end

def handle_event("create", %{"organization" => params}, socket) do
  case Organizations.create_organization(normalize_modules(params)) do
    {:ok, organization} ->
      {:noreply,
       socket
       |> put_flash(:info, "#{organization.name} created.")
       |> assign(:show_form, false)
       |> assign(:organizations, Organizations.list_all_organizations())}

    {:error, changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset, as: "organization"))}
  end
end


  @impl true
  def handle_event("toggle_module", %{"id" => id, "module" => module}, socket) do
    organization = Enum.find(socket.assigns.organizations, &(to_string(&1.id) == id))

    modules =
      if module in organization.modules,
        do: List.delete(organization.modules, module),
        else: [module | organization.modules]

    case Organizations.set_organization_modules(organization, modules) do
      {:ok, updated} ->
        organizations =
          Enum.map(socket.assigns.organizations, fn
            %{id: id} = _o when id == updated.id -> updated
            o -> o
          end)

        {:noreply, assign(socket, :organizations, organizations)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update #{organization.name}.")}
    end
  end
  defp normalize_modules(params) do
  Map.update(params, "modules", [], &Enum.reject(&1, fn m -> m == "" end))
end
end
