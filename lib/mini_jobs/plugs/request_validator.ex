defmodule MiniJobs.Plugs.RequestValidator do
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    validate_request(conn)
  end

  defp validate_request(conn) do
    # Vérifier si la méthode est supportée
    supported_methods = ~w(GET POST PUT DELETE PATCH HEAD OPTIONS)
    
    if conn.method not in supported_methods do
      Logger.warning("Unsupported HTTP method: #{conn.method}")
      send_error_response(conn, :method_not_allowed, "Method Not Allowed")
    else
      conn
    end
  rescue
    error ->
      Logger.error("Error in RequestValidator plug: #{inspect(error)}")
      conn
    end

  defp send_error_response(conn, status, message) do
    error = case status do
      400 -> MiniJobs.Errors.bad_request(message, %{})
      401 -> MiniJobs.Errors.unauthorized(message, %{})
      403 -> MiniJobs.Errors.forbidden(message, %{})
      404 -> MiniJobs.Errors.not_found(message, %{})
      405 -> MiniJobs.Errors.method_not_allowed(message, %{})
      500 -> MiniJobs.Errors.internal_server_error(message, %{})
      _ -> MiniJobs.Errors.internal_server_error(message, %{})
    end
    
    MiniJobs.Errors.send_error(conn, error)
  end
end