defmodule MiniJobs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def application do
    [
      extra_applications: [:logger, :plug, :cowboy],
      mod: {MiniJobs.Application, []}
    ]
  end

  @impl true
  def start(_type, _args) do
    # Start the main supervisor and cowboy HTTP server
    children = [
      # Plug.Cowboy HTTP server
      {Plug.Cowboy, scheme: :http, plug: MiniJobs.Router, options: [port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: MiniJobs.Supervisor]
    {:ok, _pid} = Supervisor.start_link(children, opts)
  end
end
