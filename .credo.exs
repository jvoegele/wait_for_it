# Credo configuration. The strict gate runs against library code only; test code favors
# clarity over lint rules and is intentionally excluded from the strict checks.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "mix.exs"],
        excluded: []
      },
      strict: true,
      plugins: [],
      requires: [],
      checks: %{
        disabled: [
          # WaitForIt is macro-heavy: the macros intentionally use fully-qualified module
          # names inside `quote` blocks, so the "alias nested modules" suggestion is noise here.
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
