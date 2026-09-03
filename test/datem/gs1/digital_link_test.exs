defmodule Datem.GS1.DigitalLinkTest do
  use ExUnit.Case, async: true

  alias Datem.GS1.{DigitalLink, Identifiers}

  describe "build/2 and parse/1 round-trip" do
    test "GSRN round-trips" do
      {:ok, gsrn} = Identifiers.build_gsrn("0614141", "1234567890")
      uri = DigitalLink.build(:gsrn, gsrn)

      assert uri == "https://id.datem.io/8018/#{gsrn}"
      assert {:ok, %{kind: :gsrn, ai: "8018", value: ^gsrn}} = DigitalLink.parse(uri)
    end

    test "GLN round-trips" do
      {:ok, gln} = Identifiers.build_gln("0614141", "12345")
      uri = DigitalLink.build(:gln, gln)

      assert {:ok, %{kind: :gln, ai: "414", value: ^gln}} = DigitalLink.parse(uri)
    end

    test "GIAI round-trips" do
      {:ok, giai} = Identifiers.build_giai("0614141", "VEHICLE001")
      uri = DigitalLink.build(:giai, giai)

      assert {:ok, %{kind: :giai, ai: "8004", value: ^giai}} = DigitalLink.parse(uri)
    end
  end

  describe "parse/1 validation" do
    test "rejects an unrecognised host" do
      {:ok, gsrn} = Identifiers.build_gsrn("0614141", "1234567890")
      assert {:error, :invalid_host} = DigitalLink.parse("https://evil.example/8018/#{gsrn}")
    end

    test "rejects an unrecognised AI" do
      assert {:error, :unrecognised_ai} = DigitalLink.parse("https://id.datem.io/9999/12345")
    end

    test "rejects a tampered check digit on a GSRN" do
      {:ok, gsrn} = Identifiers.build_gsrn("0614141", "1234567890")
      tampered_last_digit = gsrn |> String.last() |> String.to_integer() |> Kernel.+(1) |> rem(10)
      tampered = String.slice(gsrn, 0..-2//1) <> Integer.to_string(tampered_last_digit)

      assert {:error, :invalid_check_digit} =
               DigitalLink.parse("https://id.datem.io/8018/#{tampered}")
    end

    test "rejects a malformed URI" do
      assert {:error, :invalid_digital_link} = DigitalLink.parse("not a uri at all")
    end
  end
end
