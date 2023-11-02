defmodule WaitForIt.TimeoutError do
  @moduledoc """
  Exception type to represent a timeout that occurred while waiting.
  """

  defexception [:message, :waitable, :timeout, :last_value, :env]

  @type t :: %__MODULE__{
          __exception__: true,
          message: String.t(),
          waitable: WaitForIt.Waitable.t(),
          timeout: non_neg_integer(),
          last_value: term(),
          env: env()
        }

  @typedoc """
  Type to represent the `:env` field of `WaitForIt.TimeoutError` exceptions.

  This struct is a subset of of `Macro.Env` and contains the following fields:

    * `context` - the context of the environment; it can be nil (default context), :guard
      (inside a guard) or :match (inside a match)
    * `context_modules` - a list of modules defined in the current context
    * `file` - the current absolute file name as a binary
    * `function` - a tuple as {atom, integer}, where the first element is the function name and
      the second its arity; returns nil if not inside a function
    * `line` - the current line as an integer
    * `module` - the current module name
  """
  @type env :: %{
          context: Macro.Env.context(),
          context_modules: Macro.Env.context_modules(),
          file: Macro.Env.file(),
          function: Macro.Env.name_arity() | nil,
          line: Macro.Env.line(),
          module: module()
        }

  def exception(opts) do
    timeout = Keyword.fetch!(opts, :timeout)
    waitable = Keyword.fetch!(opts, :waitable)
    message = "timeout in #{WaitForIt.Waitable.wait_type(waitable)}: #{timeout}ms"

    params = %{
      message: message,
      timeout: timeout,
      waitable: waitable,
      last_value: opts[:last_value],
      env: make_env(opts[:env])
    }

    struct(__MODULE__, params)
  end

  @doc false
  @spec make_env(Macro.Env.t()) :: env()
  def make_env(%Macro.Env{} = env),
    do: Map.take(env, [:context, :context_modules, :file, :function, :line, :module])

  @spec make_env(any()) :: nil
  def make_env(_), do: nil
end
