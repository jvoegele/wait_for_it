defmodule WaitForIt.Waitable.MatchWait do
  @moduledoc """
  Implementation of the `WaitForIt.Waitable` protocol for the `WaitForIt.match_wait` construct.
  """

  defstruct [:pattern_match]

  defmacro create(quoted_pattern, quoted_expression) do
    quote do
      require WaitForIt.Evaluation

      %WaitForIt.Waitable.MatchWait{
        pattern_match:
          WaitForIt.Evaluation.capture_pattern_match(
            unquote(quoted_pattern),
            unquote(quoted_expression)
          )
      }
    end
  end

  defimpl WaitForIt.Waitable do
    alias WaitForIt.Waitable.MatchWait

    def wait_type(%MatchWait{}), do: :match_wait

    def evaluate(%MatchWait{pattern_match: pattern_match}, _env) do
      WaitForIt.Evaluation.eval_pattern_match(pattern_match)
    end

    def handle_timeout(%MatchWait{}, last_value, env) do
      reraise MatchError, [term: last_value], Macro.Env.stacktrace(env)
    end
  end
end
