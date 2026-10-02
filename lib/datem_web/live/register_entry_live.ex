defmodule DatemWeb.RegisterEntryLive do
  use DatemWeb, :live_view

  alias Datem.Organizations
  alias Datem.Access
  alias Datem.Access.Visitor


@impl true
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:organizations, Organizations.list_registerable_organizations())
   |> assign(:selected_organization_id, nil)
   |> assign(:selected_site_id, nil)
   |> assign(:visit_mode, "walk-in")
   |> assign(:employees, [])
   |> assign(:sites, [])
   |> assign(:display, "display: none;")
   |> assign(:pass, nil)
   |> assign_form(%Visitor{})}
end

  @impl true
  def render(%{pass: pass} = assigns) when not is_nil(pass) do
    ~H"""
    <div class="reveal w-full rounded-[30px] bg-n2 p-8 text-center lg:p-14">
      <p class="text-b18 font-semibold text-ink">You're registered.</p>
      <p class="mt-2 text-b16 opacity-80">
        Your host needs to approve the visit first, you'll receive a digital link once they do.
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="reveal w-full rounded-[30px] bg-n2 p-8 lg:p-14">
      <.form for={@form} id="access-form" phx-change="validate" phx-submit="save">
        <div class="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
          <div class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">Company / Location</label>
            <select
              name="organization_id"
              id="organization_id"
              phx-change="select_organization"
              class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
              required
            >
              <option value="">Select the company you're visiting</option>
              <option
                :for={org <- @organizations}
                value={org.id}
                selected={@selected_organization_id == org.id}
              >
                {org.name}
              </option>
            </select>
          </div>

          <div :if={@sites != []} class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">Site</label>
            <select
              name="site_id"
              id="site_id"
              class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
            >
              <option value="">Select a site</option>
             <option :for={site <- @sites} value={site.id} selected={to_string(@selected_site_id) == to_string(site.id)}>
                {site.name}
                </option>

            </select>
          </div>

          <div class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">Full name</label>
            <input
              type="text"
              name={@form[:name].name}
              id={@form[:name].id}
              value={@form[:name].value}
              class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
              placeholder="Enter your full names"
              required
            />
            <span class="text-b14 font-medium text-red-500">
              <%= for msg <- @form[:name].errors do %>
                {translate_error(msg)}
              <% end %>
            </span>
          </div>

          <div class="flex flex-col gap-2">
      <label class="text-b16 font-semibold">Email</label>
      <input
    type="email"
    name={@form[:email].name}
    id={@form[:email].id}
    value={@form[:email].value}
    class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
    placeholder="you@example.com"
    required
     />
    <span class="text-b14 font-medium text-red-500">
    <%= for msg <- @form[:email].errors do %>
      {translate_error(msg)}
    <% end %>
    </span>
    </div>


          <div class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">Contact</label>
            <input
              type="text"
              name={@form[:contact].name}
              id={@form[:contact].id}
              value={@form[:contact].value}
              class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
              placeholder="Phone or email"
              required
            />
            <span class="text-b14 font-medium text-red-500">
              <%= for msg <- @form[:contact].errors do %>
                {translate_error(msg)}
              <% end %>
            </span>
          </div>

          <div class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">Company you work for</label>
            <input
              type="text"
              name={@form[:company].name}
              id={@form[:company].id}
              value={@form[:company].value}
              class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
              placeholder="Company (optional)"
            />
          </div>

          <div class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">ID / Passport number</label>
            <input
              type="text"
              name={@form[:id_number].name}
              id={@form[:id_number].id}
              value={@form[:id_number].value}
              class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
              placeholder="Enter your ID/passport number"
            />
          </div>

          <div class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">Who are you visiting?</label>
            <select
              name={@form[:host_employee_id].name}
              id={@form[:host_employee_id].id}
              class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
              disabled={@selected_organization_id == nil}
              required
            >
              <option value="">
                {(@selected_organization_id && "Select who you're here to see") || "Choose a company first"}
              </option>

              <option
                :for={employee <- @employees}
                value={employee.id}
                selected={to_string(@form[:host_employee_id].value) == to_string(employee.id)}
                   >
               {employee.name}
               </option>
            </select>
            <span class="text-b14 font-medium text-red-500">
              <%= for msg <- @form[:host_employee_id].errors do %>
                {translate_error(msg)}
              <% end %>
            </span>
          </div>

          <div class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">Will you walk in or drive in?</label>
           <select name="visit_mode" id="visit_mode" phx-change="toggle_carreg_input" ...>
            <option value="walk-in" selected={@visit_mode == "walk-in"}>Walk-in</option>
            <option value="driving" selected={@visit_mode == "driving"}>Driving</option>
           </select>
          </div>

          <div id="vehicle_reg_field" style={@display} class="flex flex-col gap-2">
            <label class="text-b16 font-semibold">Vehicle reg no</label>
            <input
              type="text"
              name={@form[:vehicle_reg].name}
              id={@form[:vehicle_reg].id}
              value={@form[:vehicle_reg].value}
              class="h-[58px] w-full rounded-[10px] border-0 bg-white px-5 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
              placeholder="Enter your vehicle reg no"
            />
          </div>

          <div class="flex flex-col gap-2 md:col-span-2 lg:col-span-3">
            <label class="text-b16 font-semibold">Purpose of visit</label>
            <textarea
              name={@form[:purpose].name}
              id={@form[:purpose].id}
              class="min-h-[140px] w-full rounded-[10px] border-0 bg-white px-5 py-4 text-b16 font-medium text-ink outline-none transition focus:ring-2 focus:ring-brand"
              placeholder="Enter your purpose"
            >{@form[:purpose].value}</textarea>
          </div>

          <div class="md:col-span-2 lg:col-span-3">
            <.button phx-disable-with="Saving...">Register entry</.button>
          </div>
        </div>
      </.form>

      <div id="hideMsg" class="mt-6 flex flex-col gap-3">
        <p
          :if={info = Phoenix.Flash.get(@flash, :info)}
          class="rounded-[10px] bg-sky px-5 py-3 text-b16 font-medium text-ink"
          role="alert"
          phx-click="lv:clear-flash"
          phx-value-key="info"
        >
          {info}
        </p>

        <p
          :if={error = Phoenix.Flash.get(@flash, :error)}
          class="rounded-[10px] bg-[#ffe3e3] px-5 py-3 text-b16 font-medium text-ink"
          role="alert"
          phx-click="lv:clear-flash"
          phx-value-key="error"
        >
          {error}
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_organization", %{"organization_id" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:selected_organization_id, nil)
     |> assign(:employees, [])
     |> assign(:sites, [])}
  end

  def handle_event("select_organization", %{"organization_id" => id}, socket) do
    org_id = String.to_integer(id)

    {:noreply,
     socket
     |> assign(:selected_organization_id, org_id)
     |> assign(:employees, Organizations.list_employees_for_organization(org_id))
     |> assign(:sites, Access.list_sites_for_organization(org_id))}
  end

  def handle_event("toggle_carreg_input", %{"visit_mode" => "driving"}, socket) do
    {:noreply, assign(socket, :display, "display: block;")}
  end

 def handle_event("validate", params, socket) do
  visitor_params = Map.get(params, "visitor", %{})

  changeset =
    %Visitor{}
    |> Visitor.public_registration_changeset(visitor_params)
    |> Map.put(:action, :validate)

  {:noreply,
   socket
   |> assign(:selected_site_id, params["site_id"])
   |> assign(:form, to_form(changeset, as: "visitor"))}
end

def handle_event("toggle_carreg_input", %{"visit_mode" => mode}, socket) do
  {:noreply,
   socket
   |> assign(:visit_mode, mode)
   |> assign(:display, if(mode == "driving", do: "display: block;", else: "display: none;"))}
end

def handle_event("save", params, socket) do
  visitor_params =
    params
    |> Map.get("visitor", %{})
    |> Map.put("organization_id", params["organization_id"])
    |> Map.put("site_id", params["site_id"])

  case Access.register_public_visit(visitor_params) do
    {:ok, %{pass: pass}} when not is_nil(pass) ->

      {:noreply, assign(socket, :pass, pass)}

    {:ok, %{visitor: _visitor}} ->

      {:noreply,
       put_flash(
         socket,
         :info,
         "You're registered — check your email for confirmation. We'll email your QR pass once your host approves the visit."
       )}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset, as: "visitor"))}
  end
end

  defp assign_form(socket, %Visitor{} = visitor) do
    assign(socket, :form, to_form(Visitor.public_registration_changeset(visitor, %{}), as: "visitor"))
  end
end
