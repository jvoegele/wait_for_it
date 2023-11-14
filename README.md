# WaitForIt

Various ways of waiting for things to happen.

This library allows you to wait on the results of asynchronous or remote operations using
intuitive and familiar syntax based on built-in Elixir language constructs.

There are three distinct forms of waiting provided:

  1. The `wait` macro waits until a given expression evaluates to a truthy value.
  2. The `case_wait` macro waits until a given expression evaluates to a value that
     matches any one of the given case clauses (looks like an Elixir `case` expression).
  3. The `cond_wait` macro waits until any one of the given expressions evaluates to a truthy
     value (looks like an Elixir `cond` expression).

See the [API reference](https://hexdocs.pm/wait_for_it/WaitForIt.html) for full documentation.

## Installation

`wait_for_it` can be installed by adding it to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wait_for_it, "~> 2.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/wait_for_it](https://hexdocs.pm/wait_for_it).
