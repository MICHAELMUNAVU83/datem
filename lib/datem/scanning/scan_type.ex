defmodule Datem.Scanning.ScanType do
  @moduledoc """
  A configurable checkpoint ("Lunch", "Entry", "Session A", "Merch") that an
  organisation defines for one of its events or sites.

  The behaviour of a checkpoint is data, not code: the embedded
  `Datem.Scanning.ScanType.Rules` are evaluated by `Datem.Scanning` on every
  scan, so adding a new kind of checkpoint never requires a deploy.
  """
  use Ecto.Schema
  import Ecto.Changeset

  defmodule Rules do
    @moduledoc """
    The rule set evaluated on each scan. Stored as JSONB on `scan_types.rules`.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :once_per_subject, :boolean, default: true
      field :requires_check_in, :boolean, default: false
      field :requires_prior_scan_type_id, :integer
      field :allowed_ticket_type_ids, {:array, :integer}, default: []
    end

    @doc false
    def changeset(rules, attrs) do
      rules
      |> cast(attrs, [
        :once_per_subject,
        :requires_check_in,
        :requires_prior_scan_type_id,
        :allowed_ticket_type_ids
      ])
      |> update_change(:allowed_ticket_type_ids, fn ids -> Enum.reject(ids, &is_nil/1) end)
    end
  end

  schema "scan_types" do
    field :name, :string
    field :active, :boolean, default: true
    field :active_from, :utc_datetime
    field :active_to, :utc_datetime

    embeds_one :rules, Rules, on_replace: :update

    belongs_to :organization, Datem.Organizations.Organization
    belongs_to :event, Datem.Ticketing.Event
    belongs_to :site, Datem.Access.Site

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(scan_type, attrs) do
    scan_type
    |> cast(attrs, [
      :name,
      :active,
      :active_from,
      :active_to,
      :organization_id,
      :event_id,
      :site_id
    ])
    |> cast_embed(:rules)
    |> put_default_rules()
    |> validate_required([:name, :organization_id])
    |> validate_length(:name, max: 160)
    |> validate_scope()
    |> validate_window()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:site_id)
    |> check_constraint(:event_id,
      name: :scan_types_exactly_one_scope,
      message: "must belong to exactly one event or site"
    )
  end

  @doc false
  def active_changeset(scan_type, active) when is_boolean(active),
    do: change(scan_type, active: active)

  # A checkpoint with no rules at all ("scan everyone, always") is a normal
  # case, so an absent `rules` param means defaults rather than an error.
  defp put_default_rules(changeset) do
    if get_field(changeset, :rules), do: changeset, else: put_embed(changeset, :rules, %Rules{})
  end

  defp validate_scope(changeset) do
    case {get_field(changeset, :event_id), get_field(changeset, :site_id)} do
      {nil, nil} ->
        add_error(changeset, :event_id, "pick an event or a site")

      {event_id, site_id} when not is_nil(event_id) and not is_nil(site_id) ->
        add_error(changeset, :event_id, "pick either an event or a site, not both")

      _ ->
        changeset
    end
  end

  defp validate_window(changeset) do
    from = get_field(changeset, :active_from)
    to = get_field(changeset, :active_to)

    if from && to && DateTime.compare(from, to) != :lt do
      add_error(changeset, :active_to, "must be after the start of the window")
    else
      changeset
    end
  end
end
