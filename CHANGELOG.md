# Changelog for NimbleOptions

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
