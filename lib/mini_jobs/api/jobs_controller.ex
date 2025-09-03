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
    
    # Validate job creation parameters using centralized validation
    case MiniJobs.JobValidation.validate_job_creation(conn.body_params) do
      {:ok, job_data} ->
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
      {:error, error} ->
        Logger.warning("Job creation validation failed [#{request_id}]: #{inspect(error)}")
        MiniJobs.Errors.send_error(conn, error)
    end
  end
  end

  def show(conn, %{"id" => id}) do
    request_id = generate_request_id()
    conn = Plug.Conn.put_private(conn, :request_id, request_id)
    Logger.info("Getting job #{id} [#{request_id}]")

    # Validate job ID using centralized validation
    case MiniJobs.JobValidation.validate_job_id(id) do
      {:ok, validated_id} ->
        case MiniJobs.QueueManager.get_job(validated_id) do
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
              validated_id, 
              request_id: request_id
            ) |> MiniJobs.Errors.send_error(conn)
        end
      {:error, _error} ->
        MiniJobs.Errors.bad_request("Invalid job ID format", request_id: request_id)
        |> MiniJobs.Errors.send_error(conn)
    end
  end

  def index(conn, _params) do
    request_id = generate_request_id()
    conn = Plug.Conn.put_private(conn, :request_id, request_id)
    Logger.info("Listing all jobs [#{request_id}]")
    
    # Validate query parameters using centralized validation
    case MiniJobs.JobValidation.validate_query_params(conn.query_params) do
      {:ok, query_params} ->
        # Get jobs with validated filters
        job_list = MiniJobs.QueueManager.list_jobs(
          status: query_params.status, 
          limit: query_params.limit, 
          offset: query_params.offset
        )

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
          limit: query_params.limit,
          offset: query_params.offset
        }

        json(conn, response)
      {:error, error} ->
        Logger.warning("Query parameter validation failed [#{request_id}]: #{inspect(error)}")
        MiniJobs.Errors.send_error(conn, error)
    end
  end

  def delete(conn, %{"id" => id}) do
    request_id = generate_request_id()
    conn = Plug.Conn.put_private(conn, :request_id, request_id)
    Logger.info("Deleting job #{id} [#{request_id}]")
    
    # Validate job ID using centralized validation
    case MiniJobs.JobValidation.validate_job_id(id) do
      {:ok, validated_id} ->
        # First check if job exists
        case MiniJobs.QueueManager.get_job(validated_id) do
          {:ok, _job} ->
            # Update status to cancelled
            case MiniJobs.QueueManager.update_job_status(validated_id, :cancelled) do
              {:ok, _cancelled_job} ->
                json(conn, %{
                  job_id: validated_id,
                  status: "cancelled",
                  message: "Job cancelled successfully"
                })
              {:error, reason} ->
                Logger.error("Failed to cancel job #{validated_id} [#{request_id}]: #{inspect(reason)}")
                MiniJobs.Errors.internal_server_error(
                  "Failed to cancel job", 
                  %{job_id: validated_id, reason: inspect(reason)},
                  request_id: request_id
                ) |> MiniJobs.Errors.send_error(conn)
            end
          {:error, :job_not_found} ->
            MiniJobs.Errors.resource_not_found(
              "Job", 
              validated_id, 
              request_id: request_id
            ) |> MiniJobs.Errors.send_error(conn)
        end
      {:error, _error} ->
        MiniJobs.Errors.bad_request("Invalid job ID format", request_id: request_id)
        |> MiniJobs.Errors.send_error(conn)
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