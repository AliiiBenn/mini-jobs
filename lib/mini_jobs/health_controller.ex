defmodule MiniJobs.HealthController do
  def check(conn) do
    response = %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: "0.1.0"
    }

    json(conn, 200, response)
  end

  defp json(conn, status, data) do
    body = Jason.encode!(data)

    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, body)
  end
end
