defmodule WaitForIt.TimeoutError do
  @moduledoc """
  Exception type to represent a timeout that occurred while waiting.
  """

  defexception [:message, :timeout, :wait_type, :last_value]

  def exception(opts) do
    timeout = Keyword.fetch!(opts, :timeout)
    wait_type = Keyword.fetch!(opts, :wait_type)
    message = "WaitForIt timeout in #{inspect(wait_type)}: #{timeout}ms"

    params = %{
      message: message,
      timeout: timeout,
      wait_type: wait_type,
      last_value: opts[:last_value]
    }

    struct(__MODULE__, params)
  end
end
