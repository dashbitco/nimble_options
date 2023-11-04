defmodule NimbleOptions.DocsTest do
  use ExUnit.Case, async: true

  describe "NimbleOptions.docs/1" do
    test "override docs for recursive keys" do
      docs = """
      * `:type` (`t:atom/0`) - Required. The type of the option item.

      * `:required` (`t:boolean/0`) - Defines if the option item is required. The default value is `false`.

      * `:keys` (`t:keyword/0`) - Defines which set of keys are accepted.

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
      * `:producer` (non-empty `t:keyword/0`) - The producer. Supported options:

        * `:module` - The module.

        * `:rate_limiting` (non-empty `t:keyword/0`) - A list of options to enable and configure rate limiting. Supported options:

          * `:allowed_messages` (`t:pos_integer/0`) - Number of messages per interval.

          * `:interval` (`t:pos_integer/0`) - Required. The interval.

      * `:other_key` (`t:String.t/0`)

      """

      assert NimbleOptions.docs(schema) == docs
      assert NimbleOptions.docs(NimbleOptions.new!(schema)) == docs
    end

    test "supports paragraphs and keeps the correct indentation" do
      schema = [
        producer: [
          type: :non_empty_keyword_list,
          doc: """
          The producer.

          Which is very cool.
          """,
          keys: [
            nested: [
              type: :integer,
              doc: """
              The nestedness.

              It should be quite nested.
              """
            ]
          ]
        ]
      ]

      docs = """
      * `:producer` (non-empty `t:keyword/0`) - The producer.

        Which is very cool.

        * `:nested` (`t:integer/0`) - The nestedness.

          It should be quite nested.

      """

      assert NimbleOptions.docs(schema) == docs
      assert NimbleOptions.docs(NimbleOptions.new!(schema)) == docs
    end

    test "uses the type_doc option" do
      schema = [
        foo: [type: :string, type_doc: "`t:SomeModule.t/0`", doc: "The foo."],
        bar: [type: :string, type_doc: "`t:SomeModule.t/0`"],
        baz: [type: :integer, type_doc: false, doc: "The bar."],
        quux: [type: :integer, type_doc: false, doc: false]
      ]

      docs = """
      * `:foo` (`t:SomeModule.t/0`) - The foo.

      * `:bar` (`t:SomeModule.t/0`)

      * `:baz` - The bar.

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

          #{NimbleOptions.docs(nested_schema)}
          """
        ],
        map_with_keys: [
          type: :map,
          keys: [key_a: [type: :string, required: true], key_b: [type: {:map, :string, :integer}]]
        ],
        other_key: [type: {:list, :atom}]
      ]

      docs = """
      * `:producer` - The producer. Either a string or a keyword list with the following keys:

        * `:allowed_messages` (`t:pos_integer/0`) - Allowed messages.

        * `:interval` (`t:pos_integer/0`) - Interval.

      * `:map_with_keys` (`t:map/0`)

        * `:key_a` (`t:String.t/0`) - Required.

        * `:key_b` (map of `t:String.t/0` keys and `t:integer/0` values)

      * `:other_key` (list of `t:atom/0`)

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
      * `:name` (`t:atom/0`) - Required. The name.

      * `:producer` (non-empty `t:keyword/0`) - This is the producer summary. See "Producers options" section below.

      * `:other_key` (`t:String.t/0`)

      ### Producers options

      The producer options allow users to set up the producer.

      The available options are:

      * `:module` - The module.

      * `:concurrency` (`t:pos_integer/0`) - The concurrency.

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
          """,
          default: "HELLO"
        ],
        module: [
          type: :atom,
          doc: "The module."
        ]
      ]

      docs = """
      * `:name` (`t:String.t/0`) - The name.

        This a multiline text.

        Another line.

        The default value is `"HELLO"`.

      * `:module` (`t:atom/0`) - The module.

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
      * `:name` (`t:atom/0`) - An atom.

      * `:count` (`t:integer/0`)

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
             * `:custom_keys` (`t:keyword/0`) - Custom keys

             """
    end

    test "autogenerated type docs" do
      schema = [
        no_type: [],
        custom: [type: {:custom, __MODULE__, :foo, []}],
        or: [type: {:or, [:integer, :boolean]}],
        f: [type: {:fun, 3}],
        kw: [type: :keyword_list],
        nonempty_kw: [type: :non_empty_keyword_list],
        int: [type: :integer],
        ref: [type: :reference],
        list_of_ints: [type: {:list, :integer}],
        nested_list_of_ints: [type: {:list, {:list, :integer}}],
        list_of_kws: [type: {:list, {:keyword_list, []}}],
        list_of_maps: [type: {:list, {:map, []}}],
        map: [type: :map],
        map_of_strings: [type: {:map, :string, :string}],
        tuple: [type: {:tuple, [:integer, :atom, {:list, :string}]}],
        struct: [type: {:struct, URI}]
      ]

      assert NimbleOptions.docs(schema) == """
             * `:no_type`

             * `:custom`

             * `:or`

             * `:f` (function of arity 3)

             * `:kw` (`t:keyword/0`)

             * `:nonempty_kw` (non-empty `t:keyword/0`)

             * `:int` (`t:integer/0`)

             * `:ref` (`t:reference/0`)

             * `:list_of_ints` (list of `t:integer/0`)

             * `:nested_list_of_ints` (list of list of `t:integer/0`)

             * `:list_of_kws` (list of `t:keyword/0`)

             * `:list_of_maps` (list of `t:map/0`)

             * `:map` (`t:map/0`)

             * `:map_of_strings` (map of `t:String.t/0` keys and `t:String.t/0` values)

             * `:tuple` (tuple of `t:integer/0`, `t:atom/0`, list of `t:String.t/0` values)

             * `:struct` (struct of type URI)

             """
    end

    test "uses the :since schema option" do
      schema = [
        str_without_default: [
          type: :string,
          doc: "Some doc.",
          since: "10.0.0"
        ],
        str_with_default: [
          type: :string,
          doc: "Some doc.",
          since: "11.0.0",
          default: "dflt"
        ]
      ]

      assert NimbleOptions.docs(schema) == """
             * `:str_without_default` (`t:String.t/0`) - Some doc. *Available since version 10.0.0*.

             * `:str_with_default` (`t:String.t/0`) - Some doc. The default value is `"dflt"`. *Available since version 11.0.0*.

             """
    end
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
