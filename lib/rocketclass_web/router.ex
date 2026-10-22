defmodule RocketclassWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:put_root_layout, html: {RocketclassWeb.Layouts, :root})
  end

  scope "/" do
    pipe_through(:browser)
    live("/", RocketclassWeb.HomeLive)
    get("/runs/:id/video", RocketclassWeb.FilesController, :video)
    get("/runs/:id/results", RocketclassWeb.FilesController, :results)
  end
end
