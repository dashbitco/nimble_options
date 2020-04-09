defmodule NimbleOptionsTest do
  use ExUnit.Case, async: true

  doctest NimbleOptions

  test "known options" do
    schema = [name: [], context: []]
    opts = [name: MyProducer, context: :ok]

    assert NimbleOptions.validate(opts, schema) == {:ok, opts}
  end

  test "unknown options" do
    schema = [an_option: [], other_option: []]
    opts = [an_option: 1, not_an_option1: 1, not_an_option2: 1]

    assert NimbleOptions.validate(opts, schema) ==
             {:error,
              "unknown options [:not_an_option1, :not_an_option2], valid options are: [:an_option, :other_option]"}
  end

  describe "validate the schema itself before validating the options" do
    test "raise ArgumentError when invalid" do
      schema = [stages: [type: :foo]]
      opts = [stages: 1]

      message = """
      invalid schema given to NimbleOptions.validate/2. \
      Reason: (in options [:stages]) invalid option type :foo.

      Available types: :any, :keyword_list, :non_empty_keyword_list, :atom, \
      :non_neg_integer, :pos_integer, :mfa, :mod_arg, :string, :boolean, :timeout, \
      {:fun, arity}, {:one_of, choices}, {:custom, mod, fun, args}\
      """

      assert_raise ArgumentError, message, fn ->
        NimbleOptions.validate(opts, schema)
      end
    end

    test "validate the keys recursively, if any" do
      schema = [
        producers: [
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                module: [unknown_schema_option: 1],
                arg: []
              ]
            ]
          ]
        ]
      ]

      message = """
      invalid schema given to NimbleOptions.validate/2. \
      Reason: (in options [:producers, :keys, :*, :keys, :module]) \
      unknown options [:unknown_schema_option], \
      valid options are: [:type, :required, :default, :keys, \
      :deprecated, :rename_to, :doc, :subsection]\
      """

      assert_raise ArgumentError, message, fn ->
        NimbleOptions.validate([], schema)
      end
    end
  end

  describe "default value" do
    test "is used when none is given" do
      schema = [context: [default: :ok]]
      assert NimbleOptions.validate([], schema) == {:ok, [context: :ok]}
    end

    test "is not used when one is given" do
      schema = [context: [default: :ok]]
      assert NimbleOptions.validate([context: :given], schema) == {:ok, [context: :given]}
    end
  end

  describe "required options" do
    test "when present" do
      schema = [name: [required: true, type: :atom]]
      opts = [name: MyProducer]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "when missing" do
      schema = [name: [required: true], an_option: [], other_option: []]
      opts = [an_option: 1, other_option: 2]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "required option :name not found, received options: [:an_option, :other_option]"}
    end
  end

  describe "rename_to" do
    test "is renamed when given" do
      schema = [context: [rename_to: :new_context], new_context: []]

      assert NimbleOptions.validate([context: :ok], schema) ==
               {:ok, [{:context, :ok}, {:new_context, :ok}]}
    end

    test "is ignored when not given" do
      schema = [context: [rename_to: :new_context], new_context: []]
      assert NimbleOptions.validate([], schema) == {:ok, []}
    end

    test "is ignored with default" do
      schema = [context: [rename_to: :new_context, default: 1], new_context: []]
      assert NimbleOptions.validate([], schema) == {:ok, [context: 1]}
    end
  end

  describe "deprecated" do
    import ExUnit.CaptureIO

    test "warns when given" do
      schema = [context: [deprecated: "Use something else"]]

      assert capture_io(:stderr, fn ->
               assert NimbleOptions.validate([context: :ok], schema) == {:ok, [context: :ok]}
             end) =~ ":context is deprecated. Use something else"
    end

    test "does not warn when not given" do
      schema = [context: [deprecated: "Use something else"]]
      assert NimbleOptions.validate([], schema) == {:ok, []}
    end

    test "does not warn when using default" do
      schema = [context: [deprecated: "Use something else", default: :ok]]

      assert NimbleOptions.validate([], schema) == {:ok, [context: :ok]}
    end
  end

  describe "type validation" do
    test "valid positive integer" do
      schema = [stages: [type: :pos_integer]]
      opts = [stages: 1]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid positive integer" do
      schema = [stages: [type: :pos_integer]]

      assert NimbleOptions.validate([stages: 0], schema) ==
               {:error, "expected :stages to be a positive integer, got: 0"}

      assert NimbleOptions.validate([stages: :an_atom], schema) ==
               {:error, "expected :stages to be a positive integer, got: :an_atom"}
    end

    test "valid non negative integer" do
      schema = [min_demand: [type: :non_neg_integer]]
      opts = [min_demand: 0]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid non negative integer" do
      schema = [min_demand: [type: :non_neg_integer]]

      assert NimbleOptions.validate([min_demand: -1], schema) ==
               {:error, "expected :min_demand to be a non negative integer, got: -1"}

      assert NimbleOptions.validate([min_demand: :an_atom], schema) ==
               {:error, "expected :min_demand to be a non negative integer, got: :an_atom"}
    end

    test "valid atom" do
      schema = [name: [type: :atom]]
      opts = [name: :an_atom]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid atom" do
      schema = [name: [type: :atom]]

      assert NimbleOptions.validate([name: 1], schema) ==
               {:error, "expected :name to be an atom, got: 1"}
    end

    test "valid string" do
      schema = [doc: [type: :string]]
      opts = [doc: "a string"]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid string" do
      schema = [doc: [type: :string]]

      assert NimbleOptions.validate([doc: :an_atom], schema) ==
               {:error, "expected :doc to be an string, got: :an_atom"}
    end

    test "valid boolean" do
      schema = [required: [type: :boolean]]

      opts = [required: true]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [required: false]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid boolean" do
      schema = [required: [type: :boolean]]

      assert NimbleOptions.validate([required: :an_atom], schema) ==
               {:error, "expected :required to be an boolean, got: :an_atom"}
    end

    test "valid timeout" do
      schema = [timeout: [type: :timeout]]

      opts = [timeout: 0]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [timeout: 1000]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [timeout: :infinity]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid timeout" do
      schema = [timeout: [type: :timeout]]

      opts = [timeout: -1]

      assert NimbleOptions.validate(opts, schema) ==
               {:error, "expected :timeout to be non-negative integer or :infinity, got: -1"}

      opts = [timeout: :invalid]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "expected :timeout to be non-negative integer or :infinity, got: :invalid"}
    end

    test "valid mfa" do
      schema = [transformer: [type: :mfa]]

      opts = [transformer: {SomeMod, :func, [1, 2]}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [transformer: {SomeMod, :func, []}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid mfa" do
      schema = [transformer: [type: :mfa]]

      opts = [transformer: {"not_a_module", :func, []}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :transformer to be a tuple {Mod, Fun, Args}, got: {"not_a_module", :func, []})
             }

      opts = [transformer: {SomeMod, "not_a_func", []}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :transformer to be a tuple {Mod, Fun, Args}, got: {SomeMod, "not_a_func", []})
             }

      opts = [transformer: {SomeMod, :func, "not_a_list"}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :transformer to be a tuple {Mod, Fun, Args}, got: {SomeMod, :func, "not_a_list"})
             }

      opts = [transformer: NotATuple]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :transformer to be a tuple {Mod, Fun, Args}, got: NotATuple)
             }
    end

    test "valid mod_arg" do
      schema = [producer: [type: :mod_arg]]

      opts = [producer: {SomeMod, [1, 2]}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [producer: {SomeMod, []}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid mod_arg" do
      schema = [producer: [type: :mod_arg]]

      opts = [producer: NotATuple]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :producer to be a tuple {Mod, Arg}, got: NotATuple)
             }

      opts = [producer: {"not_a_module", []}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :producer to be a tuple {Mod, Arg}, got: {"not_a_module", []})
             }
    end

    test "valid {:fun, arity}" do
      schema = [partition_by: [type: {:fun, 1}]]

      opts = [partition_by: fn x -> x end]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [partition_by: &:erlang.phash2/1]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid {:fun, arity}" do
      schema = [partition_by: [type: {:fun, 1}]]

      opts = [partition_by: :not_a_fun]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :partition_by to be a function of arity 1, got: :not_a_fun)
             }

      opts = [partition_by: fn x, y -> x * y end]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :partition_by to be a function of arity 1, got: function of arity 2)
             }
    end

    test "valid {:one_of, choices}" do
      schema = [batch_mode: [type: {:one_of, [:flush, :bulk]}]]

      opts = [batch_mode: :flush]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [batch_mode: :bulk]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid {:one_of, choices}" do
      schema = [batch_mode: [type: {:one_of, [:flush, :bulk]}]]

      opts = [batch_mode: :invalid]

      assert NimbleOptions.validate(opts, schema) ==
               {:error, "expected :batch_mode to be one of [:flush, :bulk], got: :invalid"}
    end

    test "{:custom, mod, fun, args} with empty args" do
      schema = [buffer_keep: [type: {:custom, __MODULE__, :buffer_keep, []}]]

      opts = [buffer_keep: :first]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [buffer_keep: :last]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [buffer_keep: :unknown]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected :first or :last, got: :unknown)
             }
    end

    test "{:custom, mod, fun, args} with args" do
      schema = [buffer_keep: [type: {:custom, __MODULE__, :choice, [[:first, :last]]}]]

      opts = [buffer_keep: :first]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [buffer_keep: :last]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [buffer_keep: :unknown]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               ~s(expected one of [:first, :last], got: :unknown)
             }
    end

    test "{:custom, mod, fun, args} can also cast the value of an option" do
      schema = [connections: [type: {:custom, __MODULE__, :string_to_integer, []}]]

      opts = [connections: "5"]
      assert {:ok, validated_opts} = NimbleOptions.validate(opts, schema)
      assert length(validated_opts) == 1
      assert validated_opts[:connections] == 5
    end
  end

  describe "nested options with predefined keys" do
    test "known options" do
      schema = [
        processors: [
          type: :keyword_list,
          keys: [
            stages: [],
            max_demand: []
          ]
        ]
      ]

      opts = [processors: [stages: 1, max_demand: 2]]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "unknown options" do
      schema = [
        processors: [
          type: :keyword_list,
          keys: [
            stages: [],
            min_demand: []
          ]
        ]
      ]

      opts = [
        processors: [
          stages: 1,
          unknown_option1: 1,
          unknown_option2: 1
        ]
      ]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "(in options [:processors]) unknown options [:unknown_option1, :unknown_option2], valid options are: [:stages, :min_demand]"}
    end

    test "options with default values" do
      schema = [
        processors: [
          type: :keyword_list,
          keys: [
            stages: [default: 10]
          ]
        ]
      ]

      opts = [processors: []]

      assert NimbleOptions.validate(opts, schema) == {:ok, [processors: [stages: 10]]}
    end

    test "all required options present" do
      schema = [
        processors: [
          type: :keyword_list,
          keys: [
            stages: [required: true],
            max_demand: [required: true]
          ]
        ]
      ]

      opts = [processors: [stages: 1, max_demand: 2]]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "required options missing" do
      schema = [
        processors: [
          type: :keyword_list,
          keys: [
            stages: [required: true],
            max_demand: [required: true]
          ]
        ]
      ]

      opts = [processors: [max_demand: 1]]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "(in options [:processors]) required option :stages not found, received options: [:max_demand]"}
    end

    test "nested options types" do
      schema = [
        processors: [
          type: :keyword_list,
          keys: [
            name: [type: :atom],
            stages: [type: :pos_integer]
          ]
        ]
      ]

      opts = [processors: [name: MyModule, stages: :an_atom]]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "(in options [:processors]) expected :stages to be a positive integer, got: :an_atom"}
    end
  end

  describe "nested options with custom keys" do
    test "known options" do
      schema = [
        producers: [
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                module: [],
                arg: [type: :atom]
              ]
            ]
          ]
        ]
      ]

      opts = [producers: [producer1: [module: MyModule, arg: :atom]]]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "unknown options" do
      schema = [
        producers: [
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                module: [],
                arg: []
              ]
            ]
          ]
        ]
      ]

      opts = [producers: [producer1: [module: MyModule, arg: :ok, unknown_option: 1]]]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "(in options [:producers, :producer1]) unknown options [:unknown_option], valid options are: [:module, :arg]"}
    end

    test "options with default values" do
      schema = [
        producers: [
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                arg: [default: :ok]
              ]
            ]
          ]
        ]
      ]

      opts = [producers: [producer1: []]]

      assert NimbleOptions.validate(opts, schema) == {:ok, [producers: [producer1: [arg: :ok]]]}
    end

    test "all required options present" do
      schema = [
        producers: [
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                module: [required: true],
                arg: [required: true]
              ]
            ]
          ]
        ]
      ]

      opts = [producers: [default: [module: MyModule, arg: :ok]]]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "required options missing" do
      schema = [
        producers: [
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                module: [required: true],
                arg: [required: true]
              ]
            ]
          ]
        ]
      ]

      opts = [producers: [default: [module: MyModule]]]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "(in options [:producers, :default]) required option :arg not found, received options: [:module]"}
    end

    test "nested options types" do
      schema = [
        producers: [
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                module: [required: true, type: :atom],
                stages: [type: :pos_integer]
              ]
            ]
          ]
        ]
      ]

      opts = [
        producers: [
          producer1: [
            module: MyProducer,
            stages: :an_atom
          ]
        ]
      ]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "(in options [:producers, :producer1]) expected :stages to be a positive integer, got: :an_atom"}
    end

    test "validate empty keys for :non_empty_keyword_list" do
      schema = [
        producers: [
          type: :non_empty_keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                module: [required: true, type: :atom],
                stages: [type: :pos_integer]
              ]
            ]
          ]
        ]
      ]

      opts = [
        producers: []
      ]

      assert NimbleOptions.validate(opts, schema) ==
               {:error, "expected :producers to be a non-empty keyword list, got: []"}
    end

    test "allow empty keys for :keyword_list" do
      schema = [
        producers: [
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                module: [required: true, type: :atom],
                stages: [type: :pos_integer]
              ]
            ]
          ]
        ]
      ]

      opts = [
        producers: []
      ]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "default value for :keyword_list" do
      schema = [
        batchers: [
          required: false,
          default: [],
          type: :keyword_list,
          keys: [
            *: [
              type: :keyword_list,
              keys: [
                stages: [type: :pos_integer, default: 1]
              ]
            ]
          ]
        ]
      ]

      opts = []

      assert NimbleOptions.validate(opts, schema) == {:ok, [batchers: []]}
    end
  end

  describe "nested options show up in error messages" do
    test "for options that we validate" do
      schema = [
        socket_options: [
          type: :keyword_list,
          keys: [
            certificates: [
              type: :keyword_list,
              keys: [
                path: [type: :string]
              ]
            ]
          ]
        ]
      ]

      opts = [socket_options: [certificates: [path: :not_a_string]]]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                "(in options [:socket_options, :certificates]) expected :path to be an string, got: :not_a_string"}
    end
  end

  describe "docs" do
    test "override docs for recursive keys" do
      docs = """
      ## Options

        * `:type` - Required. The type of the option item.

        * `:required` - Defines if the option item is required. The default value is `false`.

        * `:keys` - Defines which set of keys are accepted.

      """

      assert NimbleOptions.docs(recursive_schema()) == docs
    end

    test "generate inline indented docs for nested options" do
      schema = [
        producer: [
          type: :non_empty_keyword_list,
          doc: "The producer. Supported options:",
          keys: [
            module: [type: :mod_arg, doc: "The module."],
            rate_limiting: [
              type: :non_empty_keyword_list,
              doc: """
              A list of options to enable and configure rate limiting. Supported options:
              """,
              keys: [
                allowed_messages: [type: :pos_integer, doc: "Number of messages per interval."],
                interval: [required: true, type: :pos_integer, doc: "The interval."]
              ]
            ]
          ]
        ]
      ]

      docs = """
      ## Options

        * `:producer` - The producer. Supported options:

          * `:module` - The module.

          * `:rate_limiting` - A list of options to enable and configure rate limiting. Supported options:

            * `:allowed_messages` - Number of messages per interval.

            * `:interval` - Required. The interval.

      """

      assert NimbleOptions.docs(schema) == docs
    end

    test "generate subsections for nested options" do
      schema = [
        name: [required: true, type: :atom, doc: "The name."],
        producer: [
          type: :non_empty_keyword_list,
          doc: "This is the producer summary. See \"Producers options\" section below.",
          subsection: """
          ### Producers options

          The producer options allow users to set up the producer.

          The available options are:
          """,
          keys: [
            module: [type: :mod_arg, doc: "The module."],
            concurrency: [type: :pos_integer, doc: "The concurrency."]
          ]
        ]
      ]

      docs = """
      ## Options

      In order to set up the pipeline, use the following options:

        * `:name` - Required. The name.

        * `:producer` - This is the producer summary. See "Producers options" section below.

      ### Producers options

      The producer options allow users to set up the producer.

      The available options are:

        * `:module` - The module.

        * `:concurrency` - The concurrency.

      """

      section_intro = "In order to set up the pipeline, use the following options:"

      assert NimbleOptions.docs(schema, section_intro) == docs
    end

    test "keep indentation of multiline doc" do
      schema = [
        name: [
          type: :string,
          doc: """
          The name.

          This a multiline text.

          Another line.
          """
        ],
        module: [
          type: :atom,
          doc: "The module."
        ]
      ]

      docs = """
      ## Options

        * `:name` - The name.

        This a multiline text.

        Another line.

        * `:module` - The module.

      """

      assert NimbleOptions.docs(schema) == docs
    end
  end

  def buffer_keep(value) when value in [:first, :last] do
    {:ok, value}
  end

  def buffer_keep(value) do
    {:error, "expected :first or :last, got: #{inspect(value)}"}
  end

  def choice(value, choices) do
    if value in choices do
      {:ok, value}
    else
      {:error, "expected one of #{inspect(choices)}, got: #{inspect(value)}"}
    end
  end

  def string_to_integer(value) do
    {:ok, String.to_integer(value)}
  end

  defp recursive_schema() do
    [
      *: [
        type: :keyword_list,
        keys: [
          type: [
            type: :atom,
            required: true,
            doc: "The type of the option item."
          ],
          required: [
            type: :boolean,
            default: false,
            doc: "Defines if the option item is required."
          ],
          keys: {
            &recursive_schema/0,
            doc: "Defines which set of keys are accepted."
          }
        ]
      ]
    ]
  end
end
