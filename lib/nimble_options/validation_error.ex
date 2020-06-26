defmodule NimbleOptions.ValidationError do
  @moduledoc """
  An error that is returned (or raised) when options are invalid.

  The contents of this exception are not public and you should not rely on
  its fields.

  Since this is an exception, you can either raise it directly with `raise/1`
  or turn it into a message string with `Exception.message/1`.
  """

  @type t() :: %__MODULE__{}

  defexception [:message, keys_path: []]

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
