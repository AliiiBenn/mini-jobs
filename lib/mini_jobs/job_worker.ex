defmodule MiniJobs.JobWorker do
  use GenServer

  def start_link(task_fun) do
    GenServer.start_link(__MODULE__, task_fun)
  end

  def init(task_fun) do
    result = task_fun.()
    IO.puts("Job terminé avec résultat: #{inspect(result)}")
    {:stop, :normal, result}
  end
end
