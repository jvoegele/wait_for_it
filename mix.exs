defmodule WaitForIt.Mixfile do
  use Mix.Project

  @version "2.6.0"
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
      {:telemetry, "~> 1.0"},
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
      # `usage-rules.md` is agent-facing guidance, consumed by `usage_rules`
      # (https://hex.pm/packages/usage_rules). It must be listed here or it is absent
      # from the tarball and `mix usage_rules.sync` finds nothing.
      files: [
        "lib",
        "guides",
        "usage-rules.md",
        "mix.exs",
        # Shipped so `import_deps: [:wait_for_it]` finds the `locals_without_parens` rules for the
        # paren-free macro style the guides use; without it in the tarball the export block is
        # invisible to everyone installing from Hex, and `mix format` re-parenthesises every wait.
        ".formatter.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ],
      maintainers: ["Jason Voegele"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  @doc_modules [
    WaitForIt,
    WaitForIt.Test,
    WaitForIt.Backoff,
    WaitForIt.Waitable,
    WaitForIt.TimeoutError,
    WaitForIt.V1
  ]

  @guides [
    "guides/getting_started.md",
    "guides/waiting_in_tests.md",
    "guides/polling_vs_signaling.md",
    "guides/composing_waits.md",
    "guides/recipes.md",
    "guides/telemetry.md",
    "guides/troubleshooting.md",
    "guides/ai_coding_agents.md"
  ]

  @reference [
    "guides/cheatsheet.cheatmd",
    # Agent-facing, but published here too: the README and the agents guide both link to it, and a
    # reader browsing HexDocs should be able to see what their agent is being told.
    "usage-rules.md"
  ]

  defp docs do
    [
      # Getting started is the landing page, so a new reader arrives at installation and a first
      # wait rather than at the reference. The README remains the `WaitForIt` moduledoc (see
      # `lib/wait_for_it.ex`), which is where the conceptual overview lives, so nothing duplicates.
      # The README's own Installation and "Where to go from here" sections sit outside the
      # moduledoc markers on purpose: setup and navigation belong to this landing page and the
      # sidebar, not to the API reference for the module.
      main: "getting_started",
      source_ref: "#{@version}",
      extras: [
        # Guides, ordered as a learning path; each one links to the next.
        "guides/getting_started.md": [title: "Getting started"],
        "guides/waiting_in_tests.md": [title: "Waiting in tests"],
        "guides/polling_vs_signaling.md": [title: "Polling vs signaling"],
        "guides/composing_waits.md": [title: "Composing waits"],
        "guides/recipes.md": [title: "Recipes"],
        "guides/telemetry.md": [title: "Telemetry"],
        "guides/troubleshooting.md": [title: "Troubleshooting"],
        "guides/ai_coding_agents.md": [title: "WaitForIt and AI coding agents"],
        # Reference is for lookup rather than reading, so it sits after the narrative path.
        "guides/cheatsheet.cheatmd": [title: "Cheatsheet"],
        "usage-rules.md": [title: "Usage rules"],
        "guides/about.md": [title: "About"],
        # Ungrouped, which is what puts these above the groups in the sidebar rather than
        # in the middle of the reading path; ExDoc hoists ungrouped extras regardless of
        # their position here.
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        Guides: @guides,
        Reference: @reference,
        About: ["guides/about.md"]
      ],
      groups_for_docs: [
        wait: &(&1[:section] == :wait),
        match_wait: &(&1[:section] == :match_wait),
        case_wait: &(&1[:section] == :case_wait),
        cond_wait: &(&1[:section] == :cond_wait),
        with_wait: &(&1[:section] == :with_wait),
        until: &(&1[:section] == :until),
        signaling: &(&1[:section] == :signal)
      ],
      filter_modules: fn module, _meta ->
        module in @doc_modules
      end
    ]
  end
end
