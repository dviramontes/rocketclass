defmodule Rocketclass.Application do
  use Application

  def start(_type, _args) do
    File.mkdir_p!("var/runs")

    Supervisor.start_link(
      [
        Rocketclass.Repo,
        {Phoenix.PubSub, name: Rocketclass.PubSub},
        Rocketclass.Worker,
        RocketclassWeb.Endpoint
      ],
      strategy: :one_for_one,
      name: Rocketclass.Supervisor
    )
  end
end
