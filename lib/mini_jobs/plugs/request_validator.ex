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
    error = %{
      error: status_to_string(status),
      message: message
    }

    body = Jason.encode!(error)
    
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  defp status_to_string(status) when is_integer(status) do
    case status do
      400 -> "Bad Request"
      401 -> "Unauthorized"
      403 -> "Forbidden"
      404 -> "Not Found"
      405 -> "Method Not Allowed"
      500 -> "Internal Server Error"
      _ -> "Error"
    end
  end
end