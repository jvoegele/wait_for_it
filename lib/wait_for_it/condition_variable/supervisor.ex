defmodule WaitForIt.ConditionVariable.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def create_condition_variable do
    Supervisor.start_child(__MODULE__, [])
  end

  def named_condition_variable(name) when is_atom(name) do
    case Supervisor.start_child(__MODULE__, [name]) do
      {:ok, pid} when is_pid(pid) ->
        {:ok, pid}

      {:error, {:already_started, pid}} when is_pid(pid) ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def init(:ok) do
    children = [
      worker(WaitForIt.ConditionVariable, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
