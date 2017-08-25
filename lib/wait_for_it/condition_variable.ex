defmodule WaitForIt.ConditionVariable do
  use GenServer

  defstruct name: nil, waiters: []

  def start_link(name) do
    case GenServer.start_link(__MODULE__, name, name: name) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  def init(name) do
    {:ok, %__MODULE__{name: name}}
  end

  def signal(condition_var) do
    GenServer.cast(condition_var, :signal)
  end

  def wait(condition_var, opts \\ []) do
    GenServer.call(condition_var, :wait)
    receive do
      {:signal, ^condition_var} -> :ok
    after
      Keyword.get(opts, :timeout, 5_000) -> :timeout
    end
  end

  def handle_call(:wait, {from, _tag}, state) do
    {:reply, :ok, Map.update!(state, :waiters, &([from|&1]))}
  end

  def handle_cast(:signal, state) do
    for pid <- state.waiters, do: send(pid, {:signal, state.name})
    {:noreply, %{state | waiters: []}}
  end
end
