defmodule WaitForIt.Waitable.FunctionWait do
  @moduledoc false

  # Backs the functional `WaitForIt.until/2` API. Unlike the macro-based waitables, there is no
  # AST to capture — the caller supplies the 0-arity function directly, which the wait loop calls
  # on each evaluation, halting on a truthy result just like `WaitForIt.Waitable.BasicWait`.

  defstruct [:fun]

  defimpl WaitForIt.Waitable do
    alias WaitForIt.Waitable.FunctionWait

    def wait_type(%FunctionWait{}), do: :until

    def evaluate(%FunctionWait{fun: fun}, _env) do
      value = fun.()

      if value do
        {:halt, value}
      else
        {:cont, value}
      end
    end

    def handle_timeout(_waitable, last_value, _env), do: last_value
  end
end
