defmodule MiniJobs.JobRegistry do
  require Logger
  use GenServer

  # Job status constants
  @job_statuses [:pending, :running, :completed, :failed, :cancelled]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Initialize the registry as an ETS table for fast lookups
    # We'll store {job_id, metadata} for fast access
    :ets.new(:job_metadata, [
      :public,
      :set,
      :named_table,
      :protected
    ])

    {:ok, %{}}
  end

  @doc """
  Register a new job
  """
  def register_job(job_data) do
    job_id = job_data.id

    metadata = %{
      job_id: job_id,
      command: job_data.command,
      priority: job_data.priority,
      status: job_data.status,
      created_at: job_data.created_at,
      started_at: job_data.started_at,
      completed_at: job_data.completed_at,
      timeout: job_data.timeout,
      retry_count: job_data.retry_count,
      max_retries: job_data.max_retries
    }

    :ets.insert(:job_metadata, {job_id, metadata})

    Logger.info("Job registered: #{job_id}")
    :ok
  end

  @doc """
  Update job metadata
  """
  def update_job(job_id, updates) do
    case :ets.lookup(:job_metadata, job_id) do
      [{^job_id, metadata}] ->
        updated_metadata = Map.merge(metadata, updates)
        :ets.insert(:job_metadata, {job_id, updated_metadata})

        Logger.debug("Job metadata updated: #{job_id}")
        {:ok, updated_metadata}
      [] ->
        {:error, :job_not_found}
    end
  end

  @doc """
  Get job metadata
  """
  def get_job(job_id) do
    case :ets.lookup(:job_metadata, job_id) do
      [{^job_id, metadata}] -> {:ok, metadata}
      [] -> {:error, :job_not_found}
    end
  end

  @doc """
  List all registered jobs
  """
  def all_jobs() do
    :ets.tab2list(:job_metadata)
    |> Enum.map(fn {job_id, metadata} -> {job_id, metadata} end)
    |> Enum.sort_by(fn {_job_id, metadata} ->
      metadata.created_at
    end, {:desc, DateTime})
  end

  @doc """
  Get stats for all jobs
  """
  def job_stats() do
    stats = for status <- @job_statuses do
      count = count_jobs_by_status(status)
      {status, count}
    end

    total_jobs = :ets.info(:job_metadata, :size)
    %{total_jobs: total_jobs, by_status: Map.new(stats)}
  end

  @doc """
  Get jobs created after a specific time
  """
  def get_jobs_after(datetime) do
    all_jobs()
    |> Enum.filter(fn {_job_id, metadata} ->
      metadata.created_at && DateTime.compare(metadata.created_at, datetime) == :gt
    end)
    |> Enum.map(fn {job_id, _metadata} -> job_id end)
  end

  @doc """
  Cleanup completed jobs older than specified time
  """
  def cleanup_old_jobs(older_than_hours) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -older_than_hours * 3600)

    jobs_to_delete = all_jobs()
    |> Enum.filter(fn {_job_id, metadata} ->
      metadata.completed_at && DateTime.compare(metadata.completed_at, cutoff_time) == :lt
    end)
    |> Enum.map(fn {job_id, _metadata} -> job_id end)

    Enum.each(jobs_to_delete, fn job_id ->
      :ets.delete(:job_metadata, job_id)
    end)

    Logger.info("Cleaned up #{length(jobs_to_delete)} old completed jobs")
    length(jobs_to_delete)
  end

  @doc """
  Increment retry count for a job
  """
  def increment_retry_count(job_id) do
    case :ets.lookup(:job_metadata, job_id) do
      [{^job_id, metadata}] ->
        new_count = metadata.retry_count + 1
        updated_metadata = %{metadata | retry_count: new_count}
        :ets.insert(:job_metadata, {job_id, updated_metadata})
        {:ok, new_count}
      [] ->
        {:error, :job_not_found}
    end
  end

  @doc """
  Get jobs that have exceeded max retries
  """
  def get_jobs_exceeding_max_retries() do
    all_jobs()
    |> Enum.filter(fn {_job_id, metadata} ->
      metadata.retry_count >= metadata.max_retries
    end)
    |> Enum.map(fn {job_id, _metadata} -> job_id end)
  end

  @doc """
  Reset the registry (for testing)
  """
  def reset() do
    :ets.delete_all_objects(:job_metadata)
  end

  # Private helper functions

  defp count_jobs_by_status(status) do
    :ets.foldl(
      fn {_job_id, metadata}, acc ->
        if metadata.status == status do
          acc + 1
        else
          acc
        end
      end,
      0,
      :job_metadata
    )
  end
end
