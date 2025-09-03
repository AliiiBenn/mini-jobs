defmodule MiniJobs.Json do
  require Logger

  @moduledoc """
  Safe JSON encoding with fallback for error cases.

  This module provides a safe wrapper around Jason.encode/1 that handles
  encoding errors gracefully without crashing the application.
  """

  @max_response_size 10 * 1024 * 1024  # 10MB
  @max_encoding_depth 100

  @doc """
  Safely encode data to JSON.

  Returns the JSON string on success, or a fallback error response
  if encoding fails.
  """
  def encode(data) when is_map(data) do
    try do
      # Try with depth limit to catch circular references
      Jason.encode!(data)
    rescue
      ArgumentError ->
        Logger.warning("JSON encoding failed for map, trying with sanitization")
        sanitize_and_encode(data, 0)

      error ->
        Logger.error("JSON encoding error: #{inspect(error)}")
        fallback_error_response()
    end
  end

  def encode(data) when is_list(data) do
    try do
      Jason.encode!(data)
    rescue
      ArgumentError ->
        Logger.warning("JSON encoding failed for list, trying with sanitization")
        sanitize_and_encode(data, 0)

      error ->
        Logger.error("JSON encoding error: #{inspect(error)}")
        fallback_error_response()
    end
  end

  def encode(data) do
    try do
      Jason.encode!(data)
    rescue
      ArgumentError ->
        Logger.warning("JSON encoding failed for data: #{inspect(data)}")
        sanitize_and_encode(data, 0)

      error ->
        Logger.error("JSON encoding error: #{inspect(error)}")
        fallback_error_response()
    end
  end

  # Sanitize data before encoding
  defp sanitize_and_encode(data, depth) when depth < @max_encoding_depth do
    sanitized = sanitize_data(data)
    Jason.encode!(sanitized)
  rescue
    ArgumentError ->
      # If still failing, convert to string representation
      Logger.warning("JSON encoding failed even after sanitization, converting to string")
      Jason.encode!(%{"error" => "Data too complex to encode"})
  end

  defp sanitize_and_encode(_data, depth) when depth >= @max_encoding_depth do
    # Max depth reached
    Logger.warning("Max encoding depth (#{@max_encoding_depth}) reached in JSON encoding")
    Jason.encode!(%{
      "error" => "Internal Server Error",
      "message" => "Data too complex to encode (max depth: #{@max_encoding_depth})",
      "max_size" => @max_response_size
    })
  end

  # Sanitize maps
  defp sanitize_data(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} ->
      {sanitize_key(k), sanitize_data(v)}
    end)
    |> Map.new()
  rescue
    ArgumentError ->
      # If map can't be sanitized, convert to string
      inspect(data)
  end

  # Sanitize lists
  defp sanitize_data(data) when is_list(data) do
    Enum.map(data, &sanitize_data/1)
  rescue
    ArgumentError ->
      # If list can't be sanitized, convert to string
      inspect(data)
  end

  # Sanitize atoms (convert to string)
  defp sanitize_data(atom) when is_atom(atom) do
    Atom.to_string(atom)
  end

  # Sanitize non-serializable terms
  defp sanitize_data(data) when is_pid(data) or is_reference(data) or is_port(data) do
    inspect(data)
  end

  # Sanitize functions
  defp sanitize_data(data) when is_function(data) do
    "function(#{arity(data)})"
  rescue
    # Some functions might not have inspectable arity
    ArgumentError ->
      "function"
  end

  # Keep original data for serializable types
  defp sanitize_data(data), do: data

  # Sanitize map keys
  defp sanitize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp sanitize_key(key), do: key

  # Get function arity (fallback)
  defp arity(function) do
    {arity, _} = Function.info(function, :arity)
    arity
  rescue
    ArgumentError ->
      0
  end

  # Fallback error response
  defp fallback_error_response do
    Jason.encode!(%{
      "error" => "Internal Server Error",
      "message" => "Failed to encode response",
      "max_size" => @max_response_size
    })
  end

  @doc """
  Check if data can be encoded without issues.

  Returns true if the data can be encoded, false otherwise.
  """
  def valid?(data) do
    try do
      Jason.encode!(data)
      true
    rescue
      ArgumentError -> false
    end
  end

  @doc """
  Get the size of encoded data without encoding.

  Useful for size limiting. Returns nil if size cannot be determined.
  """
  def estimated_size(data) when is_map(data) do
    # Rough estimate: 2 bytes per key, plus value sizes
    value_sizes = data
    |> Map.values()
    |> Enum.map(&estimated_size/1)
    |> Enum.sum()

    key_sizes = data
    |> Map.keys()
    |> Enum.map(fn key ->
      byte_size(Atom.to_string(key)) || 0
    end)
    |> Enum.sum()

    key_sizes + value_sizes + 4  # +4 for JSON structure
  rescue
    ArgumentError -> nil
  end

  def estimated_size(data) when is_list(data) do
    data
    |> Enum.map(&estimated_size/1)
    |> Enum.sum()
  rescue
    ArgumentError -> nil
  end

  def estimated_size(data) when is_binary(data) do
    byte_size(data) + 2  # +2 for JSON string quotes
  end

  def estimated_size(data) when is_integer(data) do
    byte_size(Integer.to_string(data))
  end

  def estimated_size(data) when is_boolean(data) do
    if data, do: byte_size("true"), else: byte_size("false")
  end

  def estimated_size(nil), do: 0

  def estimated_size(_data), do: nil
end
