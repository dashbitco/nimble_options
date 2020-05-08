defmodule NimbleOptions.ValidationError do
  @moduledoc """
  Raised when options are invalid.
  """

  defexception [:message]

  def exception(message) when is_binary(message) do
    %__MODULE__{message: message}
  end
end
