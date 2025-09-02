import Config

config :mini_jobs,
  http_port: 4000,
  cowboy_opts: [
    port: 4000,
    num_acceptors: 100,
    max_connections: 16384,
    idle_timeout: 60000
  ],
  max_workers: 10,
  job_timeout: 30000,
  max_retries: 3,
  queue_size: 1000

# Plug pipeline configuration
config :mini_jobs, :plug_pipeline,
  plugs: [
    MiniJobs.Plugs.Logger,
    MiniJobs.Plugs.JSONParser,
    MiniJobs.Plugs.RequestValidator
  ]