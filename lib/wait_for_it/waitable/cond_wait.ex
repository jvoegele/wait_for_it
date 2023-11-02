defmodule WaitForIt.Waitable.CondWait do
  @moduledoc """
  Implementation of the `WaitForIt.Waitable` protocol for the `WaitForIt.cond_wait/3` construct.
  """

  defstruct [:cond_clauses, :else_block]

  defmacro create(cond_clauses, else_block \\ nil) do
    quote do
      require WaitForIt.Evaluation

      %WaitForIt.Waitable.CondWait{
        cond_clauses: WaitForIt.Evaluation.capture_cond_clauses(unquote(cond_clauses)),
        else_block: WaitForIt.Evaluation.capture_else_block(unquote(else_block))
      }
    end
  end

  defimpl WaitForIt.Waitable do
    alias WaitForIt.Waitable.CondWait

    def wait_type(%CondWait{}), do: :cond_wait

    def evaluate(%CondWait{cond_clauses: cond_clauses}, _env) do
      try do
        result = WaitForIt.Evaluation.eval_cond_expression(cond_clauses)
        {:halt, result}
      rescue
        CondClauseError -> {:cont, nil}
      end
    end

    def handle_timeout(%CondWait{else_block: else_block}, last_value, _env) do
      WaitForIt.Evaluation.eval_else_block(last_value, else_block)
    end
  end
end
