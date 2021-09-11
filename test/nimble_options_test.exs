defmodule NimbleOptionsTest do
  use ExUnit.Case, async: true

  doctest NimbleOptions

  import ExUnit.CaptureIO

  alias NimbleOptions.ValidationError

  describe "validate keys" do
    test "known options without types" do
      schema = [name: [], context: []]
      opts = [name: MyProducer, context: :ok]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "unknown options" do
      schema = [an_option: [], other_option: []]
      opts = [an_option: 1, not_an_option1: 1, not_an_option2: 1]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: [:not_an_option1, :not_an_option2],
                  value: nil,
                  message:
                    "unknown options [:not_an_option1, :not_an_option2], valid options are: [:an_option, :other_option]"
                }}
    end
  end

  describe "validate the schema itself before validating the options" do
    test "raise ArgumentError when invalid" do
      schema = [stages: [type: :foo]]
      opts = [stages: 1]

      message = """
      invalid schema given to NimbleOptions.validate/2. \
      Reason: invalid option type :foo.

      Available types: :any, :keyword_list, :non_empty_keyword_list, :atom, \
      :integer, :non_neg_integer, :pos_integer, :float, :mfa, :mod_arg, :string, :boolean, :timeout, \
      :pid, {:fun, arity}, {:in, choices}, {:or, subtypes}, {:custom, mod, fun, args}, \
      {:list, subtype} \
      (in options [:stages])\
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
      Reason: \
      unknown options [:unknown_schema_option], \
      valid options are: [:type, :required, :default, :keys, \
      :deprecated, :rename_to, :doc, :subsection] \
      (in options [:producers, :keys, :*, :keys, :module])\
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

    test "is validated" do
      schema = [
        processors: [
          type: :keyword_list,
          default: [],
          keys: [
            stages: [type: :integer, default: "10"]
          ]
        ]
      ]

      opts = [processors: []]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :stages,
                 keys_path: [:processors],
                 message: "expected :stages to be an integer, got: \"10\"",
                 value: "10"
               }
             }
    end
  end

  describe ":required" do
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
                %ValidationError{
                  key: :name,
                  message:
                    "required option :name not found, received options: [:an_option, :other_option]"
                }}
    end
  end

  describe ":rename_to" do
    test "renames option when true" do
      schema = [context: [rename_to: :new_context], new_context: []]

      assert NimbleOptions.validate([context: :ok], schema) ==
               {:ok, [{:context, :ok}, {:new_context, :ok}]}
    end

    test "is ignored when option is not present given" do
      schema = [context: [rename_to: :new_context], new_context: []]
      assert NimbleOptions.validate([], schema) == {:ok, []}
    end
  end

  describe ":doc" do
    test "valid documentation for key" do
      schema = [context: [doc: "details", default: 1]]
      assert NimbleOptions.validate([], schema) == {:ok, [context: 1]}
      schema = [context: [doc: false, default: 1]]
      assert NimbleOptions.validate([], schema) == {:ok, [context: 1]}
    end

    test "invalid documentation for key" do
      message = """
      invalid schema given to NimbleOptions.validate/2. Reason: expected :doc to match at least \
      one given type, but didn't match any. Here are the reasons why it didn't match each of the \
      allowed types:

        * expected :doc to be one of [false], got: 1
        * expected :doc to be a string, got: 1 (in options [:context])\
      """

      assert_raise ArgumentError, message, fn ->
        schema = [context: [doc: 1, default: 1]]
        NimbleOptions.validate([], schema)
      end
    end
  end

  describe ":deprecated" do
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

    test "warns when using default" do
      schema = [context: [deprecated: "Use something else", default: :ok]]

      assert capture_io(:stderr, fn ->
               assert NimbleOptions.validate([], schema) == {:ok, [context: :ok]}
             end) =~ ":context is deprecated. Use something else"
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
               {:error,
                %ValidationError{
                  key: :stages,
                  value: 0,
                  message: "expected :stages to be a positive integer, got: 0"
                }}

      assert NimbleOptions.validate([stages: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :stages,
                  value: :an_atom,
                  message: "expected :stages to be a positive integer, got: :an_atom"
                }}
    end

    test "valid integer" do
      schema = [min_demand: [type: :integer]]
      opts = [min_demand: 12]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid integer" do
      schema = [min_demand: [type: :integer]]

      assert NimbleOptions.validate([min_demand: 1.5], schema) ==
               {:error,
                %ValidationError{
                  key: :min_demand,
                  value: 1.5,
                  message: "expected :min_demand to be an integer, got: 1.5"
                }}

      assert NimbleOptions.validate([min_demand: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :min_demand,
                  value: :an_atom,
                  message: "expected :min_demand to be an integer, got: :an_atom"
                }}
    end

    test "valid non negative integer" do
      schema = [min_demand: [type: :non_neg_integer]]
      opts = [min_demand: 0]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid non negative integer" do
      schema = [min_demand: [type: :non_neg_integer]]

      assert NimbleOptions.validate([min_demand: -1], schema) ==
               {:error,
                %ValidationError{
                  key: :min_demand,
                  value: -1,
                  message: "expected :min_demand to be a non negative integer, got: -1"
                }}

      assert NimbleOptions.validate([min_demand: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :min_demand,
                  value: :an_atom,
                  message: "expected :min_demand to be a non negative integer, got: :an_atom"
                }}
    end

    test "valid float" do
      schema = [certainty: [type: :float]]
      opts = [certainty: 0.5]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid float" do
      schema = [certainty: [type: :float]]

      assert NimbleOptions.validate([certainty: 1], schema) ==
               {:error,
                %ValidationError{
                  key: :certainty,
                  value: 1,
                  message: "expected :certainty to be a float, got: 1"
                }}

      assert NimbleOptions.validate([certainty: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :certainty,
                  value: :an_atom,
                  message: "expected :certainty to be a float, got: :an_atom"
                }}
    end

    test "valid atom" do
      schema = [name: [type: :atom]]
      opts = [name: :an_atom]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid atom" do
      schema = [name: [type: :atom]]

      assert NimbleOptions.validate([name: 1], schema) ==
               {:error,
                %ValidationError{
                  key: :name,
                  value: 1,
                  message: "expected :name to be an atom, got: 1"
                }}
    end

    test "valid string" do
      schema = [doc: [type: :string]]
      opts = [doc: "a string"]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid string" do
      schema = [doc: [type: :string]]

      assert NimbleOptions.validate([doc: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :doc,
                  value: :an_atom,
                  message: "expected :doc to be a string, got: :an_atom"
                }}
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
               {:error,
                %ValidationError{
                  key: :required,
                  value: :an_atom,
                  message: "expected :required to be a boolean, got: :an_atom"
                }}
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
               {:error,
                %ValidationError{
                  key: :timeout,
                  value: -1,
                  message: "expected :timeout to be non-negative integer or :infinity, got: -1"
                }}

      opts = [timeout: :invalid]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :timeout,
                  value: :invalid,
                  message:
                    "expected :timeout to be non-negative integer or :infinity, got: :invalid"
                }}
    end

    test "valid pid" do
      schema = [name: [type: :pid]]
      opts = [name: self()]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid pid" do
      schema = [name: [type: :pid]]

      assert NimbleOptions.validate([name: 1], schema) ==
               {:error,
                %ValidationError{
                  key: :name,
                  value: 1,
                  message: "expected :name to be a pid, got: 1"
                }}
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
               %ValidationError{
                 key: :transformer,
                 value: {"not_a_module", :func, []},
                 message:
                   ~s(expected :transformer to be a tuple {Mod, Fun, Args}, got: {"not_a_module", :func, []})
               }
             }

      opts = [transformer: {SomeMod, "not_a_func", []}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :transformer,
                 value: {SomeMod, "not_a_func", []},
                 message:
                   ~s(expected :transformer to be a tuple {Mod, Fun, Args}, got: {SomeMod, "not_a_func", []})
               }
             }

      opts = [transformer: {SomeMod, :func, "not_a_list"}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :transformer,
                 value: {SomeMod, :func, "not_a_list"},
                 message:
                   ~s(expected :transformer to be a tuple {Mod, Fun, Args}, got: {SomeMod, :func, "not_a_list"})
               }
             }

      opts = [transformer: NotATuple]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :transformer,
                 value: NotATuple,
                 message: ~s(expected :transformer to be a tuple {Mod, Fun, Args}, got: NotATuple)
               }
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
               %ValidationError{
                 key: :producer,
                 value: NotATuple,
                 message: ~s(expected :producer to be a tuple {Mod, Arg}, got: NotATuple)
               }
             }

      opts = [producer: {"not_a_module", []}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :producer,
                 value: {"not_a_module", []},
                 message:
                   ~s(expected :producer to be a tuple {Mod, Arg}, got: {"not_a_module", []})
               }
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
               %ValidationError{
                 key: :partition_by,
                 value: :not_a_fun,
                 message: ~s(expected :partition_by to be a function of arity 1, got: :not_a_fun)
               }
             }

      opts = [partition_by: fn x, y -> x * y end]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :partition_by,
                 value: opts[:partition_by],
                 message:
                   ~s(expected :partition_by to be a function of arity 1, got: function of arity 2)
               }
             }
    end

    test "valid {:in, choices}" do
      schema = [batch_mode: [type: {:in, [:flush, :bulk]}]]

      opts = [batch_mode: :flush]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [batch_mode: :bulk]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid {:in, choices}" do
      schema = [batch_mode: [type: {:in, [:flush, :bulk]}]]

      opts = [batch_mode: :invalid]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :batch_mode,
                  value: :invalid,
                  message: "expected :batch_mode to be one of [:flush, :bulk], got: :invalid"
                }}
    end

    test "deprecation of {:one_of, choices}" do
      schema = [batch_mode: [type: {:one_of, [:flush, :bulk]}]]

      assert capture_io(:stderr, fn ->
               opts = [batch_mode: :flush]
               assert NimbleOptions.validate(opts, schema) == {:ok, opts}
             end) =~ "the {:one_of, choices} type is deprecated"
    end

    test "valid {:or, subtypes} with simple subtypes" do
      schema = [docs: [type: {:or, [:string, :boolean]}]]

      opts = [docs: false]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [docs: true]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [docs: "a string"]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "valid {:or, subtypes} with compound subtypes" do
      schema = [docs: [type: {:or, [{:custom, __MODULE__, :string_to_integer, []}, :string]}]]

      opts = [docs: "a string"]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [docs: "123"]
      assert NimbleOptions.validate(opts, schema) == {:ok, [docs: 123]}
    end

    test "valid {:or, subtypes} with nested :or" do
      # Nested :or.
      schema = [
        docs: [
          type:
            {:or,
             [
               {:or, [{:custom, __MODULE__, :string_to_integer, []}, :boolean]},
               {:or, [:string]}
             ]}
        ]
      ]

      opts = [docs: "123"]
      assert NimbleOptions.validate(opts, schema) == {:ok, [docs: 123]}

      opts = [docs: "a string"]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [docs: false]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "valid {:or, subtypes} with nested keyword lists" do
      schema = [
        docs: [
          type: {:or, [:boolean, keyword_list: [enabled: [type: :boolean]]]}
        ]
      ]

      opts = [docs: false]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [docs: [enabled: true]]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid {:or, subtypes}" do
      schema = [docs: [type: {:or, [:string, :boolean]}]]

      opts = [docs: :invalid]

      expected_message = """
      expected :docs to match at least one given type, but didn't match any. Here are the \
      reasons why it didn't match each of the allowed types:

        * expected :docs to be a boolean, got: :invalid
        * expected :docs to be a string, got: :invalid\
      """

      assert NimbleOptions.validate(opts, schema) ==
               {:error, %ValidationError{key: :docs, value: :invalid, message: expected_message}}
    end

    test "invalid {:or, subtypes} with nested :or" do
      schema = [
        docs: [
          type:
            {:or,
             [
               {:or, [{:custom, __MODULE__, :string_to_integer, []}, :boolean]},
               {:or, [:string]}
             ]}
        ]
      ]

      opts = [docs: 1]

      expected_message = """
      expected :docs to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * expected :docs to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * expected :docs to be a string, got: 1
        * expected :docs to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * expected :docs to be a boolean, got: 1
        * expected to be a string, got: 1\
      """

      assert NimbleOptions.validate(opts, schema) ==
               {:error, %ValidationError{key: :docs, value: 1, message: expected_message}}
    end

    test "invalid {:or, subtypes} with nested keyword lists" do
      schema = [
        docs: [
          type: {:or, [:boolean, keyword_list: [enabled: [type: :boolean]]]}
        ]
      ]

      opts = [docs: "123"]

      expected_message = """
      expected :docs to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * expected :docs to be a keyword list, got: "123"
        * expected :docs to be a boolean, got: "123"\
      """

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :docs,
                  value: "123",
                  keys_path: [],
                  message: expected_message
                }}

      opts = [docs: [enabled: "not a boolean"]]

      expected_message = """
      expected :docs to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * expected :enabled to be a boolean, got: "not a boolean" (in options [:docs])
        * expected :docs to be a boolean, got: [enabled: "not a boolean"]\
      """

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :docs,
                 value: [enabled: "not a boolean"],
                 keys_path: [],
                 message: expected_message
               }
             }
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
               %ValidationError{
                 key: :buffer_keep,
                 value: :unknown,
                 message: ~s(expected :first or :last, got: :unknown)
               }
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
               %ValidationError{
                 key: :buffer_keep,
                 value: :unknown,
                 message: ~s(expected one of [:first, :last], got: :unknown)
               }
             }
    end

    test "{:custom, mod, fun, args} can also cast the value of an option" do
      schema = [connections: [type: {:custom, __MODULE__, :string_to_integer, []}]]

      opts = [connections: "5"]
      assert {:ok, validated_opts} = NimbleOptions.validate(opts, schema)
      assert length(validated_opts) == 1
      assert validated_opts[:connections] == 5
    end

    test "{:custom, mod, fun, args} enforces the returned value of the function" do
      schema = [my_option: [type: {:custom, __MODULE__, :misbehaving_custom_validator, []}]]

      message =
        "custom validation function NimbleOptionsTest.misbehaving_custom_validator/1 " <>
          "must return {:ok, value} or {:error, message}, got: :ok"

      assert_raise RuntimeError, message, fn ->
        assert NimbleOptions.validate([my_option: :whatever], schema)
      end
    end

    test "valid {:list, subtype}" do
      schema = [metadata: [type: {:list, :atom}]]

      opts = [metadata: [:foo, :bar, :baz]]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      # Nested lists
      schema = [metadata: [type: {:list, {:list, :atom}}]]

      opts = [metadata: [[:foo, :bar], [:baz]]]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid {:list, subtype}" do
      schema = [metadata: [type: {:list, :atom}]]

      # Not a list
      opts = [metadata: "not a list"]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :metadata,
                  keys_path: [],
                  message: "expected :metadata to be a list, got: \"not a list\"",
                  value: "not a list"
                }}

      # List with invalid elements
      opts = [metadata: [:foo, :bar, "baz", :bong, "another invalid value"]]

      message = """
      list element at position 2 in :metadata failed validation: expected "list element" \
      to be an atom, got: "baz"\
      """

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :metadata,
                 keys_path: [],
                 message: message,
                 value: [:foo, :bar, "baz", :bong, "another invalid value"]
               }
             }

      # Nested list with invalid elements
      schema = [metadata: [type: {:list, {:list, :atom}}]]
      opts = [metadata: [[:foo, :bar], ["baz", :bong, "another invalid value"]]]

      message = """
      list element at position 1 in :metadata failed validation: \
      list element at position 0 in "list element" failed validation: \
      expected "list element" to be an atom, got: "baz"\
      """

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :metadata,
                 keys_path: [],
                 message: message,
                 value: [[:foo, :bar], ["baz", :bong, "another invalid value"]]
               }
             }
    end

    test "{:list, subtype} with custom subtype" do
      schema = [metadata: [type: {:list, {:custom, __MODULE__, :string_to_integer, []}}]]

      # Valid
      opts = [metadata: ["123", "456"]]
      assert NimbleOptions.validate(opts, schema) == {:ok, [metadata: [123, 456]]}

      # Invalid
      opts = [metadata: ["123", "not an int"]]

      message = """
      list element at position 1 in :metadata failed validation: expected string to be \
      convertable to integer\
      """

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :metadata,
                 keys_path: [],
                 message: message,
                 value: ["123", "not an int"]
               }
             }
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
                %ValidationError{
                  key: [:unknown_option1, :unknown_option2],
                  keys_path: [:processors],
                  message:
                    "unknown options [:unknown_option1, :unknown_option2], valid options are: [:stages, :min_demand]"
                }}
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

    test "empty default option with default values" do
      schema = [
        processors: [
          type: :keyword_list,
          default: [],
          keys: [
            stages: [default: 10]
          ]
        ]
      ]

      assert NimbleOptions.validate([], schema) == {:ok, [processors: [stages: 10]]}
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
                %ValidationError{
                  key: :stages,
                  keys_path: [:processors],
                  message: "required option :stages not found, received options: [:max_demand]"
                }}
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
                %ValidationError{
                  key: :stages,
                  value: :an_atom,
                  keys_path: [:processors],
                  message: "expected :stages to be a positive integer, got: :an_atom"
                }}
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
                %ValidationError{
                  key: [:unknown_option],
                  keys_path: [:producers, :producer1],
                  message: "unknown options [:unknown_option], valid options are: [:module, :arg]"
                }}
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
                %ValidationError{
                  key: :arg,
                  keys_path: [:producers, :default],
                  message: "required option :arg not found, received options: [:module]"
                }}
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
                %ValidationError{
                  key: :stages,
                  value: :an_atom,
                  keys_path: [:producers, :producer1],
                  message: "expected :stages to be a positive integer, got: :an_atom"
                }}
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
               {:error,
                %ValidationError{
                  key: :producers,
                  value: [],
                  message: "expected :producers to be a non-empty keyword list, got: []"
                }}
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
                %ValidationError{
                  key: :path,
                  value: :not_a_string,
                  keys_path: [:socket_options, :certificates],
                  message: "expected :path to be a string, got: :not_a_string"
                }}
    end
  end

  describe "NimbleOptions.docs/1" do
    test "override docs for recursive keys" do
      docs = """
        * `:type` - Required. The type of the option item.

        * `:required` - Defines if the option item is required. The default value is `false`.

        * `:keys` - Defines which set of keys are accepted.

        * `:default` - The default.

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
        ],
        other_key: [type: :string]
      ]

      docs = """
        * `:producer` - The producer. Supported options:

          * `:module` - The module.

          * `:rate_limiting` - A list of options to enable and configure rate limiting. Supported options:

            * `:allowed_messages` - Number of messages per interval.

            * `:interval` - Required. The interval.

        * `:other_key`

      """

      assert NimbleOptions.docs(schema) == docs
      assert NimbleOptions.docs(NimbleOptions.new!(schema)) == docs
    end

    test "passing specific indentation" do
      nested_schema = [
        allowed_messages: [type: :pos_integer, doc: "Allowed messages."],
        interval: [type: :pos_integer, doc: "Interval."]
      ]

      schema = [
        producer: [
          type: {:or, [:string, keyword_list: nested_schema]},
          doc: """
          The producer. Either a string or a keyword list with the following keys:

          #{NimbleOptions.docs(nested_schema, nest_level: 1)}
          """
        ],
        other_key: [type: :string]
      ]

      docs = """
        * `:producer` - The producer. Either a string or a keyword list with the following keys:

          * `:allowed_messages` - Allowed messages.

          * `:interval` - Interval.

        * `:other_key`

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
        ],
        other_key: [type: :string]
      ]

      docs = """
        * `:name` - Required. The name.

        * `:producer` - This is the producer summary. See "Producers options" section below.

        * `:other_key`

      ### Producers options

      The producer options allow users to set up the producer.

      The available options are:

        * `:module` - The module.

        * `:concurrency` - The concurrency.

      """

      assert NimbleOptions.docs(schema) == docs
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
        * `:name` - The name.

      This a multiline text.

      Another line.

        * `:module` - The module.

      """

      assert NimbleOptions.docs(schema) == docs
    end

    test "the option doesn't appear in the documentation when the :doc option is false" do
      schema = [
        name: [type: :atom, doc: "An atom."],
        secret: [type: :string, doc: false],
        count: [type: :integer]
      ]

      docs = """
        * `:name` - An atom.

        * `:count`

      """

      assert NimbleOptions.docs(schema) == docs
    end

    test "the option and its children don't appear in the documentation when the :doc option is false" do
      schema = [
        producer: [
          type: :keyword_list,
          doc: false,
          keys: [
            name: [type: :atom],
            concurrency: [type: :pos_integer]
          ]
        ]
      ]

      docs = """
      """

      assert NimbleOptions.docs(schema) == docs
    end

    test "stop generating docs recursively if type has no :keys" do
      schema = [
        custom_keys: [
          type: :keyword_list,
          doc: "Custom keys",
          keys: [*: [type: :atom, doc: "Won't be there!"]]
        ]
      ]

      opts = [custom_keys: [key1: :a, key2: :b]]

      assert {:ok, ^opts} = NimbleOptions.validate(opts, schema)

      assert NimbleOptions.docs(schema) == """
               * `:custom_keys` - Custom keys

             """
    end
  end

  describe "validate!/2 (raising version)" do
    test "returns the direct options if the options are valid" do
      schema = [name: [], context: []]
      opts = [name: MyProducer, context: :ok]

      assert NimbleOptions.validate!(opts, schema) == opts
    end

    test "raises a NimbleOptions.ValidationError if the options are invalid" do
      schema = [an_option: [], other_option: []]
      opts = [an_option: 1, not_an_option1: 1, not_an_option2: 1]

      message =
        "unknown options [:not_an_option1, :not_an_option2], valid options are: [:an_option, :other_option]"

      assert_raise NimbleOptions.ValidationError, message, fn ->
        NimbleOptions.validate!(opts, schema)
      end
    end
  end

  @compile_time_wrapper NimbleOptions.new!(an_option: [])

  describe "wrapper struct" do
    test "can be built from a valid schema" do
      valid_schema = [an_option: [], other_option: []]
      assert %NimbleOptions{} = NimbleOptions.new!(valid_schema)

      invalid_schema = [:atom]

      assert_raise FunctionClauseError, fn ->
        NimbleOptions.new!(invalid_schema)
      end
    end

    test "will not be validated once built" do
      invalid_schema = [{"a_binary_key", []}]
      invalid_struct = %NimbleOptions{schema: invalid_schema}

      assert catch_error(NimbleOptions.validate([], invalid_struct))
    end

    test "can be built at compile time" do
      assert {:ok, _} = NimbleOptions.validate([an_option: 1], @compile_time_wrapper)
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

  def string_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _other -> {:error, "expected string to be convertable to integer"}
    end
  end

  def string_to_integer(other) do
    {:error, "expected to be a string, got: #{inspect(other)}"}
  end

  def misbehaving_custom_validator(_value) do
    :ok
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
          keys: [
            type: :keyword_list,
            doc: "Defines which set of keys are accepted.",
            keys: &recursive_schema/0
          ],
          default: [
            doc: "The default."
          ]
        ]
      ]
    ]
  end
end
