defmodule Datem.GS1.DigitalLink do
  @moduledoc """
  Builds and parses GS1 Digital Link URIs of the form
  `https://id.datem.io/{ai}/{value}`.

  Only the application identifiers Datem actually issues are recognised:
  GLN (`414`), GSRN (`8018`), and GIAI (`8004`).
  """

  alias Datem.GS1.CheckDigit

  @host "id.datem.io"

  @ai_kinds %{
    "414" => :gln,
    "8018" => :gsrn,
    "8004" => :giai
  }

  @kind_ais Map.new(@ai_kinds, fn {ai, kind} -> {kind, ai} end)

  @doc "The AI for a given identifier kind (`:gln`, `:gsrn`, or `:giai`)."
  def ai_for(kind), do: Map.fetch!(@kind_ais, kind)

  @doc "Builds the Digital Link URI for `kind` and `value`."
  def build(kind, value) when is_atom(kind) and is_binary(value) do
    "https://#{@host}/#{ai_for(kind)}/#{value}"
  end

  @doc """
  Parses a GS1 Digital Link URI, returning `{:ok, %{kind:, ai:, value:}}` on
  success. Validates the host, the recognised AI, and — for kinds that
  carry a GS1 check digit (GLN, GSRN) — the check digit itself.

  Returns `{:error, reason}` for anything malformed, unrecognised, or
  failing check-digit validation, so a corrupted or tampered QR code is
  never resolved.
  """
  def parse(uri) when is_binary(uri) do
    with %URI{host: host, path: path} when is_binary(path) <- URI.parse(uri),
         :ok <- validate_host(host),
         [ai, value] <- path |> String.trim_leading("/") |> String.split("/", trim: true),
         {:ok, kind} <- fetch_kind(ai),
         :ok <- validate_value(kind, value) do
      {:ok, %{kind: kind, ai: ai, value: value}}
    else
      _ -> {:error, :invalid_digital_link}
    end
  end

  defp validate_host(@host), do: :ok
  defp validate_host(_other), do: {:error, :invalid_host}

  defp fetch_kind(ai) do
    case Map.fetch(@ai_kinds, ai) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, :unrecognised_ai}
    end
  end

  defp validate_value(:giai, value), do: if(value != "", do: :ok, else: {:error, :invalid_value})

  defp validate_value(kind, value) when kind in [:gln, :gsrn] do
    if CheckDigit.valid?(value), do: :ok, else: {:error, :invalid_check_digit}
  end
end
