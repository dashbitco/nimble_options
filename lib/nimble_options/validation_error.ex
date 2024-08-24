defmodule NimbleOptions.ValidationError do
  @moduledoc """
  An error that is returned (or raised) when options are invalid.

  Since this is an exception, you can either raise it directly with `raise/1`
  or turn it into a message string with `Exception.message/1`.

  See [`%NimbleOptions.ValidationError{}`](`__struct__/0`) for documentation on the fields.
  """

  @type t() :: %__MODULE__{
          key: atom(),
          keys_path: [atom()],
          redact: boolean,
          value: term()
        }

  @doc """
  The error struct.

  Only the following documented fields are considered public. All other fields are
  considered private and should not be referenced:

    * `:key` (`t:atom/0`) - The key that did not successfully validate.

    * `:keys_path` (list of `t:atom/0`) - If the key is nested, this is the path to the key.

    * `:value` (`t:term/0`) - The value that failed to validate. This field is `nil` if there
      was no value provided.

  """
  defexception [:message, :key, :value, keys_path: [], redact: false]

  @impl true
  def message(%__MODULE__{message: message, keys_path: keys_path}) do
    suffix =
      case keys_path do
        [] -> ""
        keys -> " (in options #{inspect(keys)})"
      end

    message <> suffix
  end

  defimpl Inspect, for: NimbleOptions.ValidationError do
    import Inspect.Algebra

    def inspect(%{redact: redacted} = error, opts) do
      list =
        for attr <- [:key, :keys_path, :message, :value, :key] do
          {attr, Map.get(error, attr)}
        end

      container_doc("#NimbleOptions.ValidationError<", list, ">", %Inspect.Opts{limit: 4}, fn
        {:key, key}, _opts ->
          concat("key: ", to_doc(key, opts))

        {:keys_path, keys_path}, _opts ->
          concat("keys_path: ", to_doc(keys_path, opts))

        {:message, message}, _opts ->
          concat("message: ", to_doc(message, opts))

        {:value, value}, _opts ->
          value = if redacted, do: "**redacted**", else: value

          concat("value: ", to_doc(value, opts))
      end)
    end
  end
end
