defmodule MiniJobs.JobWorker do
  require Logger
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    Logger.info("JobWorker starting with opts: #{inspect(opts)}")
    {:ok, opts}
  end

  @impl true
  def handle_call({:execute_job, job}, _from, state) do
    Logger.info("Executing job #{job.id}: #{job.command}")
    
    # Update job status to running
    case MiniJobs.QueueManager.update_job_status(job.id, :running) do
      {:ok, updated_job} ->
        # Execute the job with timeout
        result = execute_with_timeout(updated_job, state)
        
        # Update job based on result
        case result do
          {:ok, output} ->
            _completed_job = %{updated_job | 
              status: :completed, 
              result: output,
              completed_at: DateTime.utc_now()
            }
            MiniJobs.QueueManager.update_job_status(job.id, :completed)
            Logger.info("Job #{job.id} completed successfully")
            
            {:reply, {:success, output}, state}
            
          {:error, reason} ->
            _failed_job = %{updated_job | 
              status: :failed, 
              error: reason,
              completed_at: DateTime.utc_now(),
              retry_count: updated_job.retry_count + 1
            }
            
            MiniJobs.QueueManager.update_job_status(job.id, :failed)
            Logger.warning("Job #{job.id} failed: #{reason}")
            
            # Check if we should retry
            if updated_job.retry_count < updated_job.max_retries do
              Logger.info("Retrying job #{job.id} (attempt #{updated_job.retry_count + 1})")
              # The worker supervisor will handle requeuing
              {:reply, {:retry, reason}, state}
            else
              Logger.error("Job #{job.id} exceeded max retries (#{updated_job.max_retries})")
              {:reply, {:failed, reason}, state}
            end
        end
        
      {:error, reason} ->
        Logger.error("Failed to update job status for #{job.id}: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  # Execute job with timeout handling
  defp execute_with_timeout(job, _state) do
    # Convert timeout to milliseconds
    timeout = job.timeout || 30_000
    
    try do
      # Execute the command
      case execute_command(job.command) do
        {:ok, output} -> {:ok, output}
        {:error, reason} -> {:error, reason}
        reason -> {:error, "Job failed with reason: #{inspect(reason)}"}
      end
    catch
      :exit, {^timeout, _} -> 
        {:error, "Job timed out after #{timeout}ms"}
      error ->
        {:error, "Job failed with exception: #{inspect(error)}"}
    end
  end

  # Execute the actual command
  defp execute_command(command) when is_binary(command) do
    # For now, simulate command execution
    # In a real implementation, you might:
    # 1. Execute shell commands
    # 2. Call external APIs
    # 3. Run calculations locally
    # 4. Process data in some way
    
    Logger.info("Executing command: #{command}")
    
    # Simulate some processing time
    Process.sleep(:rand.uniform(1000))
    
    # Simulate different outcomes
    case :rand.uniform(10) do
      10 ->
        {:error, "Random failure during execution"}
      5 ->
        {:error, "Command returned non-zero exit code"}
      _ ->
        {:ok, "Command executed successfully. Output: #{command}"}
    end
  end

  # Public API for the worker
  def execute_job(pid, job) do
    GenServer.call(pid, {:execute_job, job}, 5000)  # 5 second timeout
  end

  # Check if worker is busy
  def busy?(pid) do
    GenServer.call(pid, :busy)
  end

end