defmodule Datem.GS1.IdentifiersTest do
  use ExUnit.Case, async: true

  alias Datem.GS1.{CheckDigit, Identifiers}

  describe "build_gln/2" do
    test "builds a 13-digit, check-digit-valid GLN" do
      assert {:ok, gln} = Identifiers.build_gln("0614141", "12345")
      assert String.length(gln) == 13
      assert CheckDigit.valid?(gln)
      assert String.starts_with?(gln, "0614141")
    end

    test "rejects a reference that doesn't fit the remaining length" do
      assert {:error, :reference_too_long} = Identifiers.build_gln("0614141", "123456")
    end

    test "rejects a malformed company prefix" do
      assert {:error, :invalid_company_prefix} = Identifiers.build_gln("abc", "12345")
      assert {:error, :invalid_company_prefix} = Identifiers.build_gln("123", "12345")
    end
  end

  describe "build_gsrn/2" do
    test "builds an 18-digit, check-digit-valid GSRN" do
      assert {:ok, gsrn} = Identifiers.build_gsrn("0614141", "1234567890")
      assert String.length(gsrn) == 18
      assert CheckDigit.valid?(gsrn)
    end
  end

  describe "build_giai/2" do
    test "builds an alphanumeric GIAI with no check digit" do
      assert {:ok, giai} = Identifiers.build_giai("0614141", "VEHICLE001")
      assert giai == "0614141VEHICLE001"
    end

    test "rejects non-alphanumeric references" do
      assert {:error, :invalid_reference} = Identifiers.build_giai("0614141", "not valid!")
    end

    test "rejects references longer than 30 characters once combined constraints are considered" do
      assert {:error, :reference_too_long} =
               Identifiers.build_giai("0614141", String.duplicate("A", 31))
    end
  end

  test "internal_company_prefix/0 is a structurally-valid but reserved prefix" do
    prefix = Identifiers.internal_company_prefix()
    assert String.match?(prefix, ~r/^\d{6,10}$/)
  end
end
