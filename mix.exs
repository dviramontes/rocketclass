defmodule Rocketclass.MixProject do
  use Mix.Project

  def project do
    [
      app: :rocketclass,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [setup: ["deps.get", "ecto.create", "ecto.migrate"]]
    ]
  end

  def application,
    do: [mod: {Rocketclass.Application, []}, extra_applications: [:logger, :inets, :ssl]]

  defp deps do
    [
      {:phoenix, "~> 1.8.0"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:phoenix_html, "~> 4.3"},
      {:bandit, "~> 1.12"},
      {:ecto_sql, "~> 3.14"},
      {:ecto_sqlite3, "~> 0.24.1"},
      {:jason, "~> 1.4"},
      {:lazy_html, "~> 0.1", only: :test}
    ]
  end
end
