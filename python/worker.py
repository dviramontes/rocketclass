"""Persistent v1 Port worker. stdout is exclusively length-prefixed JSON."""
import json
import os
import struct
import sys
import threading
import time
from pathlib import Path

import av

MAX_PACKET = 1_048_576
WRITE_LOCK = threading.Lock()


def read_exact(stream, count):
    chunks = bytearray()
    while len(chunks) < count:
        data = stream.read(count - len(chunks))
        if not data:
            if not chunks:
                return None
            raise EOFError("Truncated packet")
        chunks.extend(data)
    return bytes(chunks)


def receive(stream):
    header = read_exact(stream, 4)
    if header is None:
        return None
    size = struct.unpack(">I", header)[0]
    if size > MAX_PACKET:
        raise ValueError("Oversized packet")
    body = read_exact(stream, size)
    if body is None:
        raise EOFError("Missing packet body")
    message = json.loads(body)
    if not isinstance(message, dict) or message.get("v") != 1:
        raise ValueError("Unsupported protocol")
    return message


def send(message):
    body = json.dumps({"v": 1, **message}, allow_nan=False).encode()
    if len(body) > MAX_PACKET:
        raise ValueError("Oversized output")
    with WRITE_LOCK:
        sys.stdout.buffer.write(struct.pack(">I", len(body)) + body)
        sys.stdout.buffer.flush()


def fixture_boxes(width, height, index):
    # Deliberately synthetic geometry; never presented as model predictions.
    x = 0.15 + (index % 100) / 200
    return [{"class": "ball", "track_id": "fixture-ball", "detector_score": None,
             "bbox_xyxy": [x * width, .3 * height, (x + .05) * width, .39 * height]}]


def analyze(request, cancel, emit=send):
    run_id = request["id"]
    output = Path(request["output"])
    partial = output.with_suffix(".partial")
    start = time.perf_counter()
    try:
        mode = request["mode"]
        if mode not in ("inspect", "fixture"):
            raise ValueError("Unknown analysis mode")
        output.parent.mkdir(parents=True, exist_ok=True)
        count = 0
        origin = None
        last_progress = start
        with av.open(request["source"]) as container, partial.open("w") as records:
            if not container.streams.video:
                raise ValueError("Source has no video stream")
            stream = container.streams.video[0]
            container_start_ms = (container.start_time or 0) / 1000
            for frame in container.decode(stream):
                if cancel.is_set():
                    emit({"type": "cancelled", "id": run_id})
                    return
                if frame.pts is None:
                    raise ValueError("Video frame lacks a presentation timestamp")
                pts_ms = float(frame.pts * frame.time_base * 1000)
                if origin is None:
                    origin = pts_ms
                record = {"run_id": run_id, "frame_index": count, "timestamp_ms": pts_ms - origin,
                          "source_pts_ms": pts_ms, "playback_timestamp_ms": pts_ms - container_start_ms, "width": frame.width, "height": frame.height,
                          "mode": mode, "detections": fixture_boxes(frame.width, frame.height, count) if mode == "fixture" else []}
                records.write(json.dumps(record) + "\n")
                count += 1
                if time.perf_counter() - last_progress >= .25:
                    emit({"type": "progress", "id": run_id, "frames": count})
                    last_progress = time.perf_counter()
            if count == 0:
                raise ValueError("No frames decoded")
        if cancel.is_set():
            emit({"type": "cancelled", "id": run_id})
            return
        os.replace(partial, output)
        elapsed = time.perf_counter() - start
        emit({"type": "complete", "id": run_id, "frames": count,
              "summary": {"elapsed_seconds": elapsed, "decode_fps": count / elapsed,
                          "width": frame.width, "height": frame.height,
                          "last_timestamp_ms": pts_ms - origin, "first_source_pts_ms": origin,
                          "python": sys.version.split()[0], "pyav": av.__version__,
                          "model": None, "mode": mode, "worker_version": "0.1.0"}})
    except Exception as error:
        emit({"type": "error", "id": run_id, "error": str(error)})
    finally:
        partial.unlink(missing_ok=True)


def main():
    job = None
    cancel = threading.Event()
    active_id = None
    send({"type": "ready", "python": sys.version.split()[0], "pyav": av.__version__})
    try:
        while (request := receive(sys.stdin.buffer)) is not None:
            if request.get("type") == "cancel" and request.get("id") == active_id:
                cancel.set()
            elif request.get("type") == "analyze":
                if job and job.is_alive():
                    # The completion packet may reach BEAM before thread teardown.
                    job.join(timeout=.05)
                if job and job.is_alive():
                    send({"type": "error", "id": request.get("id"), "error": "Worker busy"})
                    continue
                cancel = threading.Event()
                active_id = request["id"]
                job = threading.Thread(target=analyze, args=(request, cancel), daemon=True)
                job.start()
            else:
                raise ValueError("Invalid command")
    finally:
        cancel.set()
        if job:
            job.join(timeout=1)


if __name__ == "__main__":
    main()
