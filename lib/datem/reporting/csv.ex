defmodule Datem.Reporting.CSV do
  @moduledoc """
  A minimal RFC 4180 CSV encoder/decoder.

  Small enough not to warrant a dependency: exports are the only producer
  of CSV and attendee import is the only consumer, and both only ever deal
  with flat rows of strings, numbers and datetimes — no embedded newlines
  inside a field.
  """

  @doc """
  Encodes `headers` plus `rows` (a list of lists) into a CSV binary with
  CRLF line endings, quoting any field that needs it.
  """
  def encode(headers, rows) do
    [headers | rows]
    |> Enum.map_join("\r\n", fn row -> Enum.map_join(row, ",", &field/1) end)
    |> Kernel.<>("\r\n")
  end

  defp field(nil), do: ""
  defp field(%DateTime{} = datetime), do: field(DateTime.to_iso8601(datetime))
  defp field(value) when is_binary(value), do: escape(value)
  defp field(value), do: field(to_string(value))

  defp escape(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(value, "\"", "\"\"")}")
    else
      value
    end
  end

  @doc """
  Decodes a CSV binary into `{headers, rows}`, both lists of strings.
  Headers are lowercased and trimmed. Handles quoted fields (including an
  embedded comma or an escaped `""` inside quotes) — the inverse of
  `encode/2`.
  """
  def decode(binary) do
    case binary |> String.split(~r/\r\n|\n/) |> Enum.reject(&(&1 == "")) do
      [] -> {[], []}
      [header_line | row_lines] ->
        headers = header_line |> parse_line() |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
        rows = Enum.map(row_lines, &parse_line/1)
        {headers, rows}
    end
  end

  # Parses one CSV line into fields, honoring quoted fields that may
  # contain a comma or an escaped `""`.
  defp parse_line(line), do: parse_line(line, "", [], false)

  defp parse_line("", field, acc, false), do: Enum.reverse([String.trim(field) | acc])

  defp parse_line("\"\"" <> rest, field, acc, true),
    do: parse_line(rest, field <> "\"", acc, true)

  defp parse_line("\"" <> rest, field, acc, true), do: parse_line(rest, field, acc, false)
  defp parse_line("\"" <> rest, field, acc, false), do: parse_line(rest, field, acc, true)

  defp parse_line("," <> rest, field, acc, false),
    do: parse_line(rest, "", [String.trim(field) | acc], false)

  defp parse_line(<<c::utf8, rest::binary>>, field, acc, in_quotes),
    do: parse_line(rest, field <> <<c::utf8>>, acc, in_quotes)
end
