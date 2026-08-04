defmodule WaitForIt.EnvTest do
  @moduledoc """
  Tests for the trimmed `env` that waits carry (issue #22).

  A full `__ENV__` is around 1000 words, almost all of it the calling module's
  import table, and it was being embedded in the caller's compiled module once
  per wait, copied into the signal registry, and copied again by every telemetry
  handler that forwarded metadata off-process.

  Trimming happens at macro expansion, so the fat term is never emitted. The
  value stays a real `%Macro.Env{}` where it is passed down, because
  `Macro.Env.stacktrace/1` is called on it to reraise at the caller's location.
  """

  use ExUnit.Case, async: false

  import WaitForIt

  @kept [:context, :context_modules, :file, :function, :line, :module]

  def relay(event, measurements, metadata, pid),
    do: send(pid, {:telemetry, event, measurements, metadata})

  defp attach do
    handler = "env-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler,
      [[:wait_for_it, :wait, :start], [:wait_for_it, :wait, :stop]],
      &__MODULE__.relay/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  describe "telemetry metadata env" do
    setup do
      attach()
      :ok
    end

    test "carries exactly the retained fields" do
      wait(true, timeout: 50)

      assert_received {:telemetry, [:wait_for_it, :wait, :stop], _meas, meta}
      assert meta.env |> Map.keys() |> Enum.sort() == @kept
    end

    test "is a plain map, not a Macro.Env struct" do
      # It is data crossing a boundary; a struct would imply the other fields are
      # populated.
      wait(true, timeout: 50)

      assert_received {:telemetry, [:wait_for_it, :wait, :stop], _meas, meta}
      assert is_map(meta.env)
      refute is_struct(meta.env)
    end

    test "points at this call site" do
      line = __ENV__.line + 1
      wait(true, timeout: 50)

      assert_received {:telemetry, [:wait_for_it, :wait, :stop], _meas, meta}
      assert meta.env.module == __MODULE__
      assert meta.env.line == line
      assert meta.env.file == __ENV__.file
      assert {name, _arity} = meta.env.function
      assert is_atom(name)
    end

    test "does not carry the caller's import table" do
      # The regression this exists for: `:functions`, `:macros`, and `:requires`
      # are the bulk of a full env and are of no use to a handler.
      wait(true, timeout: 50)

      assert_received {:telemetry, [:wait_for_it, :wait, :stop], _meas, meta}

      refute Map.has_key?(meta.env, :functions)
      refute Map.has_key?(meta.env, :macros)
      refute Map.has_key?(meta.env, :requires)
      refute Map.has_key?(meta.env, :aliases)
      refute Map.has_key?(meta.env, :lexical_tracker)
      refute Map.has_key?(meta.env, :versioned_vars)
    end

    test "is a small fraction of a full env in the same module" do
      # Calibrated against this module's own `__ENV__` rather than an absolute
      # word count, so the assertion stays meaningful as the module's imports
      # change. A full env here is on the order of 1000 words.
      wait(true, timeout: 50)

      assert_received {:telemetry, [:wait_for_it, :wait, :stop], _meas, meta}

      full = :erts_debug.flat_size(__ENV__)
      trimmed = :erts_debug.flat_size(meta.env)

      assert trimmed * 10 < full, "expected #{trimmed} words to be <1/10th of #{full}"
    end

    test "the start event carries the same env as the stop event" do
      wait(true, timeout: 50)

      assert_received {:telemetry, [:wait_for_it, :wait, :start], _meas, start_meta}
      assert_received {:telemetry, [:wait_for_it, :wait, :stop], _meas, stop_meta}
      assert start_meta.env == stop_meta.env
    end
  end

  describe "TimeoutError env agrees with telemetry" do
    test "both carry the same shape and the same values" do
      attach()

      error =
        try do
          wait!(false, timeout: 20, interval: 1)
        rescue
          e in WaitForIt.TimeoutError -> e
        end

      assert_received {:telemetry, [:wait_for_it, :wait, :stop], _meas, meta}

      # The two paths disagreed before: TimeoutError trimmed, telemetry did not.
      assert error.env == meta.env
      assert error.env |> Map.keys() |> Enum.sort() == @kept
    end
  end

  # Opaque to the type checker: returns `:never` at runtime, but Elixir 1.20 would
  # otherwise infer the exact type `:never` and flag the wait pattern as a clause
  # that can never match. See the Troubleshooting guide.
  defp never, do: Process.get(:__wait_for_it_unset__, :never)

  defp timing_out_match_wait do
    match_wait({:ok, _v}, never(), timeout: 20, interval: 1, on_timeout: :raise_last_value)
  end

  describe "reraise still points at the caller" do
    test "a match_wait timeout raises MatchError at the call site" do
      # `Macro.Env.stacktrace/1` is called on the trimmed env for this. It reads
      # only module/function/file/line, all of which survive the trim.
      {error, stacktrace} =
        try do
          timing_out_match_wait()
          flunk("expected a MatchError")
        rescue
          e in MatchError -> {e, __STACKTRACE__}
        end

      assert %MatchError{} = error
      assert [{__MODULE__, :timing_out_match_wait, _arity, location} | _] = stacktrace
      assert location[:line] == match_wait_source_line()
      assert to_string(location[:file]) =~ "env_test.exs"
    end
  end

  # Found by scanning the source rather than recorded as an offset from a module
  # attribute, which drifts the moment the formatter reflows anything above it.
  defp match_wait_source_line do
    index =
      __ENV__.file
      |> File.read!()
      |> String.split("\n")
      |> Enum.find_index(&String.contains?(&1, "match_wait({:ok, _v}, never()"))

    index + 1
  end

  describe "WaitForIt.Env" do
    test "trim/1 keeps a real Macro.Env so stacktrace/1 still works" do
      full = __ENV__
      trimmed = WaitForIt.Env.trim(full)

      assert %Macro.Env{} = trimmed
      assert Macro.Env.stacktrace(trimmed) == Macro.Env.stacktrace(full)
    end

    test "trim/1 drops the bulky fields" do
      trimmed = WaitForIt.Env.trim(__ENV__)

      assert trimmed.functions == []
      assert trimmed.macros == []
      assert trimmed.requires == []
      assert :erts_debug.flat_size(trimmed) < :erts_debug.flat_size(__ENV__)
    end

    test "to_map/1 returns nil for a non-env" do
      assert WaitForIt.Env.to_map(nil) == nil
      assert WaitForIt.Env.to_map(:nope) == nil
    end
  end
end
