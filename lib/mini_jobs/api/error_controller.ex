defmodule MiniJobs.API.ErrorController do
  require Logger

  def not_found(conn) do
    Logger.warning("404 Not Found: #{conn.method} #{conn.request_path}")
    
    error = %{
      error: "Not Found",
      message: "The requested resource was not found",
      path: conn.request_path,
      method: conn.method
    }

    json(conn, 404, error)
  end

  defp json(conn, status, data) do
    body = Jason.encode!(data)
    
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, body)
  end
end