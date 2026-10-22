defmodule RocketclassWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :rocketclass
  @session [store: :cookie, key: "_rocketclass", signing_salt: "local-session", same_site: "Lax"]
  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])
  plug(Plug.Static, at: "/assets", from: {:rocketclass, "priv/static"})
  plug(Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"})
  plug(Plug.Static, at: "/vendor/live_view", from: {:phoenix_live_view, "priv/static"})
  plug(Plug.RequestId)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.Session, @session)
  plug(RocketclassWeb.Router)
end
