# NimbleOptions

![](https://github.com/dashbitco/nimble_options/workflows/CI/badge.svg)

Simple library for validating and documenting options.

## Installation

You can install `nimble_options` by adding it to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nimble_options, "~> 0.1.0"}
  ]
end
```

## Usage

This library allows you to validate options based on a definition.
A definition is a keyword list specifying how the options you want
to validate should look like:

```elixir
schema = [
  connections: [
    type: :non_neg_integer,
    default: 5
  ],
  url: [
    type: :string,
    required: true
  ]
]
```

Now you can validate options through `NimbleOptions.validate/2`:

```elixir
options = [url: "https://example.com"]

NimbleOptions.validate(options, schema)
#=> {:ok, [url: "https://example.com", connections: 5]}
```

If the options don't match the definition, an error is returned:

```elixir
NimbleOptions.validate([connections: 3], schema)
#=> {:error, "required option :url not found, received options: [:connections]"}
```

## Nimble*

Other nimble libraries by Dashbit:

  * [NimbleCSV](https://github.com/dashbitco/nimble_csv) - simple and fast CSV parsing
  * [NimbleParsec](https://github.com/dashbitco/nimble_parsec) - simple and fast parser combinators

## License

Copyright 2020 Dashbit

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
