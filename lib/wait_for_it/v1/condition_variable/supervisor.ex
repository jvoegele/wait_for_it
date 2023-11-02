defmodule WaitForIt.V1.ConditionVariable.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias WaitForIt.V1.ConditionVariable

  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def create_condition_variable do
    DynamicSupervisor.start_child(__MODULE__, ConditionVariable)
  end

  def named_condition_variable(name) when is_atom(name) do
    case DynamicSupervisor.start_child(__MODULE__, {ConditionVariable, name: name}) do
      {:ok, pid} when is_pid(pid) ->
        {:ok, pid}

      {:error, {:already_started, pid}} when is_pid(pid) ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
