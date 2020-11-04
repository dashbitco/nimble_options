defmodule NimbleOptions do
  @options_schema [
    *: [
      type: :keyword_list,
      keys: [
        type: [
          type: {:custom, __MODULE__, :validate_type, []},
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
        keys: [
          type: :keyword_list,
          doc: """
          Available for types `:keyword_list` and `:non_empty_keyword_list`,
          it defines which set of keys are accepted for the option item. The value of the
          `:keys` option is a schema itself. For example: `keys: [foo: [type: :atom]]`.
          Use `:*` as the key to allow multiple arbitrary keys and specify their schema:
          `keys: [*: [type: :integer]]`.
          """,
          keys: &__MODULE__.options_schema/0
        ],
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
          type: {:or, [:string, {:in, [false]}]},
          doc: "The documentation for the option item."
        ],
        subsection: [
          type: :string,
          doc: "The title of separate subsection of the options' documentation"
        ]
      ]
    ]
  ]

  @moduledoc """
  Provides a standard API to handle keyword-list-based options.

  `NimbleOptions` allows developers to create schemas using a
  pre-defined set of options and types. The main benefits are:

    * A single unified way to define simple static options
    * Config validation against schemas
    * Automatic doc generation

  ## Schema options

  These are the options supported in a *schema*. They are what
  defines the validation for the items in the given schema.

  #{NimbleOptions.Docs.generate(@options_schema, nest_levels: 0)}

  ## Types

    * `:any` - Any type.

    * `:keyword_list` - A keyword list.

    * `:non_empty_keyword_list` - A non-empty keyword list.

    * `:atom` - An atom.

    * `:string` - A string.

    * `:boolean` - A boolean.

    * `:integer` - An integer.

    * `:non_neg_integer` - A non-negative integer.

    * `:pos_integer` - A positive integer.

    * `:timeout` - A non-negative integer or the atom `:infinity`.

    * `:pid` - A PID (process identifier).

    * `:mfa` - A named function in the format `{module, function, arity}`

    * `:mod_arg` - A module along with arguments, e.g. `{MyModule, [arg1, arg2]}`.
      Usually used for process initialization using `start_link` and friends.

    * `{:fun, arity}` - Any function with the specified arity.

    * `{:in, choices}` - A value that is a member of one of the `choices`. `choices`
      should be a list of terms. The value is an element in said list of terms,
      that is, `value in choices` is `true`. Previously called `:one_of`.

    * `{:custom, mod, fun, args}` - A custom type. The related value must be validated
      by `mod.fun(values, ...args)`. The function should return `{:ok, value}` or
      `{:error, message}`.

    * `{:or, subtypes}` - A value that matches one of the given `subtypes`. The value is
      matched against the subtypes in the order specified in the list of `subtypes`. If
      one of the subtypes matches and **updates** (casts) the given value, the updated
      value is used. For example: `{:or, [:string, :boolean, {:fun, 2}]}`. If one of the
      subtypes is a keyword list, you won't be able to pass `:keys` directly. For this reason,
      keyword lists (`:keyword_list` and `:non_empty_keyword_list`) are special cased and can
      be used as subtypes with `{:keyword_list, keys}` or `{:non_empty_keyword_list, keys}`.
      For example, a type such as `{:or, [:boolean, keyword_list: [enabled: [type: :boolean]]]}`
      would match either a boolean or a keyword list with the `:enabled` boolean option in it.

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
      ...> {:error, %NimbleOptions.ValidationError{} = error} = NimbleOptions.validate(config, schema)
      ...> Exception.message(error)
      "required option :module not found, received options: [:concurrency] (in options [:producer])"

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
      ...> {:error, %NimbleOptions.ValidationError{} = error} = NimbleOptions.validate(config, schema)
      ...> Exception.message(error)
      "expected :interval to be a positive integer, got: :oops! (in options [:producer, :rate_limiting])"

  """

  alias NimbleOptions.ValidationError

  @basic_types [
    :any,
    :keyword_list,
    :non_empty_keyword_list,
    :atom,
    :integer,
    :non_neg_integer,
    :pos_integer,
    :mfa,
    :mod_arg,
    :string,
    :boolean,
    :timeout,
    :pid
  ]

  @typedoc """
  A schema. See the module documentation for more information.
  """
  @type schema() :: keyword()

  @doc """
  Validate the given `options` with the given `schema`.

  See the module documentation for what a `schema` is.

  If the validation is successful, this function returns `{:ok, validated_options}`
  where `validated_options` is a keyword list. If the validation fails, this
  function returns `{:error, validation_error}` where `validation_error` is a
  `NimbleOptions.ValidationError` struct explaining what's wrong with the options.
  You can use `raise/1` with that struct or `Exception.message/1` to turn it into a string.
  """
  @spec validate(keyword(), schema()) ::
          {:ok, validated_options :: keyword()} | {:error, ValidationError.t()}
  def validate(options, schema) when is_list(options) and is_list(schema) do
    case validate_options_with_schema(schema, options_schema()) do
      {:ok, _validated_schema} ->
        validate_options_with_schema(options, schema)

      {:error, %ValidationError{} = error} ->
        raise ArgumentError,
              "invalid schema given to NimbleOptions.validate/2. " <>
                "Reason: #{Exception.message(error)}"
    end
  end

  @doc """
  Validates the given `options` with the given `schema` and raises if they're not valid.

  This function behaves exactly like `validate/2`, but returns the options directly
  if they're valid or raises a `NimbleOptions.ValidationError` exception otherwise.
  """
  @spec validate!(keyword(), schema()) :: validated_options :: keyword()
  def validate!(options, schema) do
    case validate(options, schema) do
      {:ok, options} -> options
      {:error, %ValidationError{} = error} -> raise error
    end
  end

  @doc ~S"""
  Returns documentation for the given schema.

  You can use this to inject documentation in your docstrings. For example,
  say you have your schema in a module attribute:

      @options_schema [...]

  With this, you can use `docs/1` to inject documentation:

      @doc "Supported options:\n#{NimbleOptions.docs(@options_schema)}"

  ## Options

    * `:nest_levels` - an integer deciding the "nest level" of the generated
      docs. This is useful when, for example, you use `docs/2` inside the `:doc`
      option of another schema. For example, if you have the following nested schema:

          nested_schema = [
            allowed_messages: [type: :pos_integer, doc: "Allowed messages."],
            interval: [type: :pos_integer, doc: "Interval."]
          ]

      then you can document it inside another schema with its nesting level increased:

          schema = [
            producer: [
              type: {:or, [:string, keyword_list: nested_schema]},
              doc:
                "Either a string or a keyword list with the following keys:\n\n" <>
                  NimbleOptions.docs(nested_schema, nest_levels: 1)
            ],
            other_key: [type: :string]
          ]

  """
  @spec docs(schema(), keyword()) :: String.t()
  def docs(schema, options \\ []) when is_list(schema) and is_list(options) do
    NimbleOptions.Docs.generate(schema, options)
  end

  @doc false
  def options_schema() do
    @options_schema
  end

  defp validate_options_with_schema(opts, schema) do
    validate_options_with_schema_and_path(opts, schema, _path = [])
  end

  defp validate_options_with_schema_and_path(opts, fun, path) when is_function(fun) do
    validate_options_with_schema_and_path(opts, fun.(), path)
  end

  defp validate_options_with_schema_and_path(opts, schema, path) do
    schema = expand_star_to_option_keys(schema, opts)

    with :ok <- validate_unknown_options(opts, schema),
         {:ok, options} <- validate_options(schema, opts) do
      {:ok, options}
    else
      {:error, %ValidationError{} = error} ->
        {:error, %ValidationError{error | keys_path: path ++ error.keys_path}}
    end
  end

  defp validate_unknown_options(opts, schema) do
    valid_opts = Keyword.keys(schema)

    case Keyword.keys(opts) -- valid_opts do
      [] ->
        :ok

      keys ->
        error_tuple(
          keys,
          nil,
          "unknown options #{inspect(keys)}, valid options are: #{inspect(valid_opts)}"
        )
    end
  end

  defp validate_options(schema, opts) do
    case Enum.reduce_while(schema, opts, &reduce_options/2) do
      {:error, %ValidationError{}} = result -> result
      result -> {:ok, result}
    end
  end

  defp reduce_options({key, schema_opts}, opts) do
    case validate_option(opts, key, schema_opts) do
      {:error, %ValidationError{}} = result ->
        {:halt, result}

      {:ok, value} ->
        actual_key = schema_opts[:rename_to] || key
        {:cont, Keyword.update(opts, actual_key, value, fn _ -> value end)}

      :no_value ->
        if Keyword.has_key?(schema_opts, :default) do
          opts_with_default = Keyword.put(opts, key, schema_opts[:default])
          reduce_options({key, schema_opts}, opts_with_default)
        else
          {:cont, opts}
        end
    end
  end

  defp validate_option(opts, key, schema) do
    with {:ok, value} <- validate_value(opts, key, schema),
         :ok <- validate_type(schema[:type], key, value) do
      if nested_schema = schema[:keys] do
        validate_options_with_schema_and_path(value, nested_schema, _path = [key])
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
        error_tuple(
          key,
          nil,
          "required option #{inspect(key)} not found, received options: " <>
            inspect(Keyword.keys(opts))
        )

      true ->
        :no_value
    end
  end

  defp validate_type(:integer, key, value) when not is_integer(value) do
    error_tuple(key, value, "expected #{inspect(key)} to be an integer, got: #{inspect(value)}")
  end

  defp validate_type(:non_neg_integer, key, value) when not is_integer(value) or value < 0 do
    error_tuple(
      key,
      value,
      "expected #{inspect(key)} to be a non negative integer, got: #{inspect(value)}"
    )
  end

  defp validate_type(:pos_integer, key, value) when not is_integer(value) or value < 1 do
    error_tuple(
      key,
      value,
      "expected #{inspect(key)} to be a positive integer, got: #{inspect(value)}"
    )
  end

  defp validate_type(:atom, key, value) when not is_atom(value) do
    error_tuple(key, value, "expected #{inspect(key)} to be an atom, got: #{inspect(value)}")
  end

  defp validate_type(:timeout, key, value)
       when not (value == :infinity or (is_integer(value) and value >= 0)) do
    error_tuple(
      key,
      value,
      "expected #{inspect(key)} to be non-negative integer or :infinity, got: #{inspect(value)}"
    )
  end

  defp validate_type(:string, key, value) when not is_binary(value) do
    error_tuple(key, value, "expected #{inspect(key)} to be a string, got: #{inspect(value)}")
  end

  defp validate_type(:boolean, key, value) when not is_boolean(value) do
    error_tuple(key, value, "expected #{inspect(key)} to be a boolean, got: #{inspect(value)}")
  end

  defp validate_type(:keyword_list, key, value) do
    if keyword_list?(value) do
      :ok
    else
      error_tuple(
        key,
        value,
        "expected #{inspect(key)} to be a keyword list, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type(:non_empty_keyword_list, key, value) do
    if keyword_list?(value) && value != [] do
      :ok
    else
      error_tuple(
        key,
        value,
        "expected #{inspect(key)} to be a non-empty keyword list, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type(:pid, _key, value) when is_pid(value) do
    :ok
  end

  defp validate_type(:pid, key, value) do
    error_tuple(key, value, "expected #{inspect(key)} to be a pid, got: #{inspect(value)}")
  end

  defp validate_type(:mfa, _key, {m, f, args}) when is_atom(m) and is_atom(f) and is_list(args) do
    :ok
  end

  defp validate_type(:mfa, key, value) when not is_nil(value) do
    error_tuple(
      key,
      value,
      "expected #{inspect(key)} to be a tuple {Mod, Fun, Args}, got: #{inspect(value)}"
    )
  end

  defp validate_type(:mod_arg, _key, {m, _arg}) when is_atom(m) do
    :ok
  end

  defp validate_type(:mod_arg, key, value) do
    error_tuple(
      key,
      value,
      "expected #{inspect(key)} to be a tuple {Mod, Arg}, got: #{inspect(value)}"
    )
  end

  defp validate_type({:fun, arity}, key, value) do
    expected = "expected #{inspect(key)} to be a function of arity #{arity}, "

    if is_function(value) do
      case :erlang.fun_info(value, :arity) do
        {:arity, ^arity} ->
          :ok

        {:arity, fun_arity} ->
          error_tuple(key, value, expected <> "got: function of arity #{inspect(fun_arity)}")
      end
    else
      error_tuple(key, value, expected <> "got: #{inspect(value)}")
    end
  end

  defp validate_type({:custom, mod, fun, args}, key, value) do
    case apply(mod, fun, [value | args]) do
      {:ok, value} ->
        {:ok, value}

      {:error, message} when is_binary(message) ->
        error_tuple(key, value, message)

      other ->
        raise "custom validation function #{inspect(mod)}.#{fun}/#{length(args) + 1} " <>
                "must return {:ok, value} or {:error, message}, got: #{inspect(other)}"
    end
  end

  # TODO: remove on v0.5.
  defp validate_type({:one_of, choices}, key, value) do
    validate_type({:in, choices}, key, value)
  end

  defp validate_type({:in, choices}, key, value) do
    if value in choices do
      :ok
    else
      error_tuple(
        key,
        value,
        "expected #{inspect(key)} to be one of #{inspect(choices)}, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type({:or, subtypes}, key, value) do
    result =
      Enum.reduce_while(subtypes, _errors = [], fn subtype, errors_acc ->
        {subtype, nested_schema} =
          case subtype do
            {keyword_list, keys} when keyword_list in [:keyword_list, :non_empty_keyword_list] ->
              {keyword_list, keys}

            other ->
              {other, _nested_schema = nil}
          end

        case validate_type(subtype, key, value) do
          :ok when not is_nil(nested_schema) ->
            case validate_options_with_schema_and_path(value, nested_schema, _path = [key]) do
              {:ok, value} -> {:halt, {:ok, value}}
              {:error, %ValidationError{} = error} -> {:cont, [error | errors_acc]}
            end

          :ok ->
            {:halt, {:ok, value}}

          {:ok, value} ->
            {:halt, {:ok, value}}

          {:error, %ValidationError{} = reason} ->
            {:cont, [reason | errors_acc]}
        end
      end)

    case result do
      {:ok, value} ->
        {:ok, value}

      errors when is_list(errors) ->
        message =
          "expected #{inspect(key)} to match at least one given type, but didn't match " <>
            "any. Here are the reasons why it didn't match each of the allowed types:\n\n" <>
            Enum.map_join(errors, "\n", &("  * " <> Exception.message(&1)))

        error_tuple(key, value, message)
    end
  end

  defp validate_type(nil, key, value) do
    validate_type(:any, key, value)
  end

  defp validate_type(_type, _key, _value) do
    :ok
  end

  defp keyword_list?(value) do
    is_list(value) and Enum.all?(value, &match?({key, _value} when is_atom(key), &1))
  end

  defp expand_star_to_option_keys(keys, opts) do
    case keys[:*] do
      nil ->
        keys

      schema_opts ->
        Enum.map(opts, fn {k, _} -> {k, schema_opts} end)
    end
  end

  defp available_types() do
    types =
      Enum.map(@basic_types, &inspect/1) ++
        ["{:fun, arity}", "{:in, choices}", "{:or, subtypes}", "{:custom, mod, fun, args}"]

    Enum.join(types, ", ")
  end

  @doc false
  def validate_type(value) when value in @basic_types do
    {:ok, value}
  end

  def validate_type({:fun, arity} = value) when is_integer(arity) and arity >= 0 do
    {:ok, value}
  end

  # TODO: remove on v0.5.
  def validate_type({:one_of, choices}) do
    IO.warn("the {:one_of, choices} type is deprecated. Use {:in, choices} instead.")
    validate_type({:in, choices})
  end

  def validate_type({:in, choices} = value) when is_list(choices) do
    {:ok, value}
  end

  def validate_type({:custom, mod, fun, args} = value)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    {:ok, value}
  end

  def validate_type({:or, subtypes} = value) when is_list(subtypes) do
    Enum.reduce_while(subtypes, {:ok, value}, fn
      {keyword_list_type, _keys}, acc
      when keyword_list_type in [:keyword_list, :non_empty_keyword_list] ->
        {:cont, acc}

      subtype, acc ->
        case validate_type(subtype) do
          {:ok, _value} -> {:cont, acc}
          {:error, reason} -> {:halt, {:error, "invalid type in :or for reason: #{reason}"}}
        end
    end)
  end

  def validate_type(value) do
    {:error, "invalid option type #{inspect(value)}.\n\nAvailable types: #{available_types()}"}
  end

  defp error_tuple(key, value, message) do
    {:error, %ValidationError{key: key, message: message, value: value}}
  end
end
