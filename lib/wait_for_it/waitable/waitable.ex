defprotocol WaitForIt.Waitable do
  # TODO: reword this protocol description
  @moduledoc """
  Protocol used for evaluating wait conditions to determine if waiting should continue and to
  determine the final value of the wait.
  """

  @type value :: any()

  @spec evaluate(t(), Macro.Env.t()) :: {:halt, value()} | {:cont, value()}
  def evaluate(waitable, env)

  @spec handle_timeout(t(), value(), Macro.Env.t()) :: value()
  def handle_timeout(waitable, last_value, env)
end
