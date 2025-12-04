defmodule Bind.MixProject do
  use Mix.Project

  @source_url "https://github.com/azer/bind"

  def project do
    [
      app: :bind,
      version: "0.11.0",
      elixir: "~> 1.14",
      source_url: @source_url,
      homepage_url: @source_url,
      description:
        "Builds dynamic Ecto queries based on given parameters, allowing developers to retrieve data flexibly without writing custom queries for each use case.",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: [
        licenses: ["MIT"],
        links: %{
          "GitHub" => @source_url
        }
      ],
      docs: [
        # The main page in the docs
        main: "readme",
        extras: ["README.md"]
      ]
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
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:ecto, "~> 3.7"}
    ]
  end
end
