# Runs and frame classification

A run processes the entire selected video. If you select the five-second sample, it processes that sample rather than the original recording.

## What a run does

1. Creates a run record in SQLite.
2. Sends the selected file to the persistent Python worker.
3. Decodes every video frame and records its timestamp and dimensions.
4. Writes one record per frame to a JSONL file.
5. Saves the run status, frame count, and processing time.

The UI lets you review run results, play the video, and export the frame records. Runs can be cancelled, and worker failures are recorded.

## Analysis modes

| Mode | Output |
| --- | --- |
| Inspect frames | Real decoded frames and timing metadata, with empty detections. |
| Synthetic overlay demo | The same frame records plus generated boxes to test synchronized playback. These boxes are not model predictions. |

## What Classify does

The **Classify** button is separate from a run. It pauses playback and captures the currently displayed frame. Qwen reads that image using a fixed prompt, then Laya classifies whether cars, a ball, and a physical goal are present, absent, or unclear.

Starting a run does **not** automatically classify the video. Classification results currently remain in the browser session, with the run ID and captured timestamp. They are not persisted in the run's JSONL export.

The latest classification API request and response appear in the UI. Classification quality still needs evaluation; these judgments do not provide bounding boxes or track movement.
