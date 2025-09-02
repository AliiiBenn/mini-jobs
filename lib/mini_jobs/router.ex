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
    error = MiniJobs.Errors.resource_not_found(
      "Resource", 
      conn.request_path, 
      details: %{method: conn.method}
    )
    MiniJobs.Errors.send_error(conn, error)
  end

  defp fetch_query_params_helper(conn, _opts) do
    Plug.Conn.fetch_query_params(conn, [])
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
    # Create exception
    exception = {kind, reason, stack}
    
    # Create standardized error response
    error_response = MiniJobs.Errors.exception_error(
      exception,
      request_id: get_in(conn, [:private, :request_id])
    )

    MiniJobs.Errors.send_error(conn, error_response)
  end

  defp json(conn, status, data) when is_integer(status) do
    body = MiniJobs.Json.encode(data)
    
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, body)
  end

end
