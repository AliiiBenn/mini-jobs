defmodule MiniJobs.API.JobsController do
  require Logger

  def create(conn) do
    Logger.info("Creating new job")

    # Simuler création d'un job
    job_id = generate_job_id()

    response = %{
      job_id: job_id,
      status: "queued",
      message: "Job created successfully"
    }

    conn
    |> put_status(:created)
    |> json(response)
  end

  def show(conn) do
    id = Map.get(conn.path_params, "id")
    Logger.info("Getting job #{id}")

    # Simuler récupération d'un job
    job = %{
      id: id,
      status: "running",
      command: "echo 'hello'",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      started_at: DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.to_iso8601()
    }

    conn
    |> json(job)
  end

  def index(conn) do
    Logger.info("Listing all jobs")

    # Simuler liste de jobs
    jobs = [
      %{
        id: generate_job_id(),
        status: "pending",
        command: "echo 'job 1'",
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      %{
        id: generate_job_id(),
        status: "completed",
        command: "echo 'job 2'",
        created_at: DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.to_iso8601(),
        completed_at: DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.to_iso8601()
      }
    ]

    response = %{
      jobs: jobs,
      total: length(jobs)
    }

    conn
    |> json(response)
  end

  defp generate_job_id do
    DateTime.utc_now()
    |> DateTime.to_unix(:microsecond)
    |> Integer.to_string()
  end

  defp json(conn, data) do
    body = Jason.encode!(data)

    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(conn.status || 200, body)
  end

  defp put_status(conn, status) do
    %{conn | status: status}
  end
end
