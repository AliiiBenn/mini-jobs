defmodule MiniJobs.Router do
  use Plug.Router

  # Ajouter le pipeline de plugs
  plug MiniJobs.Plugs.Logger
  plug MiniJobs.Plugs.JSONParser
  plug MiniJobs.Plugs.RequestValidator
  plug(:match)
  plug(:dispatch)

  # Health check
  match "/health", via: :get do
    json(conn, 200, %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: "0.1.0"
    })
  end

  # Jobs API
  match "/api/jobs", via: :post do
    json(conn, :created, %{
      job_id: generate_job_id(),
      status: "queued",
      message: "Job created successfully"
    })
  end

  match "/api/jobs/:id", via: :get do
    id = conn.path_params["id"]
    json(conn, 200, %{
      id: id,
      status: "running",
      command: "echo 'hello'",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      started_at: DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.to_iso8601()
    })
  end

  match "/api/jobs", via: :get do
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

    json(conn, 200, %{
      jobs: jobs,
      total: length(jobs)
    })
  end

  # 404 handler
  match _ do
    json(conn, 404, %{
      error: "Not Found",
      message: "The requested resource was not found",
      path: conn.request_path,
      method: conn.method
    })
  end

  defp json(conn, status, data) do
    body = Jason.encode!(data)
    
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  defp generate_job_id do
    DateTime.utc_now() 
    |> DateTime.to_unix(:microsecond)
    |> Integer.to_string()
  end
end
