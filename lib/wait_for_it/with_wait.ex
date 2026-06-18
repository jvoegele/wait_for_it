defmodule WaitForIt.WithWait do
  @moduledoc false

  # Compile-time helpers for the `WaitForIt.with_wait/2,3` and `WaitForIt.with_wait!/2,3` macros.
  #
  # `with_wait` is a pure compile-time transformation into a regular `with` expression. Each
  # `<~` (wait-for-match) clause becomes a `<-` clause whose right-hand side is a soft
  # `WaitForIt.__wait_clause__/3` wait; every other clause passes through unchanged. The `with`
  # then provides binding, `else` routing, and `WithClauseError` for free.

  @doc """
  Builds the `with` AST for a `with_wait`/`with_wait!` call.

  `mode` is `:return_last_value` for `with_wait` (a `<~` timeout flows to `else`) or `:raise` for
  `with_wait!` (a `<~` timeout raises `WaitForIt.TimeoutError`).
  """
  def build({:on, meta, clauses}, global_opts, blocks, mode) when is_list(clauses) do
    do_block = Keyword.fetch!(blocks, :do)
    else_block = Keyword.get(blocks, :else)
    with_clauses = Enum.map(clauses, &compile_clause(&1, global_opts, mode))

    block_kw = [do: do_block] ++ if(else_block, do: [else: else_block], else: [])
    {:with, meta, with_clauses ++ [block_kw]}
  end

  def build(other, _global_opts, _blocks, _mode) do
    raise ArgumentError,
          "with_wait expects its clauses wrapped in on(...), for example:\n\n" <>
            "    with_wait on({:ok, x} <- a(), {:ok, y} <~ b()) do\n" <>
            "      ...\n" <>
            "    end\n\n" <>
            "Got: #{Macro.to_string(other)}"
  end

  # A `<~` clause becomes `pattern <- WaitForIt.__wait_clause__(pattern, expr, opts)`.
  defp compile_clause({:<~, meta, [pattern, rhs]}, global_opts, mode) do
    {expr, clause_opts} = split_rhs(rhs)

    opts =
      quote do
        Keyword.put(
          Keyword.merge(unquote(global_opts), unquote(clause_opts)),
          :on_timeout,
          unquote(mode)
        )
      end

    wait_call =
      quote do
        WaitForIt.__wait_clause__(unquote(pattern), unquote(expr), unquote(opts))
      end

    {:<-, meta, [pattern, wait_call]}
  end

  # Every other clause (ordinary `<-`, bare expression, etc.) passes through to `with` unchanged.
  defp compile_clause(clause, _global_opts, _mode), do: clause

  # `pattern <~ {expr, opts}` carries per-clause options when the right-hand side is a 2-tuple
  # whose second element is a literal keyword list. Anything else is the waited-on expression
  # itself (so `coords <~ {x(), y()}` waits for the tuple value).
  defp split_rhs({expr, opts}) when is_list(opts) do
    if keyword_list?(opts), do: {expr, opts}, else: {{expr, opts}, []}
  end

  defp split_rhs(expr), do: {expr, []}

  defp keyword_list?(list) do
    Enum.all?(list, fn
      {key, _value} when is_atom(key) -> true
      _ -> false
    end)
  end
end
