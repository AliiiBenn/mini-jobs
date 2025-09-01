defmodule MiniJobs.JobSupervisor do
  use DynamicSupervisor

  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_job(fun) do
    spec = {MiniJobs.JobWorker, fun}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
