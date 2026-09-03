defmodule Datem.Reporting.CSV do
  @moduledoc """
  A minimal RFC 4180 CSV encoder.

  Small enough not to warrant a dependency: exports are the only producer,
  and they only ever write flat rows of strings, numbers and datetimes.
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
end
