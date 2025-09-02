defmodule MiniJobs.Router do
  use Plug.Router
  use Plug.ErrorHandler

  # Add conditional Plug.Debugger only in development
  if Mix.env() == :dev do
    use Plug.Debugger, otp_app: :mini_jobs
  end

  # Ajouter le pipeline de plugs
  plug Plug.Logger
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug MiniJobs.Plugs.RequestValidator
  plug Plug.MethodOverride
  plug Plug.Head
  plug :fetch_query_params_helper
  plug(:match)
  plug(:dispatch)

  # Health check
  get "/health" do
    json(conn, 200, %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: "0.1.0"
    })
  end

  # Jobs API
  post "/api/jobs", do: MiniJobs.API.JobsController.create(conn, conn.params)

  get "/api/jobs/:id", do: MiniJobs.API.JobsController.show(conn, conn.path_params)

  get "/api/jobs", do: MiniJobs.API.JobsController.index(conn, conn.params)

  # Jobs deletion
  delete "/api/jobs/:id", do: MiniJobs.API.JobsController.delete(conn, conn.path_params)
  
  # 404 handler
  match _ do
    json(conn, 404, %{
      error: "Not Found",
      message: "The requested resource was not found",
      path: conn.request_path,
      method: conn.method
    })
  end

  defp fetch_query_params_helper(conn, _opts) do
    Plug.Conn.fetch_query_params(conn, [])
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
    error_details = if Mix.env() == :dev do
      %{
        error: %{
          status: conn.status,
          kind: kind,
          reason: reason,
          stack: stack,
          message: Exception.format_stacktrace(stack)
        },
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    else
      %{
        error: %{
          status: conn.status,
          kind: kind,
          message: "Internal server error"
        },
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    end

    json(conn, conn.status, error_details)
  end

  defp json(conn, status, data) when is_integer(status) do
    body = MiniJobs.Json.encode(data)
    
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, body)
  end

end
