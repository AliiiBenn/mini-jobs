defmodule MiniJobs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: MiniJobs.Worker.start_link(arg)
      # {MiniJobs.Worker, arg}
      {MiniJobs.JobQueue, []},
      {MiniJobs.JobSupervisor, []},
      # Start Cowboy HTTP server
      {Plug.Cowboy, scheme: :http, plug: MiniJobs.Router, options: Application.get_env(:mini_jobs, :cowboy_opts, [])}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MiniJobs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
