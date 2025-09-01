defmodule MiniJobs.JobQueue do
  use GenServer

  # Démarrer le GenServer
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(state), do: {:ok, state}

  # API publique pour ajouter un job
  def add_job(fun) do
    GenServer.cast(__MODULE__, {:add, fun})
  end

  # Gestion des messages
  def handle_cast({:add, fun}, state) do
    MiniJobs.JobSupervisor.start_job(fun)
    {:noreply, state}
  end
end
