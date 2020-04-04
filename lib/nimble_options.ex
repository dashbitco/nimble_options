defmodule NimbleOptions do
  @options_schema [
    type: :non_empty_keyword_list,
    keys: [
      *: [
        type: :keyword_list,
        keys: [
          type: [
            type: {:custom, __MODULE__, :type, []},
            default: :any,
            doc: "The type of the option item."
          ],
          required: [
            type: :boolean,
            default: false,
            doc: "Defines if the option item is required."
          ],
          default: [
            type: :any,
            doc: "The default value for option item if not specified."
          ],
          keys: {
            &__MODULE__.options_schema/0,
            doc: """
            Available for types `:keyword_list` and `:non_empty_keyword_list`,
            it defines which set of keys are accepted for the option item. Use `:*` as
            the key to allow multiple arbitrary keys.
            """
          },
          deprecated: [
            type: :string,
            doc: """
            Defines a message to indicate that the option item is deprecated. \
            The message will be displayed as a warning when passing the item.
            """
          ],
          rename_to: [
            type: :atom,
            doc: """
            Renames a option item allowing one to use a normalized name \
            internally, e.g. rename a deprecated item to the currently accepted name.
            """
          ],
          doc: [
            type: :string,
            doc: "The documentation for the option item."
          ],
          subsection: [
            type: :string,
            doc: "The title of separate subsection of the options' documentation"
          ]
        ]
      ]
    ]
  ]

  @moduledoc """
  Provides a standard API to handle keyword list based options.

  `NimbleOptions` allows developers to create schemas using a
  pre-defined set of options and types. The main benefits are:

    * A single unified way to define simple static options
    * Config validation against schemas
    * Automatic doc generation

  #{NimbleOptions.Docs.generate(@options_schema)}

  ## Types

    * `:any` - Any type.

    * `:keyword_list` - A keyword list.

    * `:non_empty_keyword_list` - A non-empty keyword list.

    * `:atom` - An atom.

    * `:string` - A string.

    * `:boolean` - A boolean.

    * `:non_neg_integer` - A non-negative integer.

    * `:pos_integer` - A positive integer.

    * `:mfa` - A named function in the format `{module, function, arity}`

    * `:mod_arg` - A module along with arguments, e.g. `{MyModule, [arg1, arg2]}`.
      Usually used for process initialization using `start_link` and friends.

    * `{:fun, arity}` - Any function with the specified arity.

    * `{:custom, mod, fun, args}` - A custom type. The related value must be validated
      by `mod.fun(values, ...args)`. The function should return `{:ok, value}` or
      `{:error, message}`.

  ## Example

      iex> schema = [
      ...>   producer: [
      ...>     type: :non_empty_keyword_list,
      ...>     required: true,
      ...>     keys: [
      ...>       module: [required: true, type: :mod_arg],
      ...>       concurrency: [
      ...>         type: :pos_integer,
      ...>       ]
      ...>     ]
      ...>   ]
      ...> ]
      ...>
      ...> config = [
      ...>   producer: [
      ...>     concurrency: 1,
      ...>   ]
      ...> ]
      ...>
      ...> NimbleOptions.validate(config, schema)
      {:error, "required option :module not found, received options: [:concurrency]"}

  ## Nested option items

  `NimbleOptions` allows option items to be nested so you can recursively validate
  any item down the options tree.

  ### Example

      iex> schema = [
      ...>   producer: [
      ...>     required: true,
      ...>     type: :non_empty_keyword_list,
      ...>     keys: [
      ...>       rate_limiting: [
      ...>         type: :non_empty_keyword_list,
      ...>         keys: [
      ...>           interval: [required: true, type: :pos_integer]
      ...>         ]
      ...>       ]
      ...>     ]
      ...>   ]
      ...> ]
      ...>
      ...> config = [
      ...>   producer: [
      ...>     rate_limiting: [
      ...>       interval: :oops!
      ...>     ]
      ...>   ]
      ...> ]
      ...>
      ...> NimbleOptions.validate(config, schema)
      {:error, "expected :interval to be a positive integer, got: :oops!"}

  """

  @basic_types [
    :any,
    :keyword_list,
    :non_empty_keyword_list,
    :atom,
    :non_neg_integer,
    :pos_integer,
    :mfa,
    :mod_arg,
    :string,
    :boolean
  ]

  @type schema() :: keyword()

  @doc """
  Validate the given `options` with the given `schema`.

  See the module documentation for what a `schema` is.

  If the validation is successful, this function returns `{:ok, validated_options}`
  where `validated_options` is a keyword list. If the validation fails, this
  function returns `{:error, reason}` where `reason` is an error message (a string)
  telling what's wrong with the given options.
  """
  @spec validate(keyword(), schema()) ::
          {:ok, validated_options :: keyword()} | {:error, reason :: String.t()}
  def validate(options, schema) do
    case validate_options_with_schema([root: schema], root: options_schema()) do
      {:error, message} ->
        raise ArgumentError,
              "invalid schema given to NimbleOptions.validate/2. Reason: #{message}"

      _ ->
        validate_options_with_schema(options, schema)
    end
  end

  @doc ~S"""
  Returns documentation for the given schema.

  You can use this to inject documentation in your docstrings. For example,
  say you have your schema in a module attribute:

      @options_schema [...]

  With this, you can use `docs/1` to inject documentation:

      @doc "Supported options:\n#{NimbleOptions.docs(@options_schema)}"

  """
  @spec docs(schema()) :: String.t()
  def docs(schema) do
    NimbleOptions.Docs.generate(schema)
  end

  @doc false
  def options_schema() do
    @options_schema
  end

  defp validate_options_with_schema(opts, schema) do
    case validate_unknown_options(opts, schema) do
      :ok -> validate_options(schema, opts)
      error -> error
    end
  end

  defp validate_unknown_options(opts, schema) do
    valid_opts = Keyword.keys(schema)

    case Keyword.keys(opts) -- valid_opts do
      [] ->
        :ok

      keys ->
        {:error, "unknown options #{inspect(keys)}, valid options are: #{inspect(valid_opts)}"}
    end
  end

  defp validate_options(schema, opts) do
    case Enum.reduce_while(schema, opts, &reduce_options/2) do
      {:error, _} = result -> result
      result -> {:ok, result}
    end
  end

  defp reduce_options({key, schema_fun}, opts) when is_function(schema_fun) do
    reduce_options({key, schema_fun.()}, opts)
  end

  defp reduce_options({key, {schema_fun, overrides}}, opts) when is_function(schema_fun) do
    schema_opts = Keyword.merge(schema_fun.(), overrides || [])
    reduce_options({key, schema_opts}, opts)
  end

  defp reduce_options({key, schema_opts}, opts) do
    case validate_option(opts, key, schema_opts) do
      {:error, _} = result ->
        {:halt, result}

      {:ok, value} ->
        actual_key = schema_opts[:rename_to] || key
        {:cont, Keyword.update(opts, actual_key, value, fn _ -> value end)}

      :no_value ->
        if Keyword.has_key?(schema_opts, :default) do
          {:cont, Keyword.put(opts, key, schema_opts[:default])}
        else
          {:cont, opts}
        end
    end
  end

  defp validate_option(opts, key, schema) do
    with {:ok, value} <- validate_value(opts, key, schema),
         :ok <- validate_type(schema[:type], key, value) do
      if schema[:keys] do
        keys = normalize_keys(schema[:keys], value)
        validate_options_with_schema(value, keys)
      else
        {:ok, value}
      end
    end
  end

  defp validate_value(opts, key, schema) do
    cond do
      Keyword.has_key?(opts, key) ->
        if message = Keyword.get(schema, :deprecated) do
          IO.warn("#{inspect(key)} is deprecated. " <> message)
        end

        {:ok, opts[key]}

      Keyword.get(schema, :required, false) ->
        {:error,
         "required option #{inspect(key)} not found, received options: " <>
           inspect(Keyword.keys(opts))}

      true ->
        :no_value
    end
  end

  defp validate_type(:non_neg_integer, key, value) when not is_integer(value) or value < 0 do
    {:error, "expected #{inspect(key)} to be a non negative integer, got: #{inspect(value)}"}
  end

  defp validate_type(:pos_integer, key, value) when not is_integer(value) or value < 1 do
    {:error, "expected #{inspect(key)} to be a positive integer, got: #{inspect(value)}"}
  end

  defp validate_type(:atom, key, value) when not is_atom(value) do
    {:error, "expected #{inspect(key)} to be an atom, got: #{inspect(value)}"}
  end

  defp validate_type(:string, key, value) when not is_binary(value) do
    {:error, "expected #{inspect(key)} to be an string, got: #{inspect(value)}"}
  end

  defp validate_type(:boolean, key, value) when not is_boolean(value) do
    {:error, "expected #{inspect(key)} to be an boolean, got: #{inspect(value)}"}
  end

  defp validate_type(:keyword_list, key, value) do
    if keyword_list?(value) do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a keyword list, got: #{inspect(value)}"}
    end
  end

  defp validate_type(:non_empty_keyword_list, key, value) do
    if keyword_list?(value) && value != [] do
      :ok
    else
      {:error, "expected #{inspect(key)} to be a non-empty keyword list, got: #{inspect(value)}"}
    end
  end

  defp validate_type(:mfa, _key, {m, f, args}) when is_atom(m) and is_atom(f) and is_list(args) do
    :ok
  end

  defp validate_type(:mfa, key, value) when not is_nil(value) do
    {:error, "expected #{inspect(key)} to be a tuple {Mod, Fun, Args}, got: #{inspect(value)}"}
  end

  defp validate_type(:mod_arg, _key, {m, _arg}) when is_atom(m) do
    :ok
  end

  defp validate_type(:mod_arg, key, value) do
    {:error, "expected #{inspect(key)} to be a tuple {Mod, Arg}, got: #{inspect(value)}"}
  end

  defp validate_type({:fun, arity}, key, value) do
    expected = "expected #{inspect(key)} to be a function of arity #{arity}, "

    if is_function(value) do
      case :erlang.fun_info(value, :arity) do
        {:arity, ^arity} ->
          :ok

        {:arity, fun_arity} ->
          {:error, expected <> "got: function of arity #{inspect(fun_arity)}"}
      end
    else
      {:error, expected <> "got: #{inspect(value)}"}
    end
  end

  defp validate_type({:custom, mod, fun, args}, _key, value) do
    apply(mod, fun, [value | args])
  end

  defp validate_type(nil, key, value) do
    validate_type(:any, key, value)
  end

  defp validate_type(_type, _key, _value) do
    :ok
  end

  defp tagged_tuple?({key, _value}) when is_atom(key), do: true
  defp tagged_tuple?(_), do: false

  defp keyword_list?(value) do
    is_list(value) && Enum.all?(value, &tagged_tuple?/1)
  end

  defp normalize_keys(keys, opts) do
    case keys[:*] do
      nil ->
        keys

      schema_opts ->
        Enum.map(opts, fn {k, _} -> {k, schema_opts} end)
    end
  end

  defp available_types() do
    types = Enum.map(@basic_types, &inspect/1) ++ ["{:fun, arity}", "{:custom, mod, fun, args}"]
    Enum.join(types, ", ")
  end

  @doc false
  def type(value) when value in @basic_types do
    {:ok, value}
  end

  def type({:fun, arity} = value) when is_integer(arity) and arity >= 0 do
    {:ok, value}
  end

  def type({:custom, mod, fun, args} = value)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    {:ok, value}
  end

  def type(value) do
    {:error, "invalid option type #{inspect(value)}.\n\nAvailable types: #{available_types()}"}
  end
end
