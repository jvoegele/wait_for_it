defmodule WaitForIt.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec, warn: false

  def start(_type, _args) do
    children = [
      supervisor(Registry, [:unique, WaitForIt.ConditionVariable.registry()]),
      supervisor(WaitForIt.ConditionVariable.Supervisor, [])
    ]

    opts = [strategy: :one_for_one, name: WaitForIt.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
