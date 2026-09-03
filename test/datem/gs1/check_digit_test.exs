defmodule Datem.GS1.CheckDigitTest do
  use ExUnit.Case, async: true

  alias Datem.GS1.CheckDigit

  describe "calculate/1" do
    test "returns a single digit 0-9" do
      digit = CheckDigit.calculate("123456789012")
      assert digit in 0..9
    end

    test "is deterministic" do
      assert CheckDigit.calculate("123456789012") == CheckDigit.calculate("123456789012")
    end

    test "differs for different inputs (not a constant)" do
      digits = for n <- 100..120, do: CheckDigit.calculate(Integer.to_string(n))
      assert Enum.uniq(digits) |> length() > 1
    end
  end

  describe "append/1 and valid?/1" do
    test "append produces a value that valid? accepts" do
      value = CheckDigit.append("614141000000")
      assert CheckDigit.valid?(value)
    end

    test "flipping any digit in the body invalidates it" do
      value = CheckDigit.append("614141000000")
      {body, check_digit} = String.split_at(value, byte_size(value) - 1)

      tampered =
        String.replace(body, "6", "7", global: false) <> check_digit

      refute CheckDigit.valid?(tampered)
    end

    test "tampering with the check digit itself invalidates it" do
      value = CheckDigit.append("614141000000")
      {body, check_digit} = String.split_at(value, byte_size(value) - 1)
      tampered_digit = check_digit |> String.to_integer() |> Kernel.+(1) |> rem(10)

      refute CheckDigit.valid?(body <> Integer.to_string(tampered_digit))
    end

    test "valid? rejects non-numeric garbage" do
      refute CheckDigit.valid?("not-a-number")
    end
  end
end
