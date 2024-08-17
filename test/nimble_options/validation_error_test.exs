defmodule NimbleOptions.ValidationErrorTest do
  use ExUnit.Case, async: true

  test "does not redact value when redact option is false" do
    schema = [foo: [type: :integer]]

    opts = [foo: "not an integer"]

    {:error, error} = NimbleOptions.validate(opts, schema)

    assert inspect(error) =~ "value: \"not an integer\""
  end

  test "redacts value when redact option is true" do
    schema = [foo: [type: :integer, redact: true]]

    opts = [foo: "not an integer"]

    {:error, error} = NimbleOptions.validate(opts, schema)

    assert inspect(error) =~ "value: \"**redacted**\""
  end
end
