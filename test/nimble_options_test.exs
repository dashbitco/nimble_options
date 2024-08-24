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
      invalid NimbleOptions schema. \
      Reason: invalid value for :type option: unknown type :foo.

      Available types: :any, :keyword_list, :non_empty_keyword_list, :map, :atom, \
      :integer, :non_neg_integer, :pos_integer, :float, :mfa, :mod_arg, :string, :boolean, :timeout, \
      :pid, :reference, nil, {:fun, arity}, {:in, choices}, {:or, subtypes}, {:custom, mod, fun, args}, \
      {:list, subtype}, {:tuple, list_of_subtypes}, {:map, key_type, value_type}, {:struct, struct_name} \
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
      invalid NimbleOptions schema. \
      Reason: \
      unknown options [:unknown_schema_option], \
      valid options are: [:type, :required, :default, :keys, \
      :deprecated, :doc, :subsection, :type_doc, :type_spec, :redact] \
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
                 message: "invalid value for :stages option: expected integer, got: \"10\"",
                 value: "10"
               }
             }
    end

    test "is not treated as values of received options when showing validation error" do
      # It is intentional to define options with default values at the beginning of the list.
      # Don't change the order of them.
      schema = [age: [type: :non_neg_integer, default: 10], name: [type: :string, required: true]]

      assert NimbleOptions.validate([], schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :name,
                 keys_path: [],
                 message: "required :name option not found, received options: []",
                 value: nil
               }
             }
    end

    test "is redacted" do
      schema = [
        processors: [
          type: :keyword_list,
          default: [],
          keys: [
            stages: [
              type: :integer,
              default: "10",
              redact: true
            ]
          ]
        ]
      ]

      opts = [processors: []]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :stages,
                 keys_path: [:processors],
                 message: "invalid value for :stages option: expected integer",
                 value: "10",
                 redact: true
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
                    "required :name option not found, received options: [:an_option, :other_option]"
                }}
    end
  end

  describe ":doc" do
    test "valid documentation for key" do
      # schema = [context: [doc: "details", default: 1]]
      # assert NimbleOptions.validate([], schema) == {:ok, [context: 1]}
      schema = [context: [doc: false, default: 1]]
      assert NimbleOptions.validate([], schema) == {:ok, [context: 1]}
    end

    test "invalid documentation for key" do
      message = """
      invalid NimbleOptions schema. Reason: expected :doc option to match at least \
      one given type, but didn't match any. Here are the reasons why it didn't match each of the \
      allowed types:

        * invalid value for :doc option: expected one of [false], got: 1
        * invalid value for :doc option: expected string, got: 1 (in options [:context])\
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
             end) =~ ":context option is deprecated. Use something else"
    end

    test "does not warn when not given" do
      schema = [context: [deprecated: "Use something else"]]
      assert NimbleOptions.validate([], schema) == {:ok, []}
    end

    test "warns when using default" do
      schema = [context: [deprecated: "Use something else", default: :ok]]

      assert capture_io(:stderr, fn ->
               assert NimbleOptions.validate([], schema) == {:ok, [context: :ok]}
             end) =~ ":context option is deprecated. Use something else"
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
                  message: "invalid value for :stages option: expected positive integer, got: 0"
                }}

      assert NimbleOptions.validate([stages: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :stages,
                  value: :an_atom,
                  message:
                    "invalid value for :stages option: expected positive integer, got: :an_atom"
                }}
    end

    test "redacted invalid positive integer" do
      schema = [stages: [type: :pos_integer, redact: true]]

      assert NimbleOptions.validate([stages: 0], schema) ==
               {:error,
                %ValidationError{
                  key: :stages,
                  value: 0,
                  message: "invalid value for :stages option: expected positive integer",
                  redact: true
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
                  message: "invalid value for :min_demand option: expected integer, got: 1.5"
                }}

      assert NimbleOptions.validate([min_demand: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :min_demand,
                  value: :an_atom,
                  message: "invalid value for :min_demand option: expected integer, got: :an_atom"
                }}
    end

    test "redacted invalid integer" do
      schema = [min_demand: [type: :integer, redact: true]]

      assert NimbleOptions.validate([min_demand: 1.5], schema) ==
               {:error,
                %ValidationError{
                  key: :min_demand,
                  value: 1.5,
                  message: "invalid value for :min_demand option: expected integer",
                  redact: true
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
                  message:
                    "invalid value for :min_demand option: expected non negative integer, got: -1"
                }}

      assert NimbleOptions.validate([min_demand: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :min_demand,
                  value: :an_atom,
                  message:
                    "invalid value for :min_demand option: expected non negative integer, got: :an_atom"
                }}
    end

    test "redacted invalid non negative integer" do
      schema = [min_demand: [type: :non_neg_integer, redact: true]]

      assert NimbleOptions.validate([min_demand: -1], schema) ==
               {:error,
                %ValidationError{
                  key: :min_demand,
                  value: -1,
                  message: "invalid value for :min_demand option: expected non negative integer",
                  redact: true
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
                  message: "invalid value for :certainty option: expected float, got: 1"
                }}

      assert NimbleOptions.validate([certainty: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :certainty,
                  value: :an_atom,
                  message: "invalid value for :certainty option: expected float, got: :an_atom"
                }}
    end

    test "redacted invalid float" do
      schema = [certainty: [type: :float, redact: true]]

      assert NimbleOptions.validate([certainty: 1], schema) ==
               {:error,
                %ValidationError{
                  key: :certainty,
                  value: 1,
                  message: "invalid value for :certainty option: expected float",
                  redact: true
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
                  message: "invalid value for :name option: expected atom, got: 1"
                }}
    end

    test "redacted invalid atom" do
      schema = [name: [type: :atom, redact: true]]

      assert NimbleOptions.validate([name: 1], schema) ==
               {:error,
                %ValidationError{
                  key: :name,
                  value: 1,
                  message: "invalid value for :name option: expected atom",
                  redact: true
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
                  message: "invalid value for :doc option: expected string, got: :an_atom"
                }}
    end

    test "redacted invalid string" do
      schema = [doc: [type: :string]]

      assert NimbleOptions.validate([doc: :an_atom], schema) ==
               {:error,
                %ValidationError{
                  key: :doc,
                  value: :an_atom,
                  message: "invalid value for :doc option: expected string, got: :an_atom"
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
                  message: "invalid value for :required option: expected boolean, got: :an_atom"
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
                  message:
                    "invalid value for :timeout option: expected non-negative integer or :infinity, got: -1"
                }}

      opts = [timeout: :invalid]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :timeout,
                  value: :invalid,
                  message:
                    "invalid value for :timeout option: expected non-negative integer or :infinity, got: :invalid"
                }}
    end

    test "redact invalid timeout" do
      schema = [timeout: [type: :timeout, redact: true]]

      opts = [timeout: -1]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :timeout,
                  value: -1,
                  message:
                    "invalid value for :timeout option: expected non-negative integer or :infinity",
                  redact: true
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
                  message: "invalid value for :name option: expected pid, got: 1"
                }}
    end

    test "redacted invalid pid" do
      schema = [name: [type: :pid, redact: true]]

      assert NimbleOptions.validate([name: 1], schema) ==
               {:error,
                %ValidationError{
                  key: :name,
                  value: 1,
                  message: "invalid value for :name option: expected pid",
                  redact: true
                }}
    end

    test "valid reference" do
      schema = [name: [type: :reference]]
      opts = [name: make_ref()]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid reference" do
      schema = [name: [type: :reference]]

      assert NimbleOptions.validate([name: 1], schema) ==
               {:error,
                %ValidationError{
                  key: :name,
                  value: 1,
                  message: "invalid value for :name option: expected reference, got: 1"
                }}
    end

    test "redacted invalid reference" do
      schema = [name: [type: :reference, redact: true]]

      assert NimbleOptions.validate([name: 1], schema) ==
               {:error,
                %ValidationError{
                  key: :name,
                  value: 1,
                  message: "invalid value for :name option: expected reference",
                  redact: true
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
                   "invalid value for :transformer option: expected tuple {mod, fun, args}, got: {\"not_a_module\", :func, []}"
               }
             }

      opts = [transformer: {SomeMod, "not_a_func", []}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :transformer,
                 value: {SomeMod, "not_a_func", []},
                 message:
                   "invalid value for :transformer option: expected tuple {mod, fun, args}, got: {SomeMod, \"not_a_func\", []}"
               }
             }

      opts = [transformer: {SomeMod, :func, "not_a_list"}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :transformer,
                 value: {SomeMod, :func, "not_a_list"},
                 message:
                   ~s(invalid value for :transformer option: expected tuple {mod, fun, args}, got: {SomeMod, :func, "not_a_list"})
               }
             }

      opts = [transformer: NotATuple]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :transformer,
                 value: NotATuple,
                 message:
                   ~s(invalid value for :transformer option: expected tuple {mod, fun, args}, got: NotATuple)
               }
             }
    end

    test "redacted invalid mfa" do
      schema = [transformer: [type: :mfa, redact: true]]

      opts = [transformer: {"not_a_module", :func, []}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :transformer,
                 value: {"not_a_module", :func, []},
                 message:
                   "invalid value for :transformer option: expected tuple {mod, fun, args}",
                 redact: true
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
                 message:
                   ~s(invalid value for :producer option: expected tuple {mod, arg}, got: NotATuple)
               }
             }

      opts = [producer: {"not_a_module", []}]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :producer,
                 value: {"not_a_module", []},
                 message:
                   ~s(invalid value for :producer option: expected tuple {mod, arg}, got: {"not_a_module", []})
               }
             }
    end

    test "redacted invalid mod_arg" do
      schema = [producer: [type: :mod_arg, redact: true]]

      opts = [producer: NotATuple]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :producer,
                 value: NotATuple,
                 message: ~s(invalid value for :producer option: expected tuple {mod, arg}),
                 redact: true
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
                 message:
                   ~s(invalid value for :partition_by option: expected function of arity 1, got: :not_a_fun)
               }
             }

      opts = [partition_by: fn x, y -> x * y end]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :partition_by,
                 value: opts[:partition_by],
                 message:
                   ~s(invalid value for :partition_by option: expected function of arity 1, got: function of arity 2)
               }
             }
    end

    test "redacted invalid {:fun, arity}" do
      schema = [partition_by: [type: {:fun, 1}, redact: true]]

      opts = [partition_by: :not_a_fun]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :partition_by,
                 value: :not_a_fun,
                 message:
                   ~s(invalid value for :partition_by option: expected function of arity 1),
                 redact: true
               }
             }

      opts = [partition_by: fn x, y -> x * y end]

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %ValidationError{
                 key: :partition_by,
                 value: opts[:partition_by],
                 message:
                   ~s(invalid value for :partition_by option: expected function of arity 1),
                 redact: true
               }
             }
    end

    test "valid nil" do
      schema = [name: [type: nil, required: true]]
      opts = [name: nil]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid nil" do
      schema = [name: [type: nil, required: true]]
      opts = [name: :not_nil]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :name,
                  value: :not_nil,
                  message: "invalid value for :name option: expected nil, got: :not_nil"
                }}
    end

    test "redacted invalid nil" do
      schema = [name: [type: nil, required: true, redact: true]]
      opts = [name: :not_nil]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :name,
                  value: :not_nil,
                  message: "invalid value for :name option: expected nil",
                  redact: true
                }}
    end

    test "valid {:in, choices}" do
      schema = [batch_mode: [type: {:in, [:flush, :bulk]}]]

      opts = [batch_mode: :flush]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [batch_mode: :bulk]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      # With ranges
      schema = [decimals: [type: {:in, 0..255}]]

      opts = [decimals: 0]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [decimals: 100]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      # With sets
      schema = [mode: [type: {:in, MapSet.new([:active, :passive])}]]

      opts = [mode: :active]
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
                  message:
                    "invalid value for :batch_mode option: expected one of [:flush, :bulk], got: :invalid"
                }}

      # With ranges
      schema = [decimals: [type: {:in, 0..255}]]

      opts = [decimals: -1]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :decimals,
                  value: -1,
                  message: "invalid value for :decimals option: expected one of 0..255, got: -1"
                }}

      # With sets
      schema = [mode: [type: {:in, MapSet.new([:active, :passive])}]]

      opts = [mode: :unknown]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :mode,
                  value: :unknown,
                  message:
                    "invalid value for :mode option: expected one of #{inspect(MapSet.new([:active, :passive]))}, got: :unknown"
                }}
    end

    test "redact invalid {:in, choices}" do
      schema = [batch_mode: [type: {:in, [:flush, :bulk]}, redact: true]]

      opts = [batch_mode: :invalid]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :batch_mode,
                  value: :invalid,
                  message:
                    "invalid value for :batch_mode option: expected one of [:flush, :bulk]",
                  redact: true
                }}
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

    test "valid {:or, subtypes} with nested map" do
      schema = [
        docs: [
          type: {:or, [:boolean, map: [enabled: [type: :boolean]]]}
        ]
      ]

      opts = [docs: false]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [docs: %{enabled: true}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid {:or, subtypes}" do
      schema = [docs: [type: {:or, [:string, :boolean]}]]

      opts = [docs: :invalid]

      expected_message = """
      expected :docs option to match at least one given type, but didn't match any. Here are the \
      reasons why it didn't match each of the allowed types:

        * invalid value for :docs option: expected boolean, got: :invalid
        * invalid value for :docs option: expected string, got: :invalid\
      """

      assert NimbleOptions.validate(opts, schema) ==
               {:error, %ValidationError{key: :docs, value: :invalid, message: expected_message}}
    end

    test "redacted invalid {:or, subtypes}" do
      schema = [docs: [type: {:or, [:string, :boolean]}, redact: true]]

      opts = [docs: :invalid]

      expected_message = """
      expected :docs option to match at least one given type, but didn't match any. Here are the \
      reasons why it didn't match each of the allowed types:

        * invalid value for :docs option: expected boolean
        * invalid value for :docs option: expected string\
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
      expected :docs option to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * expected :docs option to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * invalid value for :docs option: expected string, got: 1
        * expected :docs option to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * invalid value for :docs option: expected boolean, got: 1
        * invalid value for :docs option: expected to be a string, got: 1\
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
      expected :docs option to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * invalid value for :docs option: expected keyword list, got: "123"
        * invalid value for :docs option: expected boolean, got: "123"\
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
      expected :docs option to match at least one given type, but didn't match any. \
      Here are the reasons why it didn't match each of the allowed types:

        * invalid value for :enabled option: expected boolean, got: "not a boolean" (in options [:docs])
        * invalid value for :docs option: expected boolean, got: [enabled: "not a boolean"]\
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
                 message:
                   "invalid value for :buffer_keep option: expected :first or :last, got: :unknown"
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
                 message:
                   "invalid value for :buffer_keep option: expected one of [:first, :last], got: :unknown"
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
                  message:
                    "invalid value for :metadata option: expected list, got: \"not a list\"",
                  value: "not a list"
                }}

      # List with invalid elements
      opts = [metadata: [:foo, :bar, "baz", :bong, "another invalid value"]]

      message = """
      invalid list in :metadata option: \
      invalid value for list element at position 2: \
      expected atom, got: \"baz\"\
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
      invalid list in :metadata option: \
      invalid list in list element at position 1: \
      invalid value for list element at position 0: \
      expected atom, got: \"baz\"\
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

    test "redacted invalid {:list, subtype}" do
      schema = [metadata: [type: {:list, :atom}, redact: true]]

      # Not a list
      opts = [metadata: "not a list"]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :metadata,
                  keys_path: [],
                  message: "invalid value for :metadata option: expected list",
                  value: "not a list",
                  redact: true
                }}

      # List with invalid elements
      opts = [metadata: [:foo, :bar, "baz", :bong, "another invalid value"]]

      message = """
      invalid list in :metadata option: \
      invalid value for list element at position 2: \
      expected atom\
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
      schema = [metadata: [type: {:list, {:list, :atom}}, redact: true]]
      opts = [metadata: [[:foo, :bar], ["baz", :bong, "another invalid value"]]]

      message = """
      invalid list in :metadata option: \
      invalid list in list element at position 1: \
      invalid value for list element at position 0: \
      expected atom\
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
      invalid list in :metadata option: \
      invalid value for list element at position 1: \
      expected string to be convertible to integer\
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

    for subtype <- [:keyword_list, :non_empty_keyword_list] do
      test "{:list, subtype} with a #{inspect(subtype)} subtype" do
        type = {:custom, __MODULE__, :string_to_integer, []}
        schema = [opts_list: [type: {:list, {unquote(subtype), str: [type: type]}}]]

        # Valid
        opts = [opts_list: [[str: "1"], [str: "2"]]]

        assert NimbleOptions.validate(opts, schema) ==
                 {:ok, [opts_list: [[str: 1], [str: 2]]]}

        # Invalid
        opts = [opts_list: [[str: "123"], [str: "not an int"]]]

        message = """
        invalid list element at position 1 in :opts_list option: \
        invalid value for :str option: \
        expected string to be convertible to integer\
        """

        assert NimbleOptions.validate(opts, schema) == {
                 :error,
                 %NimbleOptions.ValidationError{
                   key: :opts_list,
                   keys_path: [],
                   message: message,
                   value: [[str: "123"], [str: "not an int"]]
                 }
               }
      end
    end

    test "{:list, subtype} with a :map subtype" do
      type = {:custom, __MODULE__, :string_to_integer, []}
      schema = [map_list: [type: {:list, {:map, str: [type: type]}}]]

      valid_opts = [map_list: [%{str: "1"}, %{str: "2"}]]

      assert NimbleOptions.validate(valid_opts, schema) ==
               {:ok, [map_list: [%{str: 1}, %{str: 2}]]}

      invalid_opts = [map_list: [%{str: "123"}, %{str: "not an int"}]]

      message = """
      invalid list element at position 1 in :map_list option: \
      invalid value for :str option: expected string to be convertible to integer\
      """

      assert NimbleOptions.validate(invalid_opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :map_list,
                 keys_path: [],
                 message: message,
                 value: [%{str: "123"}, %{str: "not an int"}]
               }
             }
    end

    test "valid {:tuple, tuple_def}" do
      schema = [result: [type: {:tuple, [{:in, [:ok, :error]}, :string]}]]

      opts = [result: {:ok, "it worked"}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [result: {:error, "it did not work"}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid {:tuple, tuple_def}" do
      schema = [result: [type: {:tuple, [{:in, [:ok, :error]}, :string]}]]

      # Not a tuple
      opts = [result: "not a tuple"]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :result,
                  keys_path: [],
                  message:
                    "invalid value for :result option: expected tuple, got: \"not a tuple\"",
                  value: "not a tuple"
                }}

      # List with invalid elements
      opts = [result: {:ok, :not_a_string}]

      message = """
      invalid tuple in :result option: \
      invalid value for tuple element at position 1: \
      expected string, got: :not_a_string\
      """

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :result,
                 keys_path: [],
                 message: message,
                 value: {:ok, :not_a_string}
               }
             }

      # Nested list with invalid elements
      schema = [tup: [type: {:tuple, [{:tuple, [:string, :string]}, :integer]}]]
      opts = [tup: {{"string", :not_a_string}, 1}]

      message = """
      invalid tuple in :tup option: \
      invalid tuple in tuple element at position 0: \
      invalid value for tuple element at position 1: \
      expected string, got: :not_a_string\
      """

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :tup,
                 keys_path: [],
                 message: message,
                 value: {{"string", :not_a_string}, 1}
               }
             }
    end

    test "redacted invalid {:tuple, tuple_def}" do
      schema = [result: [type: {:tuple, [{:in, [:ok, :error]}, :string]}, redact: true]]

      # Not a tuple
      opts = [result: "not a tuple"]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %ValidationError{
                  key: :result,
                  keys_path: [],
                  message: "invalid value for :result option: expected tuple",
                  value: "not a tuple",
                  redact: true
                }}

      # List with invalid elements
      opts = [result: {:ok, :not_a_string}]

      message = """
      invalid tuple in :result option: \
      invalid value for tuple element at position 1: \
      expected string\
      """

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :result,
                 keys_path: [],
                 message: message,
                 value: {:ok, :not_a_string}
               }
             }

      # Nested list with invalid elements
      schema = [tup: [type: {:tuple, [{:tuple, [:string, :string]}, :integer]}, redact: true]]
      opts = [tup: {{"string", :not_a_string}, 1}]

      message = """
      invalid tuple in :tup option: \
      invalid tuple in tuple element at position 0: \
      invalid value for tuple element at position 1: \
      expected string\
      """

      assert NimbleOptions.validate(opts, schema) == {
               :error,
               %NimbleOptions.ValidationError{
                 key: :tup,
                 keys_path: [],
                 message: message,
                 value: {{"string", :not_a_string}, 1}
               }
             }
    end

    test "valid :map" do
      schema = [map: [type: :map]]

      opts = [map: %{}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [map: %{atom_key: :value}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      schema = [map: [type: :map, keys: [key: [type: :string]]]]

      opts = [map: %{}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [map: %{key: "string"}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid :map" do
      schema = [map: [type: :map]]

      opts = [map: "not a map"]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message: "invalid value for :map option: expected map, got: \"not a map\"",
                  value: "not a map"
                }}

      opts = [map: %{"string key" => :value}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message:
                    "invalid map in :map option: invalid value for map key: expected atom, got: \"string key\"",
                  value: %{"string key" => :value}
                }}

      schema = [map: [type: :map, keys: [key: [type: :string]]]]

      opts = [map: %{key: :atom_value}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :key,
                  keys_path: [:map],
                  message: "invalid value for :key option: expected string, got: :atom_value",
                  value: :atom_value
                }}

      opts = [map: %{unknown_key: "string"}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  __exception__: true,
                  key: [:unknown_key],
                  keys_path: [:map],
                  message: "unknown options [:unknown_key], valid options are: [:key]",
                  value: nil
                }}
    end

    test "redacted invalid map" do
      schema = [map: [type: :map, redact: true]]

      opts = [map: "not a map"]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message: "invalid value for :map option: expected map",
                  value: "not a map",
                  redact: true
                }}

      schema = [map: [type: :map, keys: [key: [type: :string, redact: true]]]]

      opts = [map: %{key: :atom_value}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :key,
                  keys_path: [:map],
                  message: "invalid value for :key option: expected string",
                  value: :atom_value,
                  redact: true
                }}
    end

    test "valid {:map, key_type, value_type}" do
      schema = [map: [type: {:map, :string, :string}]]

      opts = [map: %{"valid_key" => "valid_value", "other_key" => "other_value"}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      opts = [map: %{}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      schema = [map: [type: {:map, {:in, [:a, :b, :c]}, {:list, :integer}}]]

      opts = [map: %{a: [1, 2, 3], c: [4, 5, 6]}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}

      schema = [map: [type: {:map, :any, :any}]]

      opts = [map: %{%{map: :key} => {:and, :map, :value}}]
      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "invalid {:map, key_type, value_type}" do
      schema = [map: [type: {:map, :string, :string}]]

      opts = [map: %{:invalid_key => "valid_value", :other_invalid_key => "other_value"}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message:
                    "invalid map in :map option: invalid value for map key: expected string, got: :invalid_key",
                  value: %{invalid_key: "valid_value", other_invalid_key: "other_value"}
                }}

      opts = [map: %{"valid_key" => :invalid_value, "other_key" => :other_invalid_value}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message:
                    "invalid map in :map option: invalid value for map key \"other_key\": expected string, got: :other_invalid_value",
                  value: %{"other_key" => :other_invalid_value, "valid_key" => :invalid_value}
                }}

      schema = [map: [type: {:map, {:in, [:a, :b, :c]}, {:list, :integer}}]]

      opts = [map: %{invalid_key: [1, 2, 3], c: [4, 5, 6]}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message:
                    "invalid map in :map option: invalid value for map key: expected one of [:a, :b, :c], got: :invalid_key",
                  value: %{c: [4, 5, 6], invalid_key: [1, 2, 3]}
                }}
    end

    test "redacted invalid {:map, key_type, value_type}" do
      schema = [map: [type: {:map, :string, :string}, redact: true]]

      opts = [map: %{:invalid_key => "valid_value", :other_invalid_key => "other_value"}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message:
                    "invalid map in :map option: invalid value for map key: expected string, got: :invalid_key",
                  value: %{invalid_key: "valid_value", other_invalid_key: "other_value"}
                }}

      opts = [map: %{"valid_key" => :invalid_value, "other_key" => :other_invalid_value}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message:
                    "invalid map in :map option: invalid value for map key \"other_key\": expected string",
                  value: %{"other_key" => :other_invalid_value, "valid_key" => :invalid_value}
                }}

      schema = [map: [type: {:map, {:in, [:a, :b, :c]}, {:list, :integer}}, redact: true]]

      opts = [map: %{a: "not a list"}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message:
                    "invalid map in :map option: invalid value for map key :a: expected list",
                  value: %{a: "not a list"}
                }}

      opts = [map: %{a: ["not an integer"]}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :map,
                  keys_path: [],
                  message:
                    "invalid map in :map option: invalid list in map key :a: invalid value for list element at position 0: expected integer",
                  value: %{a: ["not an integer"]}
                }}
    end

    test "valid {:struct, struct_name}" do
      schema = [struct: [type: {:struct, URI}]]

      opts = [struct: %URI{}]

      assert NimbleOptions.validate(opts, schema) == {:ok, opts}
    end

    test "non-matching {:struct, struct_name}" do
      schema = [struct: [type: {:struct, URI}]]

      opts = [struct: %NimbleOptions{}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :struct,
                  keys_path: [],
                  message:
                    "invalid value for :struct option: expected URI, got: %NimbleOptions{schema: []}",
                  value: %NimbleOptions{schema: []}
                }}
    end

    test "invalid {:struct, struct_name}" do
      schema = [struct: [type: {:struct, "123"}]]

      opts = [struct: %URI{}]

      assert_raise(
        ArgumentError,
        "invalid NimbleOptions schema. Reason: invalid value for :type option: invalid struct_name for :struct, expected atom, got \"123\" (in options [:struct])",
        fn ->
          NimbleOptions.validate(opts, schema)
        end
      )
    end

    test "redacted invalid {:struct, struct_name}" do
      schema = [struct: [type: {:struct, URI}, redact: true]]

      opts = [struct: %NimbleOptions{}]

      assert NimbleOptions.validate(opts, schema) ==
               {:error,
                %NimbleOptions.ValidationError{
                  key: :struct,
                  keys_path: [],
                  message: "invalid value for :struct option: expected URI",
                  value: %NimbleOptions{schema: []},
                  redact: true
                }}
    end
  end

  describe "nested options with predefined keys" do
    for type <- [:keyword_list, :map] do
      test "known options for #{type}" do
        schema = [
          processors: [
            type: unquote(type),
            keys: [
              stages: [],
              max_demand: []
            ]
          ]
        ]

        processors = opts_to_type(unquote(type), stages: 1, max_demand: 2)
        opts = [processors: processors]
        assert NimbleOptions.validate(opts, schema) == {:ok, opts}
      end
    end

    for type <- [:keyword_list, :map] do
      test "unknown options for #{type}" do
        schema = [
          processors: [
            type: unquote(type),
            keys: [
              stages: [],
              min_demand: []
            ]
          ]
        ]

        processors =
          opts_to_type(unquote(type), stages: 1, unknown_option1: 1, unknown_option2: 1)

        opts = [processors: processors]

        assert NimbleOptions.validate(opts, schema) ==
                 {:error,
                  %ValidationError{
                    key: [:unknown_option1, :unknown_option2],
                    keys_path: [:processors],
                    message:
                      "unknown options [:unknown_option1, :unknown_option2], valid options are: [:stages, :min_demand]"
                  }}
      end
    end

    for type <- [:keyword_list, :map] do
      test "options with default values for #{type}" do
        schema = [
          processors: [
            type: unquote(type),
            keys: [
              stages: [default: 10]
            ]
          ]
        ]

        processors = opts_to_type(unquote(type), [])
        opts = [processors: processors]

        assert NimbleOptions.validate(opts, schema) ==
                 {:ok, [processors: opts_to_type(unquote(type), stages: 10)]}
      end
    end

    for type <- [:keyword_list, :map] do
      test "empty default option with default values for #{type}" do
        schema = [
          processors: [
            type: unquote(type),
            default: opts_to_type(unquote(type), []),
            keys: [
              stages: [default: 10]
            ]
          ]
        ]

        processors = opts_to_type(unquote(type), stages: 10)
        assert NimbleOptions.validate([], schema) == {:ok, [processors: processors]}
      end
    end

    for type <- [:keyword_list, :map] do
      test "all required options present for type #{type}" do
        schema = [
          processors: [
            type: unquote(type),
            keys: [
              stages: [required: true],
              max_demand: [required: true]
            ]
          ]
        ]

        processors = opts_to_type(unquote(type), stages: 1, max_demand: 2)
        opts = [processors: processors]

        assert NimbleOptions.validate(opts, schema) == {:ok, opts}
      end
    end

    for type <- [:keyword_list, :map] do
      test "required options missing for #{type}" do
        schema = [
          processors: [
            type: unquote(type),
            keys: [
              stages: [required: true],
              max_demand: [required: true]
            ]
          ]
        ]

        processors = opts_to_type(unquote(type), max_demand: 1)
        opts = [processors: processors]

        assert NimbleOptions.validate(opts, schema) ==
                 {:error,
                  %ValidationError{
                    key: :stages,
                    keys_path: [:processors],
                    message: "required :stages option not found, received options: [:max_demand]"
                  }}
      end
    end

    for type <- [:keyword_list, :map] do
      test "nested options types for #{type}" do
        schema = [
          processors: [
            type: unquote(type),
            keys: [
              name: [type: :atom],
              stages: [type: :pos_integer]
            ]
          ]
        ]

        processors = opts_to_type(unquote(type), name: MyModule, stages: :an_atom)
        opts = [processors: processors]

        assert NimbleOptions.validate(opts, schema) ==
                 {:error,
                  %ValidationError{
                    key: :stages,
                    value: :an_atom,
                    keys_path: [:processors],
                    message:
                      "invalid value for :stages option: expected positive integer, got: :an_atom"
                  }}
      end
    end
  end

  describe "nested options with custom keys" do
    for type <- [:keyword_list, :map] do
      test "known options for #{type}" do
        schema = [
          producers: [
            type: unquote(type),
            keys: [
              *: [
                type: unquote(type),
                keys: [
                  module: [],
                  arg: [type: :atom]
                ]
              ]
            ]
          ]
        ]

        producer1 = opts_to_type(unquote(type), module: MyModule, arg: :atom)
        producers = opts_to_type(unquote(type), producer1: producer1)
        opts = [producers: producers]

        assert NimbleOptions.validate(opts, schema) == {:ok, opts}
      end
    end

    for type <- [:keyword_list, :map] do
      test "unknown options for #{type}" do
        schema = [
          producers: [
            type: unquote(type),
            keys: [
              *: [
                type: unquote(type),
                keys: [
                  module: [],
                  arg: []
                ]
              ]
            ]
          ]
        ]

        producer1 = opts_to_type(unquote(type), module: MyModule, arg: :ok, unknown_option: 1)
        producers = opts_to_type(unquote(type), producer1: producer1)
        opts = [producers: producers]

        assert NimbleOptions.validate(opts, schema) ==
                 {:error,
                  %ValidationError{
                    key: [:unknown_option],
                    keys_path: [:producers, :producer1],
                    message:
                      "unknown options [:unknown_option], valid options are: [:module, :arg]"
                  }}
      end
    end

    for type <- [:keyword_list, :map] do
      test "options with default values for #{type}" do
        schema = [
          producers: [
            type: unquote(type),
            keys: [
              *: [
                type: unquote(type),
                keys: [
                  arg: [default: :ok]
                ]
              ]
            ]
          ]
        ]

        producer1 = opts_to_type(unquote(type), [])
        producers = opts_to_type(unquote(type), producer1: producer1)
        opts = [producers: producers]

        {:ok, [producers: validated_producers]} = NimbleOptions.validate(opts, schema)
        assert :ok == get_in(validated_producers, [:producer1, :arg])
      end
    end

    for type <- [:keyword_list, :map] do
      test "all required options present for #{type}" do
        schema = [
          producers: [
            type: unquote(type),
            keys: [
              *: [
                type: unquote(type),
                keys: [
                  module: [required: true],
                  arg: [required: true]
                ]
              ]
            ]
          ]
        ]

        default = opts_to_type(unquote(type), module: MyModule, arg: :ok)
        producers = opts_to_type(unquote(type), default: default)
        opts = [producers: producers]

        assert NimbleOptions.validate(opts, schema) == {:ok, opts}
      end
    end

    for type <- [:keyword_list, :map] do
      test "required options missing for #{type}" do
        schema = [
          producers: [
            type: unquote(type),
            keys: [
              *: [
                type: unquote(type),
                keys: [
                  module: [required: true],
                  arg: [required: true]
                ]
              ]
            ]
          ]
        ]

        default = opts_to_type(unquote(type), module: MyModule)
        producers = opts_to_type(unquote(type), default: default)
        opts = [producers: producers]

        assert NimbleOptions.validate(opts, schema) ==
                 {:error,
                  %ValidationError{
                    key: :arg,
                    keys_path: [:producers, :default],
                    message: "required :arg option not found, received options: [:module]"
                  }}
      end
    end

    for type <- [:keyword_list, :map] do
      test "nested options types for #{type}" do
        schema = [
          producers: [
            type: unquote(type),
            keys: [
              *: [
                type: unquote(type),
                keys: [
                  module: [required: true, type: :atom],
                  stages: [type: :pos_integer]
                ]
              ]
            ]
          ]
        ]

        producer1 = opts_to_type(unquote(type), module: MyProducer, stages: :an_atom)
        producers = opts_to_type(unquote(type), producer1: producer1)
        opts = [producers: producers]

        assert NimbleOptions.validate(opts, schema) ==
                 {:error,
                  %ValidationError{
                    key: :stages,
                    value: :an_atom,
                    keys_path: [:producers, :producer1],
                    message:
                      "invalid value for :stages option: expected positive integer, got: :an_atom"
                  }}
      end
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
                  message:
                    "invalid value for :producers option: expected non-empty keyword list, got: []"
                }}
    end

    test "redact invalid :non_empty_keyword_list" do
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
          ],
          redact: true
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
                  message: "invalid value for :producers option: expected non-empty keyword list",
                  redact: true
                }}
    end

    for type <- [:keyword_list, :map] do
      test "allow empty keys for #{type}" do
        schema = [
          producers: [
            type: unquote(type),
            keys: [
              *: [
                type: unquote(type),
                keys: [
                  module: [required: true, type: :atom],
                  stages: [type: :pos_integer]
                ]
              ]
            ]
          ]
        ]

        producers = opts_to_type(unquote(type), [])
        opts = [producers: producers]

        assert NimbleOptions.validate(opts, schema) == {:ok, opts}
      end
    end

    for type <- [:keyword_list, :map] do
      test "default value for #{type}" do
        empty = opts_to_type(unquote(type), [])

        schema = [
          batchers: [
            required: false,
            default: empty,
            type: unquote(type),
            keys: [
              *: [
                type: unquote(type),
                keys: [
                  stages: [type: :pos_integer, default: 1]
                ]
              ]
            ]
          ]
        ]

        opts = []

        assert NimbleOptions.validate(opts, schema) == {:ok, [batchers: empty]}
      end
    end
  end

  describe "nested options show up in error messages" do
    for type <- [:keyword_list, :map] do
      test "for options that we validate for #{type}" do
        schema = [
          socket_options: [
            type: unquote(type),
            keys: [
              certificates: [
                type: unquote(type),
                keys: [
                  path: [type: :string]
                ]
              ]
            ]
          ]
        ]

        certificates = opts_to_type(unquote(type), path: :not_a_string)
        socket_options = opts_to_type(unquote(type), certificates: certificates)
        opts = [socket_options: socket_options]

        assert NimbleOptions.validate(opts, schema) ==
                 {:error,
                  %ValidationError{
                    key: :path,
                    value: :not_a_string,
                    keys_path: [:socket_options, :certificates],
                    message: "invalid value for :path option: expected string, got: :not_a_string"
                  }}
      end
    end
  end

  # No other test is passing in `opts` as a map, so these are just some white box tests for sanity checking
  test "can use a map for validate/2" do
    schema = []
    opts = %{}
    assert NimbleOptions.validate(opts, schema) == {:ok, %{}}

    schema = [
      name: [type: :string, required: true],
      context: [type: :atom, required: false]
    ]

    opts = %{}

    assert NimbleOptions.validate(opts, schema) ==
             {:error,
              %ValidationError{
                key: :name,
                value: nil,
                keys_path: [],
                message: "required :name option not found, received options: []"
              }}

    opts = %{name: "primary 1"}
    assert NimbleOptions.validate(opts, schema) == {:ok, %{name: "primary 1"}}
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

  describe "option_typespec/1" do
    test "joins typespec correctly" do
      schema = [
        name: [type: :atom],
        context: [type: :atom],
        stages: [type: :pos_integer]
      ]

      assert NimbleOptions.option_typespec(schema) ==
               quote(do: {:name, atom()} | {:context, atom()} | {:stages, pos_integer()})
    end

    test "all possible types" do
      cases = [
        {:any, quote(do: term())},
        {:keyword_list, quote(do: keyword())},
        {:non_empty_keyword_list, quote(do: keyword())},
        {:map, quote(do: map())},
        {{:map, :string, :integer}, quote(do: %{optional(binary()) => integer()})},
        {:atom, quote(do: atom())},
        {:integer, quote(do: integer())},
        {:non_neg_integer, quote(do: non_neg_integer())},
        {:pos_integer, quote(do: pos_integer())},
        {:float, quote(do: float())},
        {:mfa, quote(do: {module(), atom(), [term()]})},
        {:mod_arg, quote(do: {module(), [term()]})},
        {:string, quote(do: binary())},
        {:boolean, quote(do: boolean())},
        {:timeout, quote(do: timeout())},
        {:pid, quote(do: pid())},
        {:reference, quote(do: reference())},
        {{:fun, 3}, quote(do: (term(), term(), term() -> term()))},
        {{:in, MapSet.new([:a, :b, :c])}, quote(do: term())},
        {{:in, 1..10}, quote(do: 1..10)},
        {{:custom, __MODULE__, :fun, []}, quote(do: term())},
        {{:list, :integer}, quote(do: [integer()])},
        {{:list, {:list, :integer}}, quote(do: [[integer()]])},
        {{:list, {:keyword_list, []}}, quote(do: [keyword()])},
        {{:list, {:non_empty_keyword_list, []}}, quote(do: [keyword()])},
        {{:or, [:integer, :boolean, :float]}, quote(do: integer() | boolean() | float())},
        {{:or, [{:or, [:integer, :float]}, :boolean]},
         quote(do: (integer() | float()) | boolean())},
        {{:struct, URI}, quote(do: struct())},
        {{:tuple, [{:list, :integer}]}, quote(do: {[integer()]})},
        {{:tuple, [:string, :atom]}, quote(do: {binary(), atom()})}
      ]

      Enum.each(cases, fn {type, quoted_typespec} ->
        actual =
          [my_key: [type: type]]
          |> NimbleOptions.option_typespec()
          |> clean_context_meta()

        expected = clean_context_meta(quote(do: {:my_key, unquote(quoted_typespec)}))

        assert actual == expected
      end)
    end

    test "supports overriding specific specs with the :type_spec schema option" do
      schema = [
        name: [
          type: :any,
          type_spec: quote(do: atom())
        ]
      ]

      assert NimbleOptions.option_typespec(schema) ==
               quote(do: {:name, atom()})
    end

    # TODO: remove check when we depend on Elixir 1.12+
    if Version.match?(System.version(), "~> 1.12") do
      test "ranges with step" do
        schema = [
          range: [type: {:in, %Range{(1..10) | step: 2}}]
        ]

        expected =
          quote do
            {:range, term()}
          end

        assert clean_context_meta(NimbleOptions.option_typespec(schema)) ==
                 clean_context_meta(expected)
      end
    end
  end

  defp clean_context_meta(ast) do
    Macro.prewalk(ast, fn
      {_, _, _} = tuple -> Macro.update_meta(tuple, &Keyword.delete(&1, :context))
      other -> other
    end)
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
      _other -> {:error, "expected string to be convertible to integer"}
    end
  end

  def string_to_integer(other) do
    {:error, "expected to be a string, got: #{inspect(other)}"}
  end

  def misbehaving_custom_validator(_value) do
    :ok
  end

  defp opts_to_type(:keyword_list, opts), do: opts
  defp opts_to_type(:map, opts), do: Map.new(opts)
end
