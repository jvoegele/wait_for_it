defmodule WaitForIt.Mixfile do
  use Mix.Project

  def project do
    [
      app: :wait_for_it,
      version: "1.0.0",
      description: "Elixir library for waiting for things to happen",
      source_url: "https://github.com/jvoegele/wait_for_it",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      package: package(),
      deps: deps()
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
      {:ex_doc, "~> 0.16.3"},
    ]
  end

  defp package do
    [
      name: :wait_for_it,
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Jason Voegele"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/jvoegele/wait_for_it"}
    ]
  end
end
