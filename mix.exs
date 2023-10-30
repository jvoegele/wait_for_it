defmodule WaitForIt.Mixfile do
  use Mix.Project

  def project do
    [
      app: :wait_for_it,
      version: "1.4.3",
      elixir: "~> 1.15",
      name: "WaitForIt",
      description: "Elixir library providing various ways of waiting for things to happen",
      source_url: "https://github.com/jvoegele/wait_for_it",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
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

  @doc_modules [WaitForIt, WaitForIt.TimeoutError, WaitForIt.V1]

  defp docs do
    [
      main: "WaitForIt",
      filter_modules: fn module, _meta ->
        module in @doc_modules
      end
    ]
  end
end
