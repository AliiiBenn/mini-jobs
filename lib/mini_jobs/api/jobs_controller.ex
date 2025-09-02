defmodule MiniJobs.API.JobsController do
  require Logger

  def create(conn, _params) do
    Logger.info("Received job creation request")
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
          send_error(conn, 400, "Invalid priority. Must be one of: high, normal, low")
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
              Logger.error("Failed to enqueue job: #{inspect(error)}")
              send_error(conn, 500, "Failed to enqueue job")
          end
        end
      _ ->
        send_error(conn, 400, "Missing required field: command")
    end
  end

  def show(conn, %{"id" => id}) do
    Logger.info("Getting job #{id}")

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
        send_error(conn, 404, "Job not found")
    end
  end

  def index(conn, _params) do
    Logger.info("Listing all jobs")
    
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

  def delete(conn, %{"id" => id}) do
    Logger.info("Deleting job #{id}")
    
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
            Logger.error("Failed to cancel job #{id}: #{inspect(reason)}")
            send_error(conn, 500, "Failed to cancel job")
        end
      {:error, :job_not_found} ->
        send_error(conn, 404, "Job not found")
    end
  end

  # Private helpers

  defp json(conn, data) do
    body = Jason.encode!(data)
    
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(200, body)
  end

  defp send_error(conn, status_code, message) do
    error = %{
      error: "error",
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    body = Jason.encode!(error)
    
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status_code, body)
  end

  # For testing purposes - clear all jobs
  def clear_all_jobs() do
    MiniJobs.QueueManager.clear_queue()
    :ok
  end
end