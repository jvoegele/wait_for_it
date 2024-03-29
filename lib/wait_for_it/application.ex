defmodule WaitForIt.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: WaitForIt.SignalRegistry},
      {Registry, keys: :unique, name: WaitForIt.V1.ConditionVariable.registry()},
      WaitForIt.V1.ConditionVariable.Supervisor
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: WaitForIt.Supervisor)
  end
end
