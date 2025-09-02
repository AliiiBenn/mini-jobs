defmodule MiniJobs.Plugs.JSONParser do
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_content_type(conn) do
      "application/json" ->
        parse_json_body(conn)
      _ ->
        conn
    end
  end

  defp get_content_type(conn) do
    # Chercher le content-type dans les headers (liste de tuples)
    case Enum.find(conn.req_headers, fn {key, _} -> key == "content-type" end) do
      nil -> nil
      {content_type, _} ->
        # Extraire le type sans les paramètres (ex: "application/json; charset=utf-8")
        content_type
        |> String.split(";")
        |> List.first()
        |> String.trim()
    end
  end

  defp parse_json_body(conn) do
    case conn.body_params do
      %{} -> 
        # body_params est déjà parsé par Plug
        conn
      _ -> 
        # Si body_params n'est pas un map, tenter de parser manuellement
        parse_json_body_raw(conn)
    end
  rescue
    _ ->
      Logger.warning("Failed to parse JSON body")
      conn
  end

  defp parse_json_body_raw(conn) do
    case conn do
      %{body_params: body_params} when is_binary(body_params) ->
        try do
          parsed = Jason.decode!(body_params)
          %{conn | body_params: parsed, body_data: parsed}
        rescue
          _ ->
            Logger.warning("Failed to parse JSON body: #{body_params}")
            conn
        end
      _ ->
        conn
    end
  end
end