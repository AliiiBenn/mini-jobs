defmodule MiniJobs.Plugs.RequestValidator do
  require Logger
  alias MiniJobs.Errors

  def init(opts), do: opts

  def call(conn, _opts) do
    validate_request(conn)
  end

  defp validate_request(conn) do
    try do
      # Vérifier si la méthode est supportée
      supported_methods = MiniJobs.JobValidation.supported_http_methods()
      
      if conn.method not in supported_methods do
        Logger.warning("Unsupported HTTP method: #{conn.method}")
        send_error_response(conn, Errors.method_not_allowed("Method Not Allowed"))
      else
        # Valider la requête selon la méthode et le chemin
        case validate_request_content(conn) do
          {:ok, conn} -> conn
          {:error, error} -> send_error_response(conn, error)
        end
      end
    rescue
      error ->
        Logger.error("Error in RequestValidator plug: #{inspect(error)}")
        send_error_response(conn, Errors.internal_server_error("Internal Server Error"))
    end
  end

  defp validate_request_content(conn) do
    # Validation basique selon le chemin de la requête
    case conn.request_path do
      "/api/jobs" ->
        case conn.method do
          "POST" -> validate_job_creation_request(conn)
          "GET" -> validate_job_list_request(conn)
          "DELETE" -> validate_job_deletion_request(conn)
          _ -> {:ok, conn}
        end
      
      "/health" ->
        validate_health_request(conn)
      
      _ ->
        {:ok, conn}
    end
  end

  defp validate_job_creation_request(conn) do
    # Valider que le corps de la requête existe et est du bon format
    case conn.body_params do
      %{} when map_size(conn.body_params) > 0 ->
        MiniJobs.JobValidation.validate_job_creation(conn.body_params)
      %{} ->
        {:error, Errors.bad_request("Request body is required")}
      _ ->
        {:error, Errors.bad_request("Invalid request body format")}
    end
  end

  defp validate_job_list_request(conn) do
    # Valider les paramètres de requête pour la liste des jobs
    MiniJobs.JobValidation.validate_query_params(conn.query_params)
  end

  defp validate_job_deletion_request(conn) do
    # Valider que l'ID du job est présent et valide
    with {:ok, job_id} <- Map.fetch(conn.path_params, "id"),
         {:ok, validated_id} <- MiniJobs.JobValidation.validate_job_id(job_id) do
      {:ok, conn}
    else
      :error ->
        {:error, Errors.bad_request("Job ID is required in path")}
      {:error, _error} ->
        {:error, Errors.bad_request("Invalid job ID format")}
    end
  end

  defp validate_health_request(conn) do
    # Le endpoint health n'a pas besoin de validation complexe
    {:ok, conn}
  end

  defp send_error_response(conn, error) do
    # S'assurer que l'erreur a un statut valide
    error_with_status = Map.get(error, :status, 400)
    
    conn
    |> Errors.send_error(error)
  end
end