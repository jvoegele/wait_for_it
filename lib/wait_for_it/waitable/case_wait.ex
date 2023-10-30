defmodule WaitForIt.Waitable.CaseWait do
  @moduledoc """
  Implementation of the `WaitForIt.Waitable` protocol for the `WaitForIt.case_wait/3` construct.
  """

  defstruct [:expression, :case_clauses, :else_block]

  defmacro create(quoted_expression, case_clauses, else_block \\ nil) do
    quote do
      require WaitForIt.EvalHelpers

      %WaitForIt.Waitable.CaseWait{
        expression: WaitForIt.EvalHelpers.wrap_expression(unquote(quoted_expression)),
        case_clauses: WaitForIt.EvalHelpers.wrap_case_clauses(unquote(case_clauses)),
        else_block: WaitForIt.EvalHelpers.wrap_else_block(unquote(else_block))
      }
    end
  end

  defimpl WaitForIt.Waitable do
    alias WaitForIt.Waitable.CaseWait

    def wait_type(%CaseWait{}), do: :case_wait

    def evaluate(%CaseWait{expression: expression, case_clauses: case_clauses}, _env) do
      value = WaitForIt.EvalHelpers.eval_expression(expression)

      try do
        result = WaitForIt.EvalHelpers.eval_case_expression(value, case_clauses)
        {:halt, result}
      rescue
        CaseClauseError -> {:cont, value}
      end
    end

    def handle_timeout(%CaseWait{else_block: else_block}, last_value, _env) do
      WaitForIt.EvalHelpers.eval_else_block(last_value, else_block)
    end
  end
end
