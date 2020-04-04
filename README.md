# NimbleOptions

> A library to validate options based on a spec.

## Installation

You can install install `nimble_options` by adding it to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nimble_options, "~> 0.1.0"}
  ]
end
```

## Usage

This library allows you to validate options based on a spec. A spec is a keyword
list specifying how the options you want to validate should look like:

```elixir
spec = [
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

Now, you can validate options through `NimbleOptions.validate/2`:

```elixir
options = [url: "https://example.com"]

NimbleOptions.validate(options, spec)
#=> {:ok, [url: "https://example.com", connections: 5]}
```

If the options don't match the spec, an error is returned:

```elixir
NimbleOptions.validate([connections: 3], spec)
#=> {:error, "required option :url not found, received options: [:connections]"}
```
