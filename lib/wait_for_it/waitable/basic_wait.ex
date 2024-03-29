defmodule WaitForIt.Waitable.BasicWait do
  @moduledoc """
  Implementation of the `WaitForIt.Waitable` protocol for basic truthy/falsy wait conditions.
  """

  defstruct [:expression]

  defmacro create(quoted_expression) do
    quote do
      require WaitForIt.Evaluation

      %WaitForIt.Waitable.BasicWait{
        expression: WaitForIt.Evaluation.capture_expression(unquote(quoted_expression))
      }
    end
  end

  defimpl WaitForIt.Waitable do
    alias WaitForIt.Waitable.BasicWait

    def wait_type(%BasicWait{}), do: :wait

    def evaluate(%BasicWait{expression: expression}, _env) do
      value = WaitForIt.Evaluation.eval_expression(expression)

      if value do
        {:halt, value}
      else
        {:cont, value}
      end
    end

    def handle_timeout(_waitable, last_value, _env), do: last_value
  end
end
