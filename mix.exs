defmodule WaitForIt.Mixfile do
  use Mix.Project

  @version "2.1.2"
  @source_url "https://github.com/jvoegele/wait_for_it"

  def project do
    [
      app: :wait_for_it,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

      # Hex
      package: package(),
      description: "Elixir library providing various ways of waiting for things to happen",

      # Docs
      name: "WaitForIt",
      source_url: @source_url,
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
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      plt_add_apps: [:ex_unit]
    ]
  end

  defp package do
    [
      name: :wait_for_it,
      files: ["lib", "guides", "mix.exs", "README.md", "LICENSE", "CHANGELOG.md"],
      maintainers: ["Jason Voegele"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  @doc_modules [WaitForIt, WaitForIt.Waitable, WaitForIt.TimeoutError, WaitForIt.V1]

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "guides/waiting_in_tests.md": [title: "Waiting in tests"],
        "guides/polling_vs_signaling.md": [title: "Polling vs signaling"],
        "guides/recipes.md": [title: "Recipes"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        Guides: ~r{guides/.+\.md}
      ],
      groups_for_docs: [
        wait: &(&1[:section] == :wait),
        match_wait: &(&1[:section] == :match_wait),
        case_wait: &(&1[:section] == :case_wait),
        cond_wait: &(&1[:section] == :cond_wait),
        signaling: &(&1[:section] == :signal)
      ],
      filter_modules: fn module, _meta ->
        module in @doc_modules
      end
    ]
  end
end
