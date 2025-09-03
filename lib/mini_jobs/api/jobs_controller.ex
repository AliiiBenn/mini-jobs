defmodule MiniJobs.API.JobsController do
  require Logger

  # Generate request ID for error tracking
  defp generate_request_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{timestamp}_#{random}"
  end

  def create(conn, _params) do
    request_id = generate_request_id()
    conn = Plug.Conn.put_private(conn, :request_id, request_id)
    Logger.info("Received job creation request [#{request_id}]")
    Logger.debug("Body params: #{inspect(conn.body_params)}")
    
    # Validate required fields
    case conn.body_params do
      %{"command" => command} when is_binary(command) ->
        # Optional parameters with defaults
        job_data = %{
          command: command,
          priority: Map.get(conn.body_params, "priority", "normal") |> String.to_atom(),
          timeout: Map.get(conn.body_params, "timeout", 30_000),
          max_retries: Map.get(conn.body_params, "max_retries", 3)
        }

        # Validate priority
        if job_data.priority not in [:high, :normal, :low] do
          MiniJobs.Errors.bad_request(
            "Invalid priority. Must be one of: high, normal, low", 
            %{provided_priority: job_data.priority},
            request_id: request_id
          ) |> MiniJobs.Errors.send_error(conn)
        else
          Logger.debug("Job data: #{inspect(job_data)}")
          # Enqueue the job
          case MiniJobs.QueueManager.enqueue_job(job_data) do
            {:ok, job_id} ->
              conn
              |> Plug.Conn.put_status(:created)
              |> json(%{
                job_id: job_id,
                status: "queued",
                message: "Job created successfully"
              })
            error ->
              Logger.error("Failed to enqueue job [#{request_id}]: #{inspect(error)}")
              MiniJobs.Errors.internal_server_error(
                "Failed to enqueue job", 
                %{error: inspect(error), job_data: job_data},
                request_id: request_id
              ) |> MiniJobs.Errors.send_error(conn)
          end
        end
      _ ->
        MiniJobs.Errors.bad_request(
          "Missing required field: command", 
          %{received_params: conn.body_params},
          request_id: request_id
        ) |> MiniJobs.Errors.send_error(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    request_id = generate_request_id()
    conn = Plug.Conn.put_private(conn, :request_id, request_id)
    Logger.info("Getting job #{id} [#{request_id}]")

    case MiniJobs.QueueManager.get_job(id) do
      {:ok, job} ->
        response = %{
          id: job.id,
          command: job.command,
          priority: job.priority,
          status: job.status,
          created_at: job.created_at |> DateTime.to_iso8601(),
          started_at: if(job.started_at, do: job.started_at |> DateTime.to_iso8601()),
          completed_at: if(job.completed_at, do: job.completed_at |> DateTime.to_iso8601()),
          result: job.result,
          error: job.error,
          timeout: job.timeout,
          retry_count: job.retry_count,
          max_retries: job.max_retries
        }
        
        json(conn, response)
      {:error, :job_not_found} ->
        MiniJobs.Errors.resource_not_found(
          "Job", 
          id, 
          request_id: request_id
        ) |> MiniJobs.Errors.send_error(conn)
    end
  end

  def index(conn, _params) do
    request_id = generate_request_id()
    conn = Plug.Conn.put_private(conn, :request_id, request_id)
    Logger.info("Listing all jobs [#{request_id}]")
    
    # Parse query parameters
    status = case get_in(conn.query_params, ["status"]) do
      nil -> nil
      s -> s |> String.to_atom()
    end
    
    limit = case Integer.parse(get_in(conn.query_params, ["limit"]) || "100") do
      {n, _} -> min(n, 1000)  # Cap at 1000
      _ -> 100
    end
    
    offset = case Integer.parse(get_in(conn.query_params, ["offset"]) || "0") do
      {n, _} -> n
      _ -> 0
    end

    # Validate query parameters
    cond do
      limit < 1 or limit > 1000 ->
        MiniJobs.Errors.bad_request(
          "Limit must be between 1 and 1000",
          %{provided_limit: limit, valid_range: "1-1000"},
          request_id: request_id
        ) |> MiniJobs.Errors.send_error(conn)
      
      offset < 0 ->
        MiniJobs.Errors.bad_request(
          "Offset must be a positive number",
          %{provided_offset: offset, valid_range: "≥ 0"},
          request_id: request_id
        ) |> MiniJobs.Errors.send_error(conn)
      
      status != nil and status not in [:queued, :running, :completed, :failed, :cancelled] ->
        MiniJobs.Errors.bad_request(
          "Invalid status filter",
          %{provided_status: status, valid_values: [:queued, :running, :completed, :failed, :cancelled]},
          request_id: request_id
        ) |> MiniJobs.Errors.send_error(conn)
      
      true ->
        # Get jobs with filters
        job_list = MiniJobs.QueueManager.list_jobs(status: status, limit: limit, offset: offset)

        response = %{
          jobs: Enum.map(job_list.jobs, fn {job_id, job} ->
            %{
              id: job_id,
              command: job.command,
              priority: job.priority,
              status: job.status,
              created_at: job.created_at |> DateTime.to_iso8601(),
              started_at: if(job.started_at, do: job.started_at |> DateTime.to_iso8601()),
              completed_at: if(job.completed_at, do: job.completed_at |> DateTime.to_iso8601())
            }
          end),
          total: job_list.total,
          limit: limit,
          offset: offset
        }

        json(conn, response)
    end
  end

  def delete(conn, %{"id" => id}) do
    request_id = generate_request_id()
    conn = Plug.Conn.put_private(conn, :request_id, request_id)
    Logger.info("Deleting job #{id} [#{request_id}]")
    
    # First check if job exists
    case MiniJobs.QueueManager.get_job(id) do
      {:ok, _job} ->
        # Update status to cancelled
        case MiniJobs.QueueManager.update_job_status(id, :cancelled) do
          {:ok, _cancelled_job} ->
            json(conn, %{
              job_id: id,
              status: "cancelled",
              message: "Job cancelled successfully"
            })
          {:error, reason} ->
            Logger.error("Failed to cancel job #{id} [#{request_id}]: #{inspect(reason)}")
            MiniJobs.Errors.internal_server_error(
              "Failed to cancel job", 
              %{job_id: id, reason: inspect(reason)},
              request_id: request_id
            ) |> MiniJobs.Errors.send_error(conn)
        end
      {:error, :job_not_found} ->
        MiniJobs.Errors.resource_not_found(
          "Job", 
          id, 
          request_id: request_id
        ) |> MiniJobs.Errors.send_error(conn)
    end
  end

  # Private helpers

  defp json(conn, data) do
    body = MiniJobs.Json.encode(data)
    
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(200, body)
  end

  # send_error/3 is no longer needed - using MiniJobs.Errors directly

  # For testing purposes - clear all jobs
  def clear_all_jobs() do
    MiniJobs.QueueManager.clear_queue()
    :ok
  end
end