# WaitForIt

Various ways to wait for things to happen.

Since most Elixir systems are highly concurrent, there must be a way to coordinate and synchronize
the processes in the system. While the language provides features (such as
`Process.sleep/1` and `receive`/`after`) that can be used to implement such synchronization, they are
inconvenient to use for this purpose. `WaitForIt` builds on top of these language features to
provide convenient and easy-to-use facilities for synchronizing concurrent activities. While
this is likely most useful for test code in which tests must wait for concurrent or asynchronous
activities to complete, it is also useful in any scenario where concurrent processes must
coordinate their activity. Examples include asynchronous event handling, producer-consumer
processes, and time-based activity.

There are three distinct forms of waiting provided:

  1. The `wait` macro waits until a given expression evaluates to a truthy value.
  2. The `case_wait` macro waits until a given expression evaluates to a value that
     matches any one of the given case clauses (looks like an Elixir `case` expression).
  3. The `cond_wait` macro waits until any one of the given expressions evaluates to a truthy
     value (looks like an Elixir `cond` expression).

See the [API reference](https://hexdocs.pm/wait_for_it/WaitForIt.html) for full documentation.

## Installation

`wait_for_it` can be installed from Hex by adding `wait_for_it` to your list
of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wait_for_it, "~> 2.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/wait_for_it](https://hexdocs.pm/wait_for_it).
