defmodule NimbleOptions.ValidationError do
  @moduledoc """
  An error that is returned (or raised) when options are invalid.

  Only the following documented fields are considered public. All other fields are
  considered private and should not be referenced:

    * `:key` - The key that did not successfully validate.

    * `:keys_path` - If the key is nested, this is the path to the key.

    * `:value` - The value that failed to validate. This field is `nil` if there was no
      value provided.

  Since this is an exception, you can either raise it directly with `raise/1`
  or turn it into a message string with `Exception.message/1`.
  """

  @type t() :: %__MODULE__{}

  defexception [:message, :key, :value, keys_path: []]

  @impl true
  def message(%__MODULE__{message: message, keys_path: keys_path}) do
    suffix =
      case keys_path do
        [] -> ""
        keys -> " (in options #{inspect(keys)})"
      end

    message <> suffix
  end
end
