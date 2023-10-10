defmodule CsrfPlus.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Plug-based CSRF implementation."

  def project do
    [
      app: :csrf_plus,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      preferred_cli_env: [
        "test.watch": :test
      ],
      # Hex
      package: package(),
      description: @description,
      # Docs
      name: "CsrfPlus",
      source_url: "https://github.com/rogersanctus/csrf_plus",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:plug, "~> 1.0"},
      {:telemetry, "~> 1.0"},
      {:uuid, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:mix_test_watch, git: "https://github.com/rogersanctus/mix-test.watch.git", only: [:test]},
      {:mox, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      mantainers: ["Rogério Ferreira"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/rogersanctus/csrf_plus"
      }
    ]
  end
end
