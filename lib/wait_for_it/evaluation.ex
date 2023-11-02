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

  defmacro capture_with_clauses(with_clauses, do_block) do
    quote do
      fn ->
        with unquote(with_clauses) do
          unquote(do_block)
        end
      end
    end
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
