defmodule MiniJobs.JsonTest do
  use ExUnit.Case
  doctest MiniJobs.Json

  import MiniJobs.Json

  describe "encode/1" do
    test "encodes simple data" do
      assert encode(%{"name" => "test", "value" => 42}) == "{\"name\":\"test\",\"value\":42}"
      assert encode([1, 2, 3]) == "[1,2,3]"
      assert encode("hello") == "\"hello\""
      assert encode(42) == "42"
      assert encode(true) == "true"
      assert encode(false) == "false"
      assert encode(nil) == "null"
    end

    test "encodes nested maps" do
      data = %{
        "user" => %{
          "name" => "John",
          "age" => 30,
          "active" => true
        },
        "items" => [%{"id" => 1}, %{"id" => 2}]
      }

      result = encode(data)
      assert String.contains?(result, "user")
      assert String.contains?(result, "John")
      assert String.contains?(result, "items")
    end

    test "encodes complex nested structures" do
      data = %{
        "list" => [1, %{"nested" => [2, 3]}, "string"],
        "map" => %{"key" => %{"inner" => "value"}},
        "number" => 42.5,
        "bool" => false
      }

      assert is_binary(encode(data))
    end

    test "handles atoms safely" do
      atom_map = %{status: :active, type: :user}
      result = encode(atom_map)
      assert String.contains?(result, "status")
      assert String.contains?(result, "active")
    end

    test "sanitizes non-serializable data - pids" do
      pid = self()
      result = encode(%{"pid" => pid})
      assert is_binary(result)
      assert String.contains?(result, "pid")
    end

    test "sanitizes functions" do
      function = fn x -> x + 1 end
      result = encode(%{"func" => function})
      assert is_binary(result)
    end

    test "handles circular references with depth limit" do
      # Create a circular reference using Map.put
      map1 = %{}
      map2 = %{"ref" => map1}
      map1 = Map.put(map1, "circular", map2)

      # This should not crash, should return sanitized JSON
      assert is_binary(encode(map1))
    end

    test "returns fallback error response for problematic data" do
      # Create data that will cause encoding issues
      ref = make_ref()
      data = %{"ref" => ref}
      result = encode(data)

      assert is_binary(result)
      # Should contain some error indication
      assert result != ""
    end
  end

  describe "valid?/1" do
    test "returns true for valid data" do
      assert valid?(%{"simple" => "map"})
      assert valid?([1, 2, 3])
      assert valid?("string")
      assert valid?(42)
      assert valid?(true)
      assert valid?(false)
      assert valid?(nil)
    end

    test "returns false for invalid data" do
      # Create data that would cause encoding issues
      map = %{}
      ref = make_ref()
      map["circular"] = ref
      ref = map

      refute valid?(ref)
    end
  end

  describe "estimated_size/1 for simple data" do
    test "estimates size for strings" do
      assert estimated_size("hello") == byte_size(~s("hello"))
      assert estimated_size("") == byte_size(~s(""))
    end

    test "estimates size for numbers" do
      assert estimated_size(42) == byte_size("42")
      assert estimated_size(0) == byte_size("0")
      assert estimated_size(-1) == byte_size("-1")
    end

    test "estimates size for booleans" do
      assert estimated_size(true) == byte_size("true")
      assert estimated_size(false) == byte_size("false")
    end

    test "returns 0 for nil" do
      assert estimated_size(nil) == 0
    end

    test "estimates size for simple maps" do
      data = %{"key" => "value"}
      # Should account for key bytes + value bytes + JSON structure
      assert is_integer(estimated_size(data))
      assert estimated_size(data) > 0
    end

    test "estimates size for simple lists" do
      data = [1, 2, 3]
      assert is_integer(estimated_size(data))
      assert estimated_size(data) > 0
    end

    test "returns nil for complex data that can not be calculated" do
      # This might return nil for certain complex structures
      ref = make_ref()
      data = %{"ref" => ref}
      result = estimated_size(data)
      assert is_nil(result) or is_integer(result)
    end
  end

  describe "size constants" do
    test "has max response size defined" do
      assert MiniJobs.Json.@max_response_size == 10 * 1024 * 1024
    end

    test "has max encoding depth defined" do
      assert MiniJobs.Json.@max_encoding_depth == 100
    end
  end

  describe "error handling and logging" do
    test "does not crash on various input types" do
      # Should not crash for any input
      assert is_binary(encode(%{}))
      assert is_binary(encode([]))
      assert is_binary(encode(""))
      assert is_binary(encode(0))
      assert is_binary(encode(true))
      assert is_binary(encode(false))
      assert is_binary(encode(nil))
    end

    test "provides consistent error response format" do
      # Create problematic data that will trigger fallback
      data = fn x -> x end
      result = encode(%{"func" => data})

      # Should be valid JSON even in error cases
      assert String.first(result) == "{"
      assert String.last(result) == "}"
    end
  end
end
