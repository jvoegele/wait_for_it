defmodule WaitForIt.Mixfile do
  use Mix.Project

  def project do
    [
      app: :wait_for_it,
      version: "1.4.1",
      description: "Elixir library for waiting for things to happen",
      source_url: "https://github.com/jvoegele/wait_for_it",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WaitForIt.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.30.9", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 0.6", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      name: :wait_for_it,
      files: ["lib", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md"],
      maintainers: ["Jason Voegele"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/jvoegele/wait_for_it"}
    ]
  end
end
