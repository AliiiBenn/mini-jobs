defmodule MiniJobs.Errors do
  require Logger

  @moduledoc """
  Centralized error response handling for the mini-jobs application.

  This module provides a consistent error response format across all endpoints
  and helper functions for common error scenarios.
  """

  @type error_kind :: :error | :throw | :exit
  @type error_status :: pos_integer()

  @doc """
  Error response structure.
  """
  @type t :: %{
          status: error_status(),
          kind: error_kind(),
          message: String.t(),
          timestamp: String.t(),
          error_id: String.t() | nil,
          details: map()
        }


  @spec new_error(error_status(), error_kind(), String.t(), map(), keyword()) :: map()
  def new_error(status, kind, message, details \\ %{}, opts \\ []) do
    error_id = Keyword.get(opts, :error_id, generate_error_id())
    request_id = Keyword.get(opts, :request_id, nil)

    # Get stack trace from current process if available
    stack = Keyword.get(opts, :stack, Process.info(self(), :current_stacktrace))

    error_response = %{
      status: status,
      kind: kind,
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      error_id: error_id,
      details: details
    }

    # Only include stack trace in development
    if Mix.env() == :dev and stack do
      _error_response = Map.put(error_response, :stack, Exception.format_stacktrace(stack))
    end

    # Add request ID if available
    if request_id do
      _error_response = Map.put(error_response, :request_id, request_id)
    end

    error_response
  end

  @doc """
  Create a bad request error (400).
  """
  @spec bad_request(String.t(), map(), keyword()) :: map()
  def bad_request(message, details \\ %{}, opts \\ []) do
    new_error(400, :error, message, details, opts)
  end

  @doc """
  Create an unauthorized error (401).
  """
  @spec unauthorized(String.t(), map(), keyword()) :: map()
  def unauthorized(message, details \\ %{}, opts \\ []) do
    new_error(401, :error, message, details, opts)
  end

  @doc """
  Create a forbidden error (403).
  """
  @spec forbidden(String.t(), map(), keyword()) :: map()
  def forbidden(message, details \\ %{}, opts \\ []) do
    new_error(403, :error, message, details, opts)
  end

  @doc """
  Create a not found error (404).
  """
  @spec not_found(String.t(), map(), keyword()) :: map()
  def not_found(message, details \\ %{}, opts \\ []) do
    new_error(404, :error, message, details, opts)
  end

  @doc """
  Create an unprocessable entity error (422).
  """
  @spec unprocessable_entity(String.t(), map(), keyword()) :: map()
  def unprocessable_entity(message, details \\ %{}, opts \\ []) do
    new_error(422, :error, message, details, opts)
  end

  @doc """
  Create an internal server error (500).
  """
  @spec internal_server_error(String.t(), map(), keyword()) :: map()
  def internal_server_error(message, details \\ %{}, opts \\ []) do
    new_error(500, :error, message, details, opts)
  end

  @doc """
  Create a service unavailable error (503).
  """
  @spec service_unavailable(String.t(), map(), keyword()) :: map()
  def service_unavailable(message, details \\ %{}, opts \\ []) do
    new_error(503, :error, message, details, opts)
  end

  @doc """
  Create a method not allowed error (405).
  """
  @spec method_not_allowed(String.t(), map(), keyword()) :: map()
  def method_not_allowed(message, details \\ %{}, opts \\ []) do
    new_error(405, :error, message, details, opts)
  end

  @doc """
  Create validation errors with field-specific details.
  """
  @spec validation_error([{String.t(), String.t()}], keyword()) :: map()
  def validation_error(errors, opts \\ []) do
    details = %{
      fields: Enum.into(errors, %{}, fn {field, message} -> {field, [message]} end)
    }

    message =
      case errors do
        [{_field, msg}] -> msg
        _ -> "Validation failed for #{length(errors)} field(s)"
      end

    bad_request(message, details, opts)
  end

  @doc """
  Handle not found errors for specific resources.
  """
  @spec resource_not_found(String.t(), String.t(), keyword()) :: map()
  def resource_not_found(resource_type, resource_id, opts \\ []) do
    message = "#{resource_type} with ID '#{resource_id}' not found"

    details = %{
      resource_type: resource_type,
      resource_id: resource_id
    }

    not_found(message, details, opts)
  end

  @doc """
  Handle generic errors from exceptions.
  """
  @spec exception_error(Exception.t(), keyword()) :: map()
  def exception_error(exception, opts \\ []) do
    message = Exception.message(exception)
    stack = Keyword.get(opts, :stack, Process.info(self(), :current_stacktrace))

    # Generic error for production
    if Mix.env() == :prod do
      internal_server_error(
        "Internal server error",
        %{"exception" => Exception.format_stacktrace(stack)},
        Keyword.put(opts, :stack, stack)
      )
    else
      # Include more details in development
      internal_server_error(
        message,
        %{"exception" => Exception.format_stacktrace(stack)},
        Keyword.put(opts, :stack, stack)
      )
    end
  end

  @doc """
  Generate a unique error ID.
  """
  @spec generate_error_id() :: String.t()
  def generate_error_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    random = :crypto.strong_rand_bytes(8) |> Base.encode64(padding: false)
    "#{timestamp}_#{random}"
  end

  @doc """
  Send an error response through a Plug connection.
  """
  @spec send_error(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def send_error(conn, error_response) do
    json_body = MiniJobs.Json.encode(error_response)

    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(error_response.status, json_body)
  end
end
