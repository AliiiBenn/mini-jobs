defmodule MiniJobs.JobProcessor do
  require Logger
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start the queue manager and worker supervisor
    {:ok, _queue_manager} = MiniJobs.QueueManager.start_link([])
    {:ok, _worker_sup} = MiniJobs.WorkerSupervisor.start_link([])

    # Start processing jobs
    schedule_next_job()
    
    {:ok, %{active_workers: 0}}
  end

  @impl true
  def handle_info(:process_next_job, state) do
    # Check if we have available workers
    max_workers = 10  # Configurable max workers
    current_workers = state.active_workers

    if current_workers < max_workers do
      # Get next job from queue
      case MiniJobs.QueueManager.dequeue_job() do
        {:ok, job} ->
          Logger.info("Processing job #{job.id}: #{job.command}")
          
          # Start a worker for this job
          case MiniJobs.WorkerSupervisor.start_worker(job) do
            {:ok, worker_pid} ->
              # Tell the worker to execute the job
              case MiniJobs.JobWorker.execute_job(worker_pid, job) do
                :ok ->
                  # Mark this worker as active
                  new_state = %{state | active_workers: current_workers + 1}
                  schedule_next_job()
                  {:noreply, new_state}
                {:success, _output} ->
                  # Job completed successfully, mark worker as active
                  new_state = %{state | active_workers: current_workers + 1}
                  schedule_next_job()
                  {:noreply, new_state}
                {:retry, reason} ->
                  Logger.warning("Job #{job.id} failed but will be retried: #{reason}")
                  # The job is already back in the queue, just continue processing
                  schedule_next_job()
                  {:noreply, state}
                {:failed, reason} ->
                  Logger.error("Job #{job.id} failed permanently: #{reason}")
                  schedule_next_job()
                  {:noreply, state}
              end
            {:error, reason} ->
              Logger.error("Failed to start worker for job #{job.id}: #{inspect(reason)}")
              schedule_next_job()
              {:noreply, state}
          end
        {:error, :empty_queue} ->
          # No jobs in queue, check if we should scale down workers
          MiniJobs.WorkerSupervisor.cleanup_idle_workers(1)
          schedule_next_job()
          {:noreply, state}
      end
    else
      # Max workers reached, wait a bit and check again
      schedule_next_job(5000)  # Wait 5 seconds
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:worker_completed, _job_id}, state) do
    # Worker finished its job
    new_state = %{state | active_workers: max(0, state.active_workers - 1)}
    schedule_next_job()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:worker_retry, job_id}, state) do
    # Worker wants to retry the job
    Logger.info("Job #{job_id} will be retried")
    
    # Requeue the job (it will be picked up on next process cycle)
    # In a real implementation, you might want to add a delay before retrying
    schedule_next_job()
    {:noreply, state}
  end

  # Schedule the next job processing
  defp schedule_next_job(interval \\ 100) do
    Process.send_after(self(), :process_next_job, interval)
  end

  # Public API

  @doc """
  Get current processor stats
  """
  def stats() do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    queue_size = MiniJobs.QueueManager.queue_size()
    active_workers = state.active_workers
    
    stats = %{
      queue_size: queue_size,
      active_workers: active_workers,
      max_workers: 10,
      workers_list: MiniJobs.WorkerSupervisor.list_active_workers()
    }

    {:reply, stats, state}
  end

  @doc """
  Shutdown the processor gracefully
  """
  def shutdown(pid) do
    GenServer.stop(pid)
  end
end