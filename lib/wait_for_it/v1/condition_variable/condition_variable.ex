defmodule WaitForIt.V1.ConditionVariable do
  @moduledoc false

  use GenServer,
    restart: :temporary

  @default_idle_timeout 60_000

  defstruct waiters: [],
            idle_timeout: @default_idle_timeout

  def start_link, do: start_link([])

  def start_link(opts) when is_list(opts) do
    name_opt =
      case Keyword.get(opts, :name) do
        name when is_atom(name) -> [name: via_tuple(name)]
        _ -> []
      end

    idle_timeout = Keyword.get(opts, :idle_timeout, @default_idle_timeout)
    GenServer.start_link(__MODULE__, idle_timeout, name_opt)
  end

  def registry, do: __MODULE__.Registry

  def signal(condition_var) when is_atom(condition_var), do: signal(via_tuple(condition_var))
  def signal(condition_var), do: GenServer.cast(condition_var, :signal)

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

  @impl true
  def init(idle_timeout) do
    {:ok, %__MODULE__{idle_timeout: idle_timeout}}
  end

  @impl true
  def handle_call({:wait, ref}, {from, _tag}, state) do
    {:reply, :ok, Map.update!(state, :waiters, &[{from, ref} | &1])}
  end

  @impl true
  def handle_cast(:signal, state) do
    for {pid, ref} <- state.waiters, do: send(pid, {:signal, ref})
    {:noreply, %{state | waiters: []}, state.idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    {:stop, :normal, state}
  end

  defp via_tuple(name), do: {:via, Registry, {registry(), name}}
end
