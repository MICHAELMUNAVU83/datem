defmodule Datem.NairobiTime do


  @offset_seconds 3 * 60 * 60

  def to_local(nil), do: nil
  def to_local(%DateTime{} = dt), do: DateTime.add(dt, @offset_seconds, :second)

  def to_utc(nil), do: nil
  def to_utc(%DateTime{} = dt), do: DateTime.add(dt, -@offset_seconds, :second)

  @doc "Parses a datetime-local input value as Nairobi wall-clock time, returns UTC."
  def parse_local_input(nil), do: nil
  def parse_local_input(""), do: nil

  def parse_local_input(value) when is_binary(value) do
    padded = if String.length(value) == 16, do: value <> ":00", else: value

    case NaiveDateTime.from_iso8601(padded) do
      {:ok, naive} -> naive |> DateTime.from_naive!("Etc/UTC") |> to_utc()
      {:error, _} -> nil
    end
  end

  @doc "Pre-fills a datetime-local input with a stored UTC value, shown in Nairobi time."
  def local_input_value(nil), do: nil
  def local_input_value(%DateTime{} = dt), do: dt |> to_local() |> Calendar.strftime("%Y-%m-%dT%H:%M")

  @doc "Formats a stored UTC value for display, in Nairobi time."
  def format(nil, _fmt), do: nil
  def format(%DateTime{} = dt, fmt), do: dt |> to_local() |> Calendar.strftime(fmt)
end
