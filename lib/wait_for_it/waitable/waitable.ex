defprotocol WaitForIt.Waitable do
  @moduledoc """
  Protocol used for evaluating waitable expressions against waiting conditions to determine if
  waiting should continue or halt with a final value.
  """

  @type wait_type :: atom()
  @type value :: any()

  @spec wait_type(t()) :: wait_type()
  def wait_type(waitable)

  @doc """
  Evaluates the waitable expression to provide its value, or to continue to wait.

  It should return `{:halt, value}` if the wait is over and the final value of the waitable
  expression has been determined, or `{:cont, value}` if waiting should continue.
  """
  @spec evaluate(t(), Macro.Env.t()) :: {:halt, value()} | {:cont, value()}
  def evaluate(waitable, env)

  @doc """
  Provides the final value of the waitable expression in the event of a timeout.
  """
  @spec handle_timeout(t(), value(), Macro.Env.t()) :: value()
  def handle_timeout(waitable, last_value, env)
end

defprotocol WaitForIt.Waitable.Raise do
  @moduledoc """
  Protocol used to customize exceptions that are raised in the event of a timeout.
  """

  @fallback_to_any true

  @spec raise_timeout_error(
          t(),
          WaitForIt.Waitable.value(),
          timeout_ms :: non_neg_integer(),
          Macro.Env.t()
        ) ::
          no_return()
  def raise_timeout_error(waitable, last_value, timeout_ms, env)
end

defimpl WaitForIt.Waitable.Raise, for: Any do
  def raise_timeout_error(waitable, last_value, timeout_ms, env) do
    raise WaitForIt.TimeoutError,
      waitable: waitable,
      timeout: timeout_ms,
      last_value: last_value,
      env: env
  end
end
