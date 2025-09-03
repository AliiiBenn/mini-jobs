defmodule MiniJobs.JobValidation do
  require Logger
  alias MiniJobs.Errors

  @moduledoc """
  Centralized validation for mini-jobs application.

  This module provides validation schemas and functions for all job-related operations,
  ensuring consistent validation across the application.
  """

  @type validation_result :: {:ok, map()} | {:error, map()}
  @type validation_error :: {String.t(), String.t()}

  @doc """
  Supported job priorities.
  """
  def job_priorities, do: [:high, :normal, :low]

  @doc """
  Supported job statuses for filtering.
  """
  def job_statuses, do: [:queued, :running, :completed, :failed, :cancelled]

  @doc """
  Supported HTTP methods.
  """
  def supported_http_methods, do: ~w(GET POST PUT DELETE PATCH HEAD OPTIONS)

  @doc """
  Validate job creation parameters.
  
  ## Parameters
  - `params`: Map containing job parameters with keys:
    - `command` (required): Command string to execute
    - `priority` (optional): Priority level (:high, :normal, :low), defaults to :normal
    - `timeout` (optional): Timeout in milliseconds, defaults to 30000
    - `max_retries` (optional): Maximum retry count, defaults to 3
  
  ## Returns
  - {:ok, validated_params} if validation passes
  - {:error, errors} if validation fails
  """
  @spec validate_job_creation(map()) :: validation_result()
  def validate_job_creation(params) do
    errors = []
    |> validate_required_command(params)
    |> validate_priority(params)
    |> validate_timeout(params)
    |> validate_max_retries(params)

    case errors do
      [] ->
        {:ok, extract_validated_params(params)}
      errors ->
        {:error, Errors.validation_error(errors)}
    end
  end

  @doc """
  Validate query parameters for job listing.
  
  ## Parameters
  - `query_params`: Map containing query parameters with keys:
    - `limit` (optional): Maximum number of jobs to return (1-1000), defaults to 100
    - `offset` (optional): Number of jobs to skip for pagination (≥ 0), defaults to 0
    - `status` (optional): Filter by job status, one of [:queued, :running, :completed, :failed, :cancelled], defaults to all
  
  ## Returns
  - {:ok, validated_params} if validation passes
  - {:error, errors} if validation fails
  """
  @spec validate_query_params(map()) :: validation_result()
  def validate_query_params(query_params) do
    errors = []
    |> validate_limit(query_params)
    |> validate_offset(query_params)
    |> validate_status(query_params)

    case errors do
      [] ->
        {:ok, extract_validated_query_params(query_params)}
      errors ->
        {:error, Errors.validation_error(errors)}
    end
  end

  @doc """
  Validate job ID parameter.
  
  ## Parameters
  - `id`: Job ID to validate
  
  ## Returns
  - {:ok, id} if valid
  - {:error, %{message: String.t()}} if invalid
  
  ## Examples
      iex> validate_job_id("abc123")
      {:ok, "abc123"}
      
      iex> validate_job_id("")
      {:error, %{message: "Job ID cannot be empty"}}
      
      iex> validate_job_id(nil)
      {:error, %{message: "Job ID is required"}}
  """
  @spec validate_job_id(String.t() | nil) :: {:ok, String.t()} | {:error, map()}
  def validate_job_id(nil) do
    {:error, %{message: "Job ID is required"}}
  end

  def validate_job_id(id) when is_binary(id) do
    cond do
      String.length(id) == 0 ->
        {:error, %{message: "Job ID cannot be empty"}}
      true ->
        {:ok, id}
    end
  end

  def validate_job_id(_id) do
    {:error, %{message: "Job ID must be a string"}}
  end

  # Private validation helpers

  defp validate_required_command(errors, params) do
    case Map.get(params, "command") do
      nil ->
        [{:command, "Command is required"} | errors]
      command when is_binary(command) ->
        if String.trim(command) != "" do
          errors
        else
          [{:command, "Command must be a non-empty string"} | errors]
        end
      _ ->
        [{:command, "Command must be a non-empty string"} | errors]
    end
  end

  defp validate_priority(errors, params) do
    case Map.get(params, "priority") do
      nil ->
        # Use default, no error
        errors
      priority ->
        if is_binary(priority) do
          atom_priority = String.to_existing_atom(priority)
          if atom_priority in job_priorities() do
            errors
          else
            [{:priority, "Priority must be one of: #{inspect(job_priorities())}"} | errors]
          end
        else
          if priority in job_priorities() do
            errors
          else
            [{:priority, "Priority must be one of: #{inspect(job_priorities())}"} | errors]
          end
        end
    end
  end

  defp validate_timeout(errors, params) do
    case Map.get(params, "timeout") do
      nil ->
        # Use default, no error
        errors
      timeout when is_integer(timeout) and timeout > 0 ->
        errors
      timeout when is_binary(timeout) ->
        case Integer.parse(timeout) do
          {num, ""} when num > 0 ->
            errors
          _ ->
            [{:timeout, "Timeout must be a positive integer"} | errors]
        end
      _ ->
        [{:timeout, "Timeout must be a positive integer"} | errors]
    end
  end

  defp validate_max_retries(errors, params) do
    case Map.get(params, "max_retries") do
      nil ->
        # Use default, no error
        errors
      max_retries when is_integer(max_retries) and max_retries >= 0 ->
        errors
      max_retries when is_binary(max_retries) ->
        case Integer.parse(max_retries) do
          {num, ""} when num >= 0 ->
            errors
          _ ->
            [{:max_retries, "Max retries must be a non-negative integer"} | errors]
        end
      _ ->
        [{:max_retries, "Max retries must be a non-negative integer"} | errors]
    end
  end

  defp validate_limit(errors, query_params) do
    case get_in(query_params, ["limit"]) do
      nil ->
        # Use default, no error
        errors
      limit when is_integer(limit) ->
        cond do
          limit < 1 ->
            [{:limit, "Limit must be at least 1"} | errors]
          limit > 1000 ->
            [{:limit, "Limit must not exceed 1000"} | errors]
          true ->
            errors
        end
      limit when is_binary(limit) ->
        case Integer.parse(limit) do
          {num, ""} ->
            cond do
              num < 1 ->
                [{:limit, "Limit must be at least 1"} | errors]
              num > 1000 ->
                [{:limit, "Limit must not exceed 1000"} | errors]
              true ->
                errors
            end
          _ ->
            [{:limit, "Limit must be a valid integer"} | errors]
        end
      _ ->
        [{:limit, "Limit must be an integer"} | errors]
    end
  end

  defp validate_offset(errors, query_params) do
    case get_in(query_params, ["offset"]) do
      nil ->
        # Use default, no error
        errors
      offset when is_integer(offset) ->
        if offset >= 0 do
          errors
        else
          [{:offset, "Offset must be a non-negative integer"} | errors]
        end
      offset when is_binary(offset) ->
        case Integer.parse(offset) do
          {num, ""} when num >= 0 ->
            errors
          _ ->
            [{:offset, "Offset must be a non-negative integer"} | errors]
        end
      _ ->
        [{:offset, "Offset must be an integer"} | errors]
    end
  end

  defp validate_status(errors, query_params) do
    case get_in(query_params, ["status"]) do
      nil ->
        # Use default, no error
        errors
      status when is_atom(status) ->
        if status in [:queued, :running, :completed, :failed, :cancelled] do
          errors
        else
          [{:status, "Status must be one of: [:queued, :running, :completed, :failed, :cancelled]"} | errors]
        end
      status when is_binary(status) ->
        case String.to_existing_atom(status) do
          atom when atom in [:queued, :running, :completed, :failed, :cancelled] ->
            errors
          _ ->
            [{:status, "Status must be one of: [:queued, :running, :completed, :failed, :cancelled]"} | errors]
        end
      _ ->
        [{:status, "Status must be one of: [:queued, :running, :completed, :failed, :cancelled]"} | errors]
    end
  end

  defp extract_validated_params(params) do
    %{
      command: Map.get(params, "command"),
      priority: normalize_priority(Map.get(params, "priority")),
      timeout: normalize_timeout(Map.get(params, "timeout")),
      max_retries: normalize_max_retries(Map.get(params, "max_retries"))
    }
  end

  # Helper to normalize priority with validation
  defp normalize_priority(nil), do: :normal
  defp normalize_priority(priority) when is_atom(priority), do: priority
  defp normalize_priority(priority) when is_binary(priority), do: String.to_existing_atom(priority)

  # Helper to normalize timeout with validation
  defp normalize_timeout(nil), do: 30_000
  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
  defp normalize_timeout(timeout) when is_binary(timeout) do
    case Integer.parse(timeout) do
      {num, ""} when num > 0 -> num
      _ -> 30_000  # fallback to default
    end
  end
  defp normalize_timeout(_), do: 30_000  # fallback to default

  # Helper to normalize max_retries with validation
  defp normalize_max_retries(nil), do: 3
  defp normalize_max_retries(max_retries) when is_integer(max_retries) and max_retries >= 0, do: max_retries
  defp normalize_max_retries(max_retries) when is_binary(max_retries) do
    case Integer.parse(max_retries) do
      {num, ""} when num >= 0 -> num
      _ -> 3  # fallback to default
    end
  end
  defp normalize_max_retries(_), do: 3  # fallback to default

  defp extract_validated_query_params(query_params) do
    %{
      limit: normalize_limit(get_in(query_params, ["limit"])),
      offset: normalize_offset(get_in(query_params, ["offset"])),
      status: normalize_status(get_in(query_params, ["status"]))
    }
  end

  # Helper to normalize limit with validation
  defp normalize_limit(nil), do: 100
  defp normalize_limit(limit) when is_integer(limit) do
    cond do
      limit < 1 -> 1
      limit > 1000 -> 1000
      true -> limit
    end
  end
  defp normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {num, ""} -> normalize_limit(num)
      _ -> 100  # fallback to default
    end
  end
  defp normalize_limit(_), do: 100  # fallback to default

  # Helper to normalize offset with validation
  defp normalize_offset(nil), do: 0
  defp normalize_offset(offset) when is_integer(offset) and offset >= 0, do: offset
  defp normalize_offset(offset) when is_binary(offset) do
    case Integer.parse(offset) do
      {num, ""} when num >= 0 -> num
      _ -> 0  # fallback to default
    end
  end
  defp normalize_offset(_), do: 0  # fallback to default

  # Helper to normalize status with validation
  defp normalize_status(nil), do: nil
  defp normalize_status(status) when is_atom(status) do
    valid_statuses = [:queued, :running, :completed, :failed, :cancelled]
    if status in valid_statuses, do: status, else: nil
  end
  defp normalize_status(status) when is_binary(status) do
    case String.to_existing_atom(status) do
      atom ->
        valid_statuses = [:queued, :running, :completed, :failed, :cancelled]
        if atom in valid_statuses, do: atom, else: nil
    end
  rescue
    ArgumentError -> nil
  end
  defp normalize_status(_), do: nil  # fallback to default
end