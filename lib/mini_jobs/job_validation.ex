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
  - `params`: Map containing job parameters
  
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
  - `query_params`: Map containing query parameters
  
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
      command when is_binary(command) and String.trim(command) != "" ->
        errors
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
        if priority in job_priorities() do
          errors
        else
          [{:priority, "Priority must be one of: #{inspect(job_priorities())}"} | errors]
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
        if status in job_statuses() do
          errors
        else
          [{:status, "Status must be one of: #{inspect(job_statuses())}"} | errors]
        end
      status when is_binary(status) ->
        case String.to_existing_atom(status) do
          atom when atom in job_statuses() ->
            errors
          _ ->
            [{:status, "Status must be one of: #{inspect(job_statuses())}"} | errors]
        end
      _ ->
        [{:status, "Status must be one of: #{inspect(job_statuses())}"} | errors]
    end
  end

  defp extract_validated_params(params) do
    %{
      command: Map.get(params, "command"),
      priority: Map.get(params, "priority") || :normal,
      timeout: Map.get(params, "timeout") || 30_000,
      max_retries: Map.get(params, "max_retries") || 3
    }
  end

  defp extract_validated_query_params(query_params) do
    %{
      limit: parse_integer(get_in(query_params, ["limit"]) || "100", 100)
        |> min(1000)
        |> max(1),
      offset: parse_integer(get_in(query_params, ["offset"]) || "0", 0)
        |> max(0),
      status: case get_in(query_params, ["status"]) do
        nil -> nil
        s when is_binary(s) -> String.to_existing_atom(s)
        s when is_atom(s) -> s
      end
    }
  end

  defp parse_integer(binary, default) when is_binary(binary) do
    case Integer.parse(binary) do
      {num, ""} -> num
      _ -> default
    end
  end

  defp parse_integer(integer, _default) when is_integer(integer), do: integer
end