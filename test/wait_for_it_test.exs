defmodule WaitForItTest do
  use ExUnit.Case
  doctest WaitForIt

  test "greets the world" do
    assert WaitForIt.hello() == :world
  end
end
