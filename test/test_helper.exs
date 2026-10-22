ExUnit.start()
Ecto.Migrator.run(Rocketclass.Repo, "priv/repo/migrations", :up, all: true)
