defmodule Rocketclass.Run do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "runs" do
    field(:source, :string)
    field(:mode, :string)
    field(:status, :string)
    field(:frames, :integer, default: 0)
    field(:summary, :map, default: %{})
    field(:error, :string)
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule Rocketclass.Runs do
  import Ecto.Query
  alias Rocketclass.{Repo, Run}
  def list, do: Repo.all(from(r in Run, order_by: [desc: r.inserted_at], limit: 30))
  def get(id), do: Repo.get(Run, id)

  def sources do
    Path.wildcard("data/*")
    |> Enum.filter(&(Path.extname(&1) in [".mp4", ".mov", ".mkv", ".webm"] and File.regular?(&1)))
  end

  def create(source, mode) do
    if source in sources() and mode in ["inspect", "fixture"] do
      Repo.insert(%Run{id: Ecto.UUID.generate(), source: source, mode: mode, status: "running"})
    else
      {:error, :invalid_input}
    end
  end

  def update(run, attrs) do
    updated = run |> Ecto.Changeset.change(attrs) |> Repo.update!()
    Phoenix.PubSub.broadcast(Rocketclass.PubSub, "runs", :runs_changed)
    updated
  end

  def interrupt_stale do
    Repo.update_all(from(r in Run, where: r.status in ["running", "cancelling"]),
      set: [status: "interrupted", error: "Application or worker restarted"]
    )
  end

  def artifact(id) do
    if is_binary(id) and Regex.match?(~r/\A[0-9a-f-]{36}\z/, id),
      do: Path.expand("var/runs/#{id}.jsonl"),
      else: nil
  end
end
