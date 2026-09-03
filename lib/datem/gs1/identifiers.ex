defmodule Datem.GS1.Identifiers do
  @moduledoc """
  Pure functions that build structurally-valid GS1 keys from a company
  prefix and a reference number. No persistence, no randomness — callers
  decide where the reference number comes from.

  Reserved for organisations without a real GS1 Company Prefix: a
  Datem-internal prefix that is not allocated to anyone by GS1. Values
  built from it are structurally valid but **not GS1-interoperable**.
  """

  alias Datem.GS1.CheckDigit

  @internal_company_prefix "0999999"

  @doc "The reserved, non-interoperable company prefix used as a fallback."
  def internal_company_prefix, do: @internal_company_prefix

  @gln_key_length 12
  @gsrn_key_length 17

  @doc """
  Builds a 13-digit GLN from `company_prefix` (6-10 digits) and a
  `location_reference` (digits, zero-padded to fill the remaining length).
  """
  def build_gln(company_prefix, location_reference) do
    build(company_prefix, location_reference, @gln_key_length)
  end

  @doc """
  Builds an 18-digit GSRN (AI 8018) from `company_prefix` and a
  `service_reference`.
  """
  def build_gsrn(company_prefix, service_reference) do
    build(company_prefix, service_reference, @gsrn_key_length)
  end

  @doc """
  Builds a GIAI (AI 8004) from `company_prefix` and an
  `individual_asset_reference`. GIAIs are alphanumeric and carry no GS1
  check digit, per the GS1 General Specifications.
  """
  def build_giai(company_prefix, individual_asset_reference)
      when is_binary(company_prefix) and is_binary(individual_asset_reference) do
    with :ok <- validate_company_prefix(company_prefix),
         :ok <- validate_asset_reference(individual_asset_reference) do
      {:ok, company_prefix <> individual_asset_reference}
    end
  end

  defp build(company_prefix, reference, key_length)
       when is_binary(company_prefix) and is_binary(reference) do
    with :ok <- validate_company_prefix(company_prefix),
         reference_length = key_length - String.length(company_prefix),
         :ok <- validate_reference(reference, reference_length) do
      body = company_prefix <> String.pad_leading(reference, reference_length, "0")
      {:ok, CheckDigit.append(body)}
    end
  end

  defp validate_company_prefix(company_prefix) do
    if String.match?(company_prefix, ~r/^\d{6,10}$/) do
      :ok
    else
      {:error, :invalid_company_prefix}
    end
  end

  defp validate_reference(reference, max_length) do
    cond do
      max_length <= 0 -> {:error, :company_prefix_too_long}
      not String.match?(reference, ~r/^\d+$/) -> {:error, :invalid_reference}
      String.length(reference) > max_length -> {:error, :reference_too_long}
      true -> :ok
    end
  end

  defp validate_asset_reference(reference) do
    cond do
      reference == "" -> {:error, :invalid_reference}
      String.length(reference) > 30 -> {:error, :reference_too_long}
      not String.match?(reference, ~r/^[A-Za-z0-9]+$/) -> {:error, :invalid_reference}
      true -> :ok
    end
  end
end
