defmodule RocketclassWeb.FilesController do
  use Phoenix.Controller, formats: [:html]
  alias Rocketclass.Runs

  def video(conn, %{"id" => id}) do
    case Runs.get(id) do
      nil ->
        send_resp(conn, 404, "Run not found")

      run ->
        # Plug.Static provides byte ranges for seeking and limits access to this registered file.
        path = Path.expand(run.source)
        opts = Plug.Static.init(at: "/", from: Path.dirname(path), only: [Path.basename(path)])
        %{conn | path_info: [Path.basename(path)]} |> Plug.Static.call(opts) |> missing()
    end
  end

  def results(conn, %{"id" => id}) do
    case Runs.get(id) do
      %{status: "complete"} ->
        path = Runs.artifact(id)

        if File.regular?(path),
          do: conn |> put_resp_content_type("application/x-ndjson") |> send_file(200, path),
          else: send_resp(conn, 404, "Artifact missing")

      _ ->
        send_resp(conn, 404, "Completed run not found")
    end
  end

  defp missing(%{state: state} = conn) when state in [:sent, :file, :chunked], do: conn
  defp missing(conn), do: send_resp(conn, 404, "Video missing")
end
