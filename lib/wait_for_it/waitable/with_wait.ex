defmodule WaitForIt.Waitable.WithWait do
  @moduledoc """
  Implementation of the `WaitForIt.Waitable` protocol for the `WaitForIt.with_wait/3` construct.
  """

  defstruct [:with_clauses, :do_block, :else_block]

  defmacro create(with_clauses, do_block, else_block \\ nil) do
    quote do
      require WaitForIt.Evaluation

      %WaitForIt.Waitable.WithWait{
        with_clauses: WaitForIt.Evaluation.capture_with_clauses(unquote(with_clauses)),
        do_block: WaitForIt.Evaluation.capture_expression(unquote(do_block)),
        else_block: WaitForIt.Evaluation.capture_else_block(unquote(else_block))
      }
    end
  end
end
