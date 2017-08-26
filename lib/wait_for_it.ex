defmodule WaitForIt do
  @moduledoc """
  Various ways to wait for things to happen.
  """

  alias WaitForIt.Helpers

  defmacro wait(expression, opts \\ []) do
    frequency = Keyword.get(opts, :frequency, 100)
    timeout = Keyword.get(opts, :timeout, 5_000)
    condition_var = Keyword.get(opts, :signal)

    if condition_var do
      quote do
        require WaitForIt.Helpers
        _ = Helpers.condition_var_wait(unquote(expression),
                                       unquote(condition_var),
                                       unquote(timeout))
      end
    else
      quote do
        require WaitForIt.Helpers
        Helpers.polling_wait(unquote(expression),
                             unquote(frequency),
                             unquote(timeout))
      end
    end
  end

  defmacro case_wait(expression, opts \\ [], do: block) do
    frequency = Keyword.get(opts, :frequency, 100)
    timeout = Keyword.get(opts, :timeout, 5_000)
    condition_var = Keyword.get(opts, :signal)

    if condition_var do
      quote do
        require WaitForIt.Helpers
        _ = Helpers.condition_var_case_wait(unquote(expression),
                                            unquote(condition_var),
                                            unquote(timeout),
                                            unquote(block))
      end
    else
      quote do
        require WaitForIt.Helpers
        Helpers.polling_case_wait(unquote(expression),
                                  unquote(frequency),
                                  unquote(timeout),
                                  unquote(block))
      end
    end
  end

  defmacro cond_wait(opts \\ [], do: block) do
    frequency = Keyword.get(opts, :frequency, 100)
    timeout = Keyword.get(opts, :timeout, 5_000)
    condition_var = Keyword.get(opts, :signal)

    if condition_var do
      quote do
        require WaitForIt.Helpers
        _ = Helpers.condition_var_cond_wait(unquote(condition_var),
                                            unquote(timeout),
                                            unquote(block))
      end
    else
      quote do
        require WaitForIt.Helpers
        Helpers.polling_cond_wait(unquote(frequency),
                                  unquote(timeout),
                                  unquote(block))
      end
    end
  end

  defmacro signal(condition_var) do
    quote do
      require WaitForIt.Helpers
      Helpers.condition_var_signal(unquote(condition_var))
    end
  end
end
