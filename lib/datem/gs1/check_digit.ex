defmodule Datem.GS1.CheckDigit do
  @moduledoc """
  GS1 mod-10 check-digit algorithm, shared by every GS1 key (GLN, GSRN,
  GIAI, ...). See GS1 General Specifications, section 7.9.

  The algorithm multiplies digits by an alternating 3/1 weight starting
  from the rightmost digit (excluding the check digit itself), sums them,
  and takes the smallest number that rounds the sum up to a multiple of 10.
  """

  @doc """
  Computes the check digit for `digits`, a string of decimal digits *not*
  including the check digit itself.
  """
  def calculate(digits) when is_binary(digits) do
    digits
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.map(&(&1 - ?0))
    |> Enum.with_index()
    |> Enum.map(fn {digit, index} -> digit * weight(index) end)
    |> Enum.sum()
    |> then(fn sum -> rem(10 - rem(sum, 10), 10) end)
  end

  defp weight(index) when rem(index, 2) == 0, do: 3
  defp weight(_index), do: 1

  @doc """
  Appends the calculated check digit to `digits`.
  """
  def append(digits) when is_binary(digits) do
    digits <> Integer.to_string(calculate(digits))
  end

  @doc """
  Validates that the last digit of `value` is the correct check digit for
  the digits preceding it.
  """
  def valid?(value) when is_binary(value) and byte_size(value) > 0 do
    {body, check_digit} = String.split_at(value, byte_size(value) - 1)
    Integer.to_string(calculate(body)) == check_digit
  end

  def valid?(_value), do: false
end
