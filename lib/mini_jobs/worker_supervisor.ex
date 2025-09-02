defmodule MiniJobs.WorkerSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    # Configure worker pool
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 100)
  end

  @doc """
  Start a new worker for a job
  """
  def start_worker(job, opts \\ []) do
    worker_opts = [
      name: opts[:name]
    ]

    spec = %{
      id: MiniJobs.JobWorker,
      start: {MiniJobs.JobWorker, :start_link, [worker_opts]},
      restart: :transient,
      shutdown: job.timeout || 30_000
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Logger.info("Started worker for job #{job.id}: #{inspect(pid)}")
        {:ok, pid}
      {:error, reason} ->
        Logger.error("Failed to start worker for job #{job.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop a worker
  """
  def stop_worker(worker_pid) do
    case DynamicSupervisor.terminate_child(__MODULE__, worker_pid) do
      :ok ->
        :ok
      {:error, reason} ->
        Logger.error("Failed to stop worker: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get active workers count
  """
  def active_workers_count() do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.filter(fn {_, pid, _, _} -> Process.alive?(pid) end)
    |> length()
  end

  @doc """
  List all active workers
  """
  def list_active_workers() do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.filter(fn {_, pid, _, _} -> Process.alive?(pid) end)
    |> Enum.map(fn {id, pid, type, modules} ->
      %{
        id: id,
        pid: pid,
        type: type,
        modules: modules
      }
    end)
  end

  @doc """
  Ensure we have enough workers to handle the queue
  """
  def ensure_workers(max_workers, current_workers \\ nil) do
    current_count = current_workers || active_workers_count()
    needed = max_workers - current_count

    if needed > 0 do
      Logger.info("Scaling up workers to #{max_workers} (currently #{current_count})")
      # Start more workers (they'll automatically pick up jobs)
      Enum.each(1..needed, fn _ ->
        # Start worker with minimal opts, it will be assigned a job later
        spec = %{
          id: MiniJobs.JobWorker,
          start: {MiniJobs.JobWorker, :start_link, [[name: generate_worker_id()]]},
          restart: :transient
        }
        DynamicSupervisor.start_child(__MODULE__, spec)
      end)
    end

    {:ok, active_workers_count()}
  end

  @doc """
  Cleanup idle workers when there's no work
  """
  def cleanup_idle_workers(min_workers \\ 1) do
    current_count = active_workers_count()

    if current_count > min_workers do
      # We have more workers than needed, terminate some
      to_terminate = current_count - min_workers
      
      Logger.info("Cleaning up #{to_terminate} idle workers")

      # Get list of workers
      workers = list_active_workers()
      
      # Terminate the oldest workers
      workers
      |> Enum.take(to_terminate)
      |> Enum.each(fn %{pid: pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      end)
    end

    {:ok, active_workers_count()}
  end

  # Generate unique worker ID for auto-generated workers
  defp generate_worker_id() do
    "worker_#{DateTime.utc_now() |> DateTime.to_unix(:microsecond)}_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  @doc """
  Stop all workers gracefully
  """
  def shutdown() do
    Logger.info("Shutting down WorkerSupervisor")
    
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end)
  end
end