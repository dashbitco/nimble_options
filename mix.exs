defmodule NimbleOptions.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/dashbitco/nimble_options"

  def project do
    [
      app: :nimble_options,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      package: package(),
      description: "Library to perform validation of options based on schemas",

      # Docs
      name: "NimbleOptions",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.19.0", only: :docs}
    ]
  end

  defp package do
    [
      maintainers: ["Andrea Leopardi", "José Valim", "Marlus Saraiva"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => @repo_url}
    ]
  end

  defp docs do
    [
      main: "NimbleOptions",
      source_ref: "v#{@version}",
      source_url: @repo_url
    ]
  end
end
