defmodule MiniJobs.Plugs.Logger do
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    start_time = System.monotonic_time(:microsecond)

    # Logger.info("Incoming request: #{conn.method} #{conn.request_path}")

    # Stocker le temps de départ pour le calcul de la durée
    conn = Plug.Conn.put_private(conn, :logger_start_time, start_time)

    # Appeler le prochain plug dans le pipeline
    conn
  rescue
    error ->
      Logger.error("Error in Logger plug: #{inspect(error)}")
      conn
  end
end