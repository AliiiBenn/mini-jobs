defmodule MiniJobsTest do
  use ExUnit.Case
  doctest MiniJobs

  test "greets the world" do
    assert MiniJobs.hello() == :world
  end
end
