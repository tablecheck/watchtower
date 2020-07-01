defmodule Watchtower.MixProject do
  use Mix.Project

  @version "0.1.0"
  @url "https://github.com/tablecheck/watchtower"
  @maintainers [
    "Matthew Pinkston"
  ]

  def project do
    [
      app: :watchtower,
      description: "Polling made easy.",
      package: package(),
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @url,
      homepage_url: @url
    ]
  end

  def package do
    [
      maintainers: @maintainers,
      licenses: ["MIT"],
      links: %{Github: @url}
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Watchtower.Application, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
