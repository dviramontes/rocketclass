import Config

config :rocketclass, Rocketclass.Laya,
  base_url: System.get_env("LAYA_BASE_URL", "http://100.88.19.124:11434/v1"),
  model: System.get_env("LAYA_MODEL", "laya:latest"),
  timeout: 15_000

config :rocketclass, Rocketclass.FrameClassifier,
  endpoint: System.get_env("VISION_ENDPOINT", "http://100.88.19.124:11434/api/chat"),
  model: System.get_env("VISION_MODEL", "qwen3.5:35b"),
  timeout: 90_000
