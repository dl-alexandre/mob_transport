defmodule Mob.Transport.MixProject do
  use Mix.Project

  @github_url "https://github.com/dl-alexandre/mob_transport"
  @version "0.1.0"
  @description "Small reusable transport abstraction for mob transport plugins."

  def project do
    [
      app: :mob_transport,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: @description,
      package: package(),
      source_url: @github_url,
      homepage_url: @github_url,
      docs: [
        main: "readme",
        extras: ["README.md", "docs/ARCHITECTURE.md", "CHANGELOG.md", "LICENSE"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40.2", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Changelog" => "#{@github_url}/blob/main/CHANGELOG.md",
        "mob" => "https://github.com/GenericJam/mob",
        "mob_dev" => "https://github.com/GenericJam/mob_dev"
      },
      files: ~w(
        lib
        docs
        mix.exs
        README.md
        CHANGELOG.md
        LICENSE
      )
    ]
  end
end
