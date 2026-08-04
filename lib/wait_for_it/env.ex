defmodule WaitForIt.Env do
  @moduledoc false

  # The caller's `Macro.Env`, cut down to the fields anything downstream actually
  # reads.
  #
  # A full `__ENV__` is around 1000 words (~8 KB), and almost all of it is the
  # calling module's import table — `:functions`, `:macros`, `:requires` — which
  # grows with the caller's imports and is of no use to a telemetry handler or an
  # error struct. That term was being embedded in the caller's compiled module
  # once per wait, copied into the signal registry's ETS on every signal-based
  # wait, and copied again by any telemetry handler that forwards metadata
  # off-process.
  #
  # Trimming happens at macro expansion rather than at runtime, so the fat term is
  # never emitted in the first place: `escaped/1` is what the waiting macros
  # unquote in place of `__ENV__`.
  #
  # The trimmed value stays a real `%Macro.Env{}` rather than becoming a plain map,
  # because `Macro.Env.stacktrace/1` is called on it when a timeout reraises a
  # `MatchError`/`CaseClauseError`/`CondClauseError` at the caller's location. It
  # reads only `:module`, `:function`, `:file`, and `:line`, all of which survive,
  # so the reraised stacktrace is byte-for-byte what it was before.

  # The fields worth keeping. `WaitForIt.TimeoutError` has exposed exactly this set
  # since it was written; the telemetry path simply never applied the same cut.
  @kept [:context, :context_modules, :file, :function, :line, :module]

  @doc """
  Returns `env` with everything but `#{inspect(@kept)}` reset to the `Macro.Env`
  defaults.
  """
  @spec trim(Macro.Env.t()) :: Macro.Env.t()
  def trim(%Macro.Env{} = env), do: struct(Macro.Env, Map.take(env, @kept))

  @doc """
  Returns the trimmed env as quoted AST, for a macro to unquote in place of
  `__ENV__`.
  """
  @spec escaped(Macro.Env.t()) :: Macro.t()
  def escaped(%Macro.Env{} = env), do: env |> trim() |> Macro.escape()

  @doc """
  Returns the plain-map form carried in telemetry metadata and on
  `WaitForIt.TimeoutError`.

  A map rather than a struct because it is data crossing a boundary — into a
  telemetry handler, a log line, or a serialized error — where a `Macro.Env`
  struct would invite the assumption that the rest of its fields are populated.
  """
  @spec to_map(Macro.Env.t() | nil) :: map() | nil
  def to_map(%Macro.Env{} = env), do: Map.take(env, @kept)
  def to_map(_other), do: nil

  @doc """
  The env fields WaitForIt retains.
  """
  @spec kept_fields() :: [atom()]
  def kept_fields, do: @kept
end
