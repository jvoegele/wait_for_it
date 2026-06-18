defmodule WaitForIt.Evaluation do
  @moduledoc """
  Helper module for capturing compile-time expressions (i.e. ASTs) and evaluating them at runtime.
  """

  defmacro capture_expression(nil), do: nil
  defmacro capture_expression(expression), do: quote(do: fn -> unquote(expression) end)

  def eval_expression(captured_expression) when is_function(captured_expression) do
    captured_expression.()
  end

  defmacro capture_case_clauses(case_clauses) do
    quote do
      fn expr ->
        case expr do
          unquote(case_clauses)
        end
      end
    end
  end

  def eval_case_expression(value, case_clauses) when is_function(case_clauses) do
    case_clauses.(value)
  end

  defmacro capture_cond_clauses(cond_clauses) do
    quote do
      fn ->
        cond do
          unquote(cond_clauses)
        end
      end
    end
  end

  def eval_cond_expression(cond_clauses) when is_function(cond_clauses) do
    cond_clauses.()
  end

  defmacro capture_pattern_match(pattern, expression) do
    quote do
      fn ->
        value = unquote(expression)

        if match?(unquote(pattern), value) do
          {:halt, value}
        else
          {:cont, value}
        end
      end
    end
  end

  def eval_pattern_match(pattern_match) do
    pattern_match.()
  end

  @doc """
  Replaces binding variables in a `pattern` with `_`, leaving pinned expressions (`^foo`) and
  everything else intact.

  This is used to build a "match test" copy of a pattern that binds nothing, so that patterns
  whose variables are bound elsewhere (by an enclosing `with`/`case`/`=`) do not trigger spurious
  "unused variable" warnings when the pattern is used only to test for a match.

  For a guarded pattern (`pattern when guard`), the guard is left untouched and any pattern
  variables that the guard references are preserved — they are *used* (by the guard), so they
  would not produce an unused-variable warning and must remain bound for the guard to compile.
  """
  def ignore_pattern_bindings(ast), do: ignore_pattern_bindings(ast, MapSet.new())

  defp ignore_pattern_bindings({:when, meta, [pattern, guard]}, _keep) do
    {:when, meta, [ignore_pattern_bindings(pattern, guard_var_names(guard)), guard]}
  end

  defp ignore_pattern_bindings({:^, _, _} = pinned, _keep), do: pinned

  defp ignore_pattern_bindings({name, meta, context}, keep)
       when is_atom(name) and is_atom(context) do
    if MapSet.member?(keep, name), do: {name, meta, context}, else: {:_, meta, context}
  end

  defp ignore_pattern_bindings({form, meta, args}, keep) when is_list(args) do
    {ignore_pattern_bindings(form, keep), meta, Enum.map(args, &ignore_pattern_bindings(&1, keep))}
  end

  defp ignore_pattern_bindings({left, right}, keep) do
    {ignore_pattern_bindings(left, keep), ignore_pattern_bindings(right, keep)}
  end

  defp ignore_pattern_bindings(list, keep) when is_list(list) do
    Enum.map(list, &ignore_pattern_bindings(&1, keep))
  end

  defp ignore_pattern_bindings(other, _keep), do: other

  defp guard_var_names(guard) do
    {_ast, names} =
      Macro.prewalk(guard, [], fn
        {name, _meta, context} = node, acc when is_atom(name) and is_atom(context) ->
          {node, [name | acc]}

        node, acc ->
          {node, acc}
      end)

    MapSet.new(names)
  end

  defmacro capture_else_block(nil), do: nil

  defmacro capture_else_block([{:->, _, _} | _] = clauses) do
    quote do
      fn value ->
        case value do
          unquote(clauses)
        end
      end
    end
  end

  defmacro capture_else_block(else_block) do
    quote do
      fn _ ->
        unquote(else_block)
      end
    end
  end

  def eval_else_block(value, nil), do: value

  def eval_else_block(value, else_block) when is_function(else_block) do
    else_block.(value)
  end
end
