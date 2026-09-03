defmodule Datem.GS1 do
  @moduledoc """
  The GS1 Identity Engine: issues GS1 identifiers for scannable entities
  (visitors, attendees, vehicles, locations), encodes them as GS1 Digital
  Link QR codes, and resolves scanned Digital Links back to their entity
  — always scoped to the scanning organisation's tenant.

  Organisations without their own licensed GS1 Company Prefix fall back to
  `Datem.GS1.Identifiers.internal_company_prefix/0`: structurally-valid,
  Digital-Link-shaped identifiers that are flagged `interoperable: false`
  until the organisation adds a real prefix.
  """

  import Ecto.Query, warn: false

  alias Datem.Repo
  alias Datem.Accounts.Scope
  alias Datem.Tenancy
  alias Datem.GS1.{CheckDigit, DigitalLink, Identifier, Identifiers}

  @reference_attempts 5

  @doc """
  Issues a new GS1 identifier of `kind` (`:gln`, `:gsrn`, or `:giai`) for
  `subject_type`/`subject_id`, scoped to the caller's current organisation.

  Uses the organisation's licensed GS1 Company Prefix if it has one;
  otherwise falls back to the reserved internal prefix and marks the
  identifier non-interoperable.
  """
  def issue_identifier(%Scope{} = scope, kind, subject_type, subject_id)
      when kind in [:gln, :gsrn, :giai] and is_binary(subject_type) do
    org_id = Tenancy.organization_id!(scope)
    {company_prefix, interoperable} = company_prefix_for(scope)

    insert_with_unique_reference(
      %{
        organization_id: org_id,
        kind: kind,
        subject_type: subject_type,
        subject_id: to_string(subject_id),
        interoperable: interoperable
      },
      company_prefix,
      kind
    )
  end

  defp company_prefix_for(%Scope{organization: %{gs1_company_prefix: prefix}})
       when is_binary(prefix) and prefix != "" do
    {prefix, true}
  end

  defp company_prefix_for(%Scope{}), do: {Identifiers.internal_company_prefix(), false}

  defp insert_with_unique_reference(base_attrs, company_prefix, kind, attempt \\ 0)

  defp insert_with_unique_reference(_base_attrs, _company_prefix, _kind, attempt)
       when attempt >= @reference_attempts do
    {:error, :could_not_generate_unique_identifier}
  end

  defp insert_with_unique_reference(base_attrs, company_prefix, kind, attempt) do
    with {:ok, value} <- build_value(company_prefix, kind) do
      digital_link = DigitalLink.build(kind, value)

      attrs =
        Map.merge(base_attrs, %{
          value: value,
          ai: DigitalLink.ai_for(kind),
          digital_link: digital_link
        })

      %Identifier{}
      |> Identifier.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:error, changeset} ->
          if Keyword.has_key?(changeset.errors, :value) do
            insert_with_unique_reference(base_attrs, company_prefix, kind, attempt + 1)
          else
            {:error, changeset}
          end

        ok ->
          ok
      end
    end
  end

  defp build_value(company_prefix, :gln),
    do:
      Identifiers.build_gln(company_prefix, random_reference(12 - String.length(company_prefix)))

  defp build_value(company_prefix, :gsrn),
    do:
      Identifiers.build_gsrn(company_prefix, random_reference(17 - String.length(company_prefix)))

  defp build_value(company_prefix, :giai),
    do: Identifiers.build_giai(company_prefix, "A" <> random_reference(10))

  defp random_reference(digits) when digits > 0 do
    :rand.uniform(10 ** digits - 1) |> Integer.to_string() |> String.pad_leading(digits, "0")
  end

  @doc """
  Resolves a scanned GS1 Digital Link URI to its registered identifier,
  scoped to the caller's current organisation.

  Rejects the scan (`{:error, :not_found}`) if the identifier belongs to a
  different organisation, so a QR code issued by one tenant can never be
  used to resolve an entity at another.
  """
  def resolve_digital_link(%Scope{} = scope, uri) when is_binary(uri) do
    with {:ok, %{value: value}} <- DigitalLink.parse(uri) do
      Identifier
      |> Tenancy.scope(scope)
      |> where([i], i.value == ^value)
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        identifier -> {:ok, identifier}
      end
    end
  end

  @doc "Validates a GS1 mod-10 check digit. Delegates to `Datem.GS1.CheckDigit`."
  defdelegate valid_check_digit?(value), to: CheckDigit, as: :valid?

  @doc "Renders `digital_link` as an SVG QR code, suitable for on-screen display."
  def qr_svg(digital_link, opts \\ []) when is_binary(digital_link) do
    digital_link
    |> EQRCode.encode()
    |> EQRCode.svg(opts)
  end

  @doc "Renders `digital_link` as a PNG QR code, suitable for print or email."
  def qr_png(digital_link) when is_binary(digital_link) do
    digital_link
    |> EQRCode.encode()
    |> EQRCode.png()
  end
end
