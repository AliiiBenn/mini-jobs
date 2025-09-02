defmodule MiniJobs.QueueManager do
  require Logger
  use GenServer

  # Job status constants
  @job_statuses [:pending, :running, :completed, :failed, :cancelled]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create ETS tables if they don't exist
    :ets.new(:job_queue, [
      :public,
      :ordered_set,
      :named_table,
      :protected,
      {:write_concurrency, true}
    ])

    :ets.new(:job_registry, [
      :public,
      :bag,
      :named_table,
      :protected
    ])

    {:ok, %{}}
  end

  # Public API

  @doc """
  Enqueue a new job
  """
  def enqueue_job(%{command: command} = job_data) do
    job_id = generate_job_id()
    priority = Map.get(job_data, :priority, :normal)
    timeout = Map.get(job_data, :timeout, 30_000)
    max_retries = Map.get(job_data, :max_retries, 3)

    job = %{
      id: job_id,
      command: command,
      priority: priority,
      status: :pending,
      created_at: DateTime.utc_now(),
      started_at: nil,
      completed_at: nil,
      result: nil,
      error: nil,
      timeout: timeout,
      retry_count: 0,
      max_retries: max_retries
    }

    # Insert into both tables
    :ets.insert(:job_queue, {job_id, job})
    :ets.insert(:job_registry, {job.id, job.status, job})

    Logger.info("Job enqueued: #{job_id} with priority #{priority}")

    {:ok, job_id}
  end

  @doc """
  Dequeue the next job (FIFO with priority)
  """
  def dequeue_job() do
    # Find the next job based on priority
    case find_next_pending_job() do
      {job_id, job_data} ->
        job = %{job_data | status: :running, started_at: DateTime.utc_now()}

        # Update in both tables
        :ets.insert(:job_queue, {job_id, job})
        :ets.insert(:job_registry, {job.id, job.status, job})

        Logger.info("Job dequeued: #{job_id}")
        {:ok, job}
      nil ->
        {:error, :empty_queue}
    end
  end

  @doc """
  Peek at the next job without dequeuing
  """
  def peek_queue() do
    case find_next_pending_job() do
      {job_id, job_data} -> {:ok, %{job_data | id: job_id}}
      nil -> {:error, :empty_queue}
    end
  end

  @doc """
  Get the number of pending jobs
  """
  def queue_size() do
    :ets.foldl(
      fn {_job_id, %{status: status}}, acc ->
        if status == :pending, do: acc + 1, else: acc
      end,
      0,
      :job_queue
    )
  end

  @doc """
  Update job status
  """
  def update_job_status(job_id, status) when status in @job_statuses do
    case :ets.lookup(:job_queue, job_id) do
      [{^job_id, job}] ->
        updated_job = %{job |
          status: status,
          completed_at: if(status in [:completed, :failed, :cancelled], do: DateTime.utc_now(), else: nil),
          started_at: if(status == :running, do: DateTime.utc_now(), else: job.started_at)
        }

        :ets.insert(:job_queue, {job_id, updated_job})
        :ets.insert(:job_registry, {updated_job.id, updated_job.status, updated_job})

        Logger.info("Job #{job_id} status updated to #{status}")
        {:ok, updated_job}
      [] ->
        {:error, :job_not_found}
    end
  end

  @doc """
  Get job details
  """
  def get_job(job_id) do
    case :ets.lookup(:job_queue, job_id) do
      [{^job_id, job}] -> {:ok, job}
      [] -> {:error, :job_not_found}
    end
  end

  @doc """
  List all jobs
  """
  def list_jobs(opts \\ []) do
    status = Keyword.get(opts, :status, nil)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    # Get all jobs and filter by status if specified
    all_jobs = :ets.tab2list(:job_queue)

    filtered_jobs = case status do
      nil -> all_jobs
      s -> Enum.filter(all_jobs, fn {_job_id, job} -> job.status == s end)
    end

    jobs = filtered_jobs
    |> Enum.sort_by(&elem(&1, 1).created_at, {:desc, DateTime})
    |> Enum.slice(offset, limit)

    total = length(filtered_jobs)

    %{jobs: jobs, total: total}
  end

  # Private helper functions

  # Find the next pending job based on priority (high > normal > low)
  defp find_next_pending_job() do
    # Get all pending jobs and sort by priority and creation time
    all_jobs = :ets.tab2list(:job_queue)
    |> Enum.filter(fn {_job_id, job} -> job.status == :pending end)
    |> Enum.sort_by(fn {_job_id, job} ->
      # Sort by priority (high: 0, normal: 1, low: 2) then by creation time (oldest first)
      priority_order = %{high: 0, normal: 1, low: 2}
      {priority_order[job.priority], job.created_at}
    end)
    |> List.first()

    case all_jobs do
      {job_id, job} -> {job_id, job}
      nil -> nil
    end
  end

  # Generate unique job ID
  defp generate_job_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:microsecond)
    random_part = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{timestamp}-#{random_part}"
  end

  # For testing purposes
  def clear_queue() do
    :ets.delete_all_objects(:job_queue)
    :ets.delete_all_objects(:job_registry)
  end
end
