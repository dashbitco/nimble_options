defmodule NimbleOptions.ValidationErrorTest do
  use ExUnit.Case, async: true

  alias NimbleOptions.ValidationError

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

  test "message is redacted when an error is raised" do
    schema = [foo: [type: :integer, redact: true]]

    opts = [foo: "not an integer"]

    assert_raise(ValidationError, "invalid value for :foo option: expected integer", fn ->
      NimbleOptions.validate!(opts, schema)
    end)
  end

  describe "Inspect implementation" do
    test "inspects fine" do
      schema = [foo: [type: :integer]]

      opts = [foo: true]

      {:error, error} = NimbleOptions.validate(opts, schema)

      assert inspect(error) ==
               ~s(#NimbleOptions.ValidationError<key: :foo, keys_path: [], message: "invalid value for :foo option: expected integer, got: true", redact: false, value: true>)
    end

    test "with a redacted option" do
      schema = [foo: [type: :integer, redact: true]]

      opts = [foo: "not an integer"]

      {:error, error} = NimbleOptions.validate(opts, schema)

      assert inspect(error) ==
               ~s(#NimbleOptions.ValidationError<key: :foo, keys_path: [], message: "invalid value for :foo option: expected integer", redact: true, value: "**redacted**">)
    end
  end
end
