defmodule WaitForIt.ConditionVariable do
  use GenServer

  defstruct waiters: []

  def start_link do
    GenServer.start_link(__MODULE__, :ok)
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: via_tuple(name))
  end

  def registry, do: __MODULE__.Registry

  def signal(condition_var) when is_atom(condition_var),
    do: signal(via_tuple(condition_var))
  def signal(condition_var),
    do: GenServer.cast(condition_var, :signal)

  def wait(condition_var, opts \\ [])
  def wait(condition_var, opts) when is_atom(condition_var),
    do: wait(via_tuple(condition_var), opts)
  def wait(condition_var, opts) do
    ref = make_ref()
    GenServer.call(condition_var, {:wait, ref})
    receive do
      {:signal, ^ref} -> :ok
    after
      Keyword.get(opts, :timeout, 5_000) -> :timeout
    end
  end

  def init(:ok) do
    {:ok, %__MODULE__{}}
  end

  def handle_call({:wait, ref}, {from, _tag}, state) do
    {:reply, :ok, Map.update!(state, :waiters, &([{from, ref}|&1]))}
  end

  def handle_cast(:signal, state) do
    for {pid, ref} <- state.waiters, do: send(pid, {:signal, ref})
    {:noreply, %{state | waiters: []}}
  end

  defp via_tuple(name), do: {:via, Registry, {registry(), name}}
end
