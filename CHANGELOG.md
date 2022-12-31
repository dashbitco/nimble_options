# Changelog for NimbleOptions

## v0.5.2

  * Add support for a {:struct, struct_name} type specifier
    * Example:

        ```elixir
        schema = [struct: [type: {:struct, URI}]]
        ```
  * Add support for the type_doc option
    * Example:

        ```elixir
        schema = [
          foo: [type: :string, type_doc: "`t:SomeModule.t/0`", doc: "The foo."]
        ]
        ```

## v0.5.1

  * Support generating typespecs for `:tuple`, `:map`, and `{:map, key, value}` options

## v0.5.0

  * Support `:map` which accepts the same `:keys` specification as keyword lists
  * Normalize all error messages to include the key and expected value out of the box
  * Do not nest options when rendered in Markdown and make sure multiline content is properly indented
  * Handle \r\n style of line breaks in docs
  * Automatically add types to generated docs
  * Support lists of keyword lists in `:list`
  * Add the `:reference` option type
  * Add the `:tuple` option type

## v0.4.0

  * Add support for all enumerables in `{:in, choices}` instead of just lists. You can now do things such as `{:in, 1..10}`.
  * Deprecate the `:rename_to` schema option and emit a warning when used.
  * Remove the `{:one_of, choices}` type which was deprecated in v0.3.3.

## v0.3.7

  * Add `NimbleOptions.new!/1` to validate the schema once.

## v0.3.6

  * Add `:float` type.
  * Fix docs generation when custom key type has no keys.

## v0.3.5

  * Add support for the `{:list, subtype}` type.

## v0.3.4

  * Support nested schemas in the `{:or, subtypes}` type as `{:or, [:string, keyword_list: [enabled: [type: :boolean]]]}`.
  * Improve validation of the return value of `{:custom, module, function, args}` functions.
  * Support options in `NimbleOptions.docs/2`. For now only the `:nest_level` option is supported.

## v0.3.3

  * Add the `{:or, subtypes}` type.
  * Deprecate the `{:one_of, choices}` and replace it with `{:in, choices}`. Using `{:one_of, choices}` emits a warning now.

## v0.3.2

  * Fix a small bug with docs for nested schemas.

## v0.3.1

  * Return `:key` and `:value` on `%NimbleOptions.ValidationError{}` to allow programmatic use of errors.
  * Validate default values according to the specified type.

## v0.3.0

  * **Breaking change**: return `{:error, %NimbleOptions.ValidationError{}}` tuples when there's a validation error in `NimbleOptions.validate/2` instead of `{:error, message}` (with `message` being a string). You can use `Exception.message/1` to turn the `NimbleOptions.ValidationError` struct into a string.
  * Add the `:pid` type.

## v0.2.1

  * Add `NimbleOptions.validate!/2`.

## v0.2.0

  * Change the behavior of `NimbleOptions.docs/1` to accept a normal schema and produce documentation for that.
  * Add support for `doc: false` as a schema option to hide an option or an option and its subsection.

## v0.1.0 (2020-04-07)

  * First release.
