defmodule DatemWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: DatemWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed top-4 right-4 z-50 w-80 sm:w-96"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 rounded-lg border bg-white p-4 shadow-lg ring-1 ring-black/5",
        @kind == :info && "border-blue-200",
        @kind == :error && "border-red-200"
      ]}>
        <.icon
          :if={@kind == :info}
          name="hero-information-circle"
          class="size-5 shrink-0 text-blue-600"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle"
          class="size-5 shrink-0 text-red-600"
        />
        <div class="min-w-0 flex-1 text-sm">
          <p :if={@title} class="font-semibold text-gray-900">{@title}</p>
          <p class="text-gray-600">{msg}</p>
        </div>
        <button type="button" class="group shrink-0 cursor-pointer" aria-label={gettext("close")}>
          <.icon
            name="hero-x-mark"
            class="size-5 text-gray-400 group-hover:text-gray-600"
          />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil, doc: "extra classes merged with the variant's base styling"
  attr :variant, :string, default: "primary", values: ~w(primary secondary danger)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "bg-blue-600 text-white hover:bg-blue-700 focus-visible:outline-blue-600",
      "secondary" =>
        "bg-white text-gray-700 border border-gray-200 hover:bg-gray-50 focus-visible:outline-blue-600",
      "danger" => "bg-red-600 text-white hover:bg-red-700 focus-visible:outline-red-600"
    }

    assigns =
      assign(assigns, :class, [
        "inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-medium",
        "transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2",
        "disabled:cursor-not-allowed disabled:opacity-50",
        Map.fetch!(variants, assigns.variant),
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end



@doc """
Renders the light-banner section used at the top of a list page: an icon,
title, subtitle, an optional count pill, and an actions slot for the
primary button(s). Deliberately has no border/rounding of its own — wrap
it together with the page's table in one bordered container so the banner,
button bar, and table read as a single connected card rather than two
separate floating boxes.

## Examples

    <div class="mb-6 overflow-hidden rounded-xl border border-blue-100">
      <.pass_header icon="hero-truck" title="Car Pass Management" subtitle="Track vehicle movements and mileage" count={length(@passes)}>
        <.button phx-click="new">+ New Car Pass</.button>
      </.pass_header>

      <.table id="car-passes" rows={@passes}>
        ...
      </.table>
    </div>
"""
attr :icon, :string, required: true
attr :title, :string, required: true
attr :subtitle, :string, default: nil
attr :count, :integer, default: nil
attr :count_label, :string, default: "Total"
slot :inner_block, doc: "action button(s), rendered in the bar below the banner"

def pass_header(assigns) do
  ~H"""
  <div>
    <div class="flex items-center justify-between bg-blue-50 px-6 py-5">
      <div>
        <p class="flex items-center gap-2 text-lg font-semibold text-blue-900">
          <.icon name={@icon} class="size-5" /> {@title}
        </p>
        <p :if={@subtitle} class="text-sm text-blue-700">{@subtitle}</p>
      </div>
      <div :if={@count} class="rounded-lg bg-white px-4 py-2 text-center shadow-sm">
        <p class="text-xl font-semibold text-blue-900">{@count}</p>
        <p class="text-xs text-blue-600">{@count_label}</p>
      </div>
    </div>

    <div :if={@inner_block != []} class="flex justify-end gap-3 border-b border-gray-200 bg-white px-6 py-3">
      {render_slot(@inner_block)}
    </div>
  </div>
  """
end
  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label for={@id} class="flex items-center gap-2">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={@class || "size-4 rounded border-gray-300 text-blue-600 focus:ring-blue-600"}
          {@rest}
        />
        <span class="text-sm text-gray-700">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-gray-700">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-lg border-gray-300 text-gray-900 focus:border-blue-600 focus:ring-blue-600 sm:text-sm",
            @errors != [] &&
              (@error_class || "border-red-500 focus:border-red-500 focus:ring-red-500")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-gray-700">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-lg border-gray-300 text-gray-900 placeholder:text-gray-400 focus:border-blue-600 focus:ring-blue-600 sm:text-sm",
            @errors != [] &&
              (@error_class || "border-red-500 focus:border-red-500 focus:ring-red-500")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
def input(assigns) do
  ~H"""
  <div class="mb-2">
    <label for={@id}>
      <span :if={@label} class="mb-1 block text-sm font-medium text-gray-700">{@label}</span>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          @class ||
            [
              "block w-full rounded-lg border border-gray-300 px-3 py-2 text-base text-gray-900",
              "placeholder:text-gray-400 shadow-sm",
              "focus:border-blue-600 focus:ring-1 focus:ring-blue-600 focus:outline-none",
              "invalid:border-gray-300 invalid:shadow-sm",
              "sm:text-sm"
            ],
          @errors != [] &&
            (@error_class || "border-red-500 focus:border-red-500 focus:ring-red-500")
        ]}
        {@rest}
      />
    </label>
    <.error :for={msg <- @errors}>{msg}</.error>
  </div>
  """
end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex items-center gap-1.5 text-sm text-red-600">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-gray-900">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-gray-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling and an empty state.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:empty>No users yet.</:empty>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"
  slot :empty, doc: "content shown instead of the table body when there are no rows"

 def table(assigns) do
  assigns =
    with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
      assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
    end

  assigns =
    assign(
      assigns,
      :empty?,
      is_list(assigns.rows) and assigns.rows == [] and assigns.empty != []
    )

  ~H"""
  <div
    :if={@empty?}
    class="rounded-lg border border-dashed border-gray-200 bg-white py-12 text-center"
  >
    <p class="text-sm text-gray-500">{render_slot(@empty)}</p>
  </div>
  <table :if={!@empty?} class="w-full text-left text-sm">
    <thead>
      <tr class="border-b border-gray-200 text-xs font-medium uppercase tracking-wide text-gray-500">
        <th :for={col <- @col} class="px-4 py-3">{col[:label]}</th>
        <th :if={@action != []} class="px-4 py-3">
          <span class="sr-only">{gettext("Actions")}</span>
        </th>
      </tr>
    </thead>
    <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
      <tr
        :for={row <- @rows}
        id={@row_id && @row_id.(row)}
        class="border-b border-gray-100 last:border-0 hover:bg-gray-50"
      >
        <td
          :for={col <- @col}
          phx-click={@row_click && @row_click.(row)}
          class={["px-4 py-4 text-sm text-gray-700", @row_click && "hover:cursor-pointer"]}
        >
          {render_slot(col, @row_item.(row))}
        </td>
        <td :if={@action != []} class="w-0 px-4 py-4 font-medium">
          <div class="flex gap-4">
            <%= for action <- @action do %>
              {render_slot(action, @row_item.(row))}
            <% end %>
          </div>
        </td>
      </tr>
    </tbody>
  </table>
  """
end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-gray-100">
      <li :for={item <- @item} class="flex justify-between gap-4 py-3 text-sm">
        <span class="font-medium text-gray-900">{item.title}</span>
        <span class="text-gray-600">{render_slot(item)}</span>
      </li>
    </ul>
    """
  end

  @doc """
  Renders content in a white surface card.

  ## Examples

      <.card>
        <p>Plain content</p>
      </.card>

      <.card title="Recent activity">
        <:actions><.button>View all</.button></:actions>
        ...
      </.card>
  """
  attr :id, :string, default: nil
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :actions

  def card(assigns) do
    ~H"""
    <div id={@id} class={["rounded-xl border border-gray-200 bg-white p-6 shadow-sm", @class]}>
      <div :if={@title || @actions != []} class="mb-4 flex items-center justify-between gap-4">
        <h2 :if={@title} class="text-base font-semibold text-gray-900">{@title}</h2>
        <div :if={@actions != []} class="flex-none">{render_slot(@actions)}</div>
      </div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a single statistic in a card, for dashboards and summaries.

  ## Examples

      <.stat_card label="On-site now" value="42" />
      <.stat_card label="Denied scans" value="3" hint="last 24h" icon="hero-shield-exclamation" />
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, default: nil
  attr :icon, :string, default: nil
  attr :class, :any, default: nil

  def stat_card(assigns) do
    ~H"""
    <div class={["rounded-xl border border-gray-200 bg-white p-6 shadow-sm", @class]}>
      <div class="flex items-start justify-between">
        <p class="text-sm font-medium text-gray-600">{@label}</p>
        <.icon :if={@icon} name={@icon} class="size-5 text-blue-600" />
      </div>
      <p class="mt-2 text-3xl font-semibold text-gray-900">{@value}</p>
      <p :if={@hint} class="mt-1 text-xs text-gray-500">{@hint}</p>
    </div>
    """
  end

  @doc """
  Renders a small status badge.

  ## Examples

      <.badge kind={:success}>Accepted</.badge>
      <.badge kind={:danger}>Denied</.badge>
  """
  attr :kind, :atom, default: :neutral, values: [:success, :warning, :danger, :info, :neutral]
  slot :inner_block, required: true

  def badge(assigns) do
    colors = %{
      success: "bg-green-50 text-green-700 ring-green-600/20",
      warning: "bg-amber-50 text-amber-700 ring-amber-600/20",
      danger: "bg-red-50 text-red-700 ring-red-600/20",
      info: "bg-blue-50 text-blue-700 ring-blue-600/20",
      neutral: "bg-gray-100 text-gray-600 ring-gray-500/10"
    }

    assigns = assign(assigns, :color, Map.fetch!(colors, assigns.kind))

    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset",
      @color
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Renders the large accept/deny result state for the full-screen scanning view.

  ## Examples

      <.scan_result result={:accepted} title="Jane Doe" subtitle="Checked in · 09:41" />
      <.scan_result result={:denied} title="Unknown code" subtitle="Not registered for this event" />
  """
  attr :result, :atom, required: true, values: [:accepted, :duplicate, :expired, :denied, :idle]
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  def scan_result(assigns) do
    styles = %{
      accepted: {"bg-green-50 text-green-700", "hero-check-circle"},
      duplicate: {"bg-amber-50 text-amber-700", "hero-exclamation-triangle"},
      expired: {"bg-amber-50 text-amber-700", "hero-clock"},
      denied: {"bg-red-50 text-red-700", "hero-x-circle"},
      idle: {"bg-gray-100 text-gray-500", "hero-qr-code"}
    }

    {color, icon} = Map.fetch!(styles, assigns.result)
    assigns = assign(assigns, color: color, icon: icon)

    ~H"""
    <div class={[
      "flex flex-col items-center justify-center gap-4 rounded-2xl p-10 text-center",
      @color
    ]}>
      <.icon name={@icon} class="size-20" />
      <div>
        <p class="text-2xl font-semibold">{@title}</p>
        <p :if={@subtitle} class="mt-1 text-sm opacity-80">{@subtitle}</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a modal dialog.

  ## Examples

      <.modal id="confirm-modal">
        <p>Are you sure?</p>
      </.modal>

      <.modal id="confirm-modal" show on_cancel={JS.navigate(~p"/")}>
        <p>Are you sure?</p>
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :class, :any, default: "max-w-md", doc: "width classes for the dialog panel"
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-gray-900/50 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <.focus_wrap
            id={"#{@id}-container"}
            phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
            phx-key="escape"
            phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
            class={[
              "relative w-full rounded-xl border border-gray-200 bg-white p-6 shadow-xl transition",
              @class
            ]}
          >
            <button
              type="button"
              class="absolute top-4 right-4 text-gray-400 hover:text-gray-600"
              aria-label={gettext("close")}
              phx-click={JS.exec("data-cancel", to: "##{@id}")}
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
            {render_slot(@inner_block)}
          </.focus_wrap>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "block"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(DatemWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(DatemWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
