# WaitForIt and AI coding agents

WaitForIt ships agent-facing rules inside the package: a condensed account of the five waiting
forms, the options, and — the part that earns its keep — the traps where the obvious guess is
wrong. This guide is for the person wiring them into an application that uses WaitForIt.

What the rules *say* is [Usage rules](usage-rules.md), published here and readable on its own.
This guide is about getting them in front of your agent.

Nothing here is specific to one agent. `AGENTS.md` is the instruction file most coding agents now
read; where a path below has to be concrete it is the default, and the setting that changes it is
named alongside.

## Why bother

Waiting code is unusually easy for an agent to get *plausibly* wrong. The mistakes compile, read
naturally, and pass a hasty review — and then produce a test that does not actually wait:

```elixir
match_wait(user, Repo.get(User, id))       # returns nil immediately — never waits
refute_eventually(job.status == :running)  # asserts "never", not "eventually not"
case_wait status() do
  :done -> :ok
  _ -> :pending                            # catch-all: matches on the first evaluation
end
```

Each is the sort of thing a model reaches for by analogy with `case` or `assert`, where the same
shape is correct. The rules exist to head those off, and they are versioned with the library, so
they stay right as the library changes.

## What ships in the package

One file, at `deps/wait_for_it/usage-rules.md` after `mix deps.get` — about 10 KB. Nothing to
download separately.

It covers: the five forms and the one timeout rule; every option and its default; and a "traps"
section — waiting inside a GenServer callback, catch-all clauses, bare-variable patterns,
unparenthesized guards on `<~` clauses, `refute_eventually` semantics, and the fact that a
waitable expression's side effects repeat.

## Setup with `usage_rules`

[`usage_rules`](https://hex.pm/packages/usage_rules) reads a config block in your `mix.exs` and
writes the rules into your agent file for you. It is a dev-only dependency of your application,
not of WaitForIt.

```elixir
# mix.exs
def project do
  [
    # ...
    usage_rules: usage_rules()
  ]
end

defp deps do
  [
    {:wait_for_it, "~> 2.6"},
    {:usage_rules, "~> 1.2", only: [:dev]}
  ]
end

defp usage_rules do
  [
    file: "AGENTS.md",
    usage_rules: [:wait_for_it]
  ]
end
```

Then:

```sh
mix deps.get
mix usage_rules.sync
```

That inlines the rules into `AGENTS.md`. Set `file:` to whichever instruction file your agent
reads, and commit the result so everyone on the team — and every CI agent — gets the same
instructions.

If you would rather not spend the context on every session, link instead of inlining:

```elixir
usage_rules: [{:wait_for_it, link: :markdown}]
```

That writes a few hundred bytes pointing at `deps/wait_for_it/usage-rules.md`, which the agent
reads when it needs to. Inlining is the better default here — 10 KB is small, and an agent that
has to decide whether to go and read something often decides not to.

Re-run `mix usage_rules.sync` after upgrading WaitForIt, so the rules in your repository match the
version you actually depend on.

## Without `usage_rules`

The file is plain Markdown at a predictable path, so nothing here needs a tool. Add a section to
your instruction file pointing at it:

```markdown
## WaitForIt

This project uses WaitForIt for waiting on asynchronous work. Before writing or changing a
`wait`, `match_wait`, `case_wait`, `cond_wait`, `with_wait`, `until`, or any
`assert_eventually` / `refute_eventually` / `assert_always` assertion, read
`deps/wait_for_it/usage-rules.md`.
```

If your agent supports imports and you would rather have the rules resident than fetched, write
that path in whatever import form it uses — `@deps/wait_for_it/usage-rules.md` in Claude Code.

## What to add yourself

The shipped rules describe the library. They cannot know your project's conventions, and those
are usually what an agent gets wrong next. Worth adding to your own instruction file:

  * **Your house timeout.** The library default is 5 s, which is far too long for a unit test and
    sometimes too short for an integration suite. If your project has a standard, say it.
  * **Which layer may wait.** Waiting blocks the calling process. If waits belong in tests and
    boundary modules only, and never in a GenServer callback, write that down.
  * **Your test helper, if you have one.** An agent will reach for `assert_eventually` directly
    unless told that your suite wraps it.

---

**Previous:** [Troubleshooting](troubleshooting.md) · **Next:** [Usage rules](usage-rules.md)
