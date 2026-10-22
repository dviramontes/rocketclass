defmodule RocketclassWeb.WebTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint RocketclassWeb.Endpoint

  test "home renders, LiveView selects persisted runs, and export is served" do
    source = "data/web-test-#{System.unique_integer([:positive])}.mp4"
    File.write!(source, "video fixture")
    {:ok, run} = Rocketclass.Runs.create(source, "fixture")
    artifact = Rocketclass.Runs.artifact(run.id)
    File.write!(artifact, "{\"frame_index\":0}\n")

    Rocketclass.Runs.update(run,
      status: "complete",
      frames: 1,
      summary: %{"elapsed_seconds" => 0.1}
    )

    on_exit(fn ->
      File.rm(source)
      File.rm(artifact)
    end)

    {:ok, view, html} = live(build_conn(), "/")
    assert html =~ "Start a run"
    view |> element("button[phx-value-id='#{run.id}']") |> render_click()
    assert render(view) =~ "SYNTHETIC DEMO"
    assert has_element?(view, "video[src='/runs/#{run.id}/video']")
    assert get(build_conn(), "/runs/#{run.id}/results").resp_body == "{\"frame_index\":0}\n"

    video =
      build_conn()
      |> Plug.Conn.put_req_header("range", "bytes=0-4")
      |> get("/runs/#{run.id}/video")

    assert video.status == 206
    assert video.resp_body == "video"
  end

  test "static browser dependencies are available and unknown runs are rejected" do
    for path <- [
          "/assets/app.js",
          "/assets/app.css",
          "/vendor/phoenix/phoenix.js",
          "/vendor/live_view/phoenix_live_view.js"
        ] do
      assert get(build_conn(), path).status == 200
    end

    assert get(build_conn(), "/runs/missing/video").status == 404
    assert get(build_conn(), "/runs/missing/results").status == 404
  end

  test "classify button uses a selected frame and displays only the latest API response" do
    previous = Application.get_env(:rocketclass, Rocketclass.FrameClassifier)
    on_exit(fn -> Application.put_env(:rocketclass, Rocketclass.FrameClassifier, previous) end)
    source = "data/frame-test-#{System.unique_integer([:positive])}.mp4"
    File.write!(source, "fixture")
    on_exit(fn -> File.rm(source) end)
    {:ok, run} = Rocketclass.Runs.create(source, "inspect")

    response = %{
      "model" => "laya:latest",
      "answers" => %{
        "object" => %{
          "type" => "choice",
          "choice" => "present",
          "probabilities" => %{"present" => 0.8, "absent" => 0.1, "unknown" => 0.1},
          "confidence" => 0.7
        }
      }
    }

    Application.put_env(:rocketclass, Rocketclass.FrameClassifier,
      transport: fn _, _, _ ->
        {:ok,
         %{
           "message" => %{
             "content" =>
               Jason.encode!(%{car: "Car visible", ball: "Ball visible", goal: "Goal visible"})
           }
         }}
      end,
      laya_options: [transport: fn _, _, _ -> {:ok, response} end]
    )

    {:ok, view, _} = live(build_conn(), "/")
    refute has_element?(view, "textarea")
    assert has_element?(view, "#classify-frame[disabled]")
    view |> element("button[phx-value-id='#{run.id}']") |> render_click()
    payload = %{image: "data:image/jpeg;base64,/9j/", run_id: run.id, timestamp: 2.5}
    render_hook(view, "classify_frame", payload)
    assert render_async(view) =~ "ball: present"
    assert render(view) =~ "Frame at 2.5 s"
    assert has_element?(view, "#latest-api-response", "probabilities")

    Application.put_env(:rocketclass, Rocketclass.FrameClassifier,
      transport: fn _, _, _ -> {:error, "Service unavailable"} end
    )

    render_hook(view, "classify_frame", payload)
    assert render_async(view) =~ "Service unavailable"
    assert has_element?(view, "#latest-api-response", "Service unavailable")
    refute has_element?(view, "#latest-api-response", "probabilities")
  end
end
