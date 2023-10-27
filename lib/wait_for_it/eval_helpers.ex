defmodule WaitForIt.EvalHelpers do
  @moduledoc false

  defmacro wrap_expression(nil), do: nil
  defmacro wrap_expression(expression), do: quote(do: fn -> unquote(expression) end)

  def eval_expression(wrapped_expression) when is_function(wrapped_expression) do
    wrapped_expression.()
  end

  defmacro wrap_case_clauses(case_clauses) do
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

  defmacro wrap_cond_clauses(cond_clauses) do
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

  defmacro wrap_else_block(nil), do: nil

  defmacro wrap_else_block([{:->, _, _} | _] = clauses) do
    quote do
      fn value ->
        case value do
          unquote(clauses)
        end
      end
    end
  end

  defmacro wrap_else_block(else_block) do
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
