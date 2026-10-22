import io
import json
import struct
import threading

import av
import pytest

from worker import analyze, receive


class Fragmented(io.BytesIO):
    def read(self, count=-1):
        return super().read(min(count, 2))


def packet(value):
    body = json.dumps(value).encode()
    return struct.pack('>I', len(body)) + body


def test_fragmentation_and_multiple_packets():
    stream = Fragmented(packet({'v': 1, 'type': 'cancel'}) * 2)
    assert receive(stream)['type'] == 'cancel'
    assert receive(stream)['type'] == 'cancel'
    assert receive(stream) is None


@pytest.mark.parametrize('data', [b'\0\0', struct.pack('>I', 2_000_000), packet({'v': 2}), b'\0\0\0\x05{}'])
def test_rejects_bad_packets(data):
    with pytest.raises((ValueError, EOFError)):
        receive(io.BytesIO(data))


@pytest.fixture
def video(tmp_path):
    path = tmp_path / 'generated.mp4'
    with av.open(str(path), 'w') as container:
        stream = container.add_stream('mpeg4', rate=25)
        stream.width = 64
        stream.height = 48
        stream.pix_fmt = 'yuv420p'
        for _ in range(10):
            frame = av.VideoFrame(64, 48, 'yuv420p')
            for plane in frame.planes:
                plane.update(bytes(plane.buffer_size))
            for encoded in stream.encode(frame):
                container.mux(encoded)
        for encoded in stream.encode():
            container.mux(encoded)
    return path


def test_decode_timestamps_and_fixture_label(video, tmp_path):
    for mode in ('inspect', 'fixture'):
        output = tmp_path / f'{mode}.jsonl'
        messages = []
        analyze({'id': 'test', 'source': str(video), 'output': str(output), 'mode': mode}, threading.Event(), messages.append)
        assert messages[-1]['type'] == 'complete'
        rows = [json.loads(line) for line in output.read_text().splitlines()]
        assert len(rows) == 10
        assert [r['timestamp_ms'] for r in rows] == pytest.approx([i * 40 for i in range(10)])
        assert rows[0]['width'] == 64
        assert bool(rows[0]['detections']) == (mode == 'fixture')
        assert messages[-1]['summary']['model'] is None


def test_cancel_cleans_partial(video, tmp_path):
    cancel = threading.Event()
    cancel.set()
    output = tmp_path / 'cancel.jsonl'
    messages = []
    analyze({'id': 'test', 'source': str(video), 'output': str(output), 'mode': 'inspect'}, cancel, messages.append)
    assert messages[-1]['type'] == 'cancelled'
    assert not output.exists()
    assert not output.with_suffix('.partial').exists()


def test_invalid_video_reports_error(tmp_path):
    messages = []
    analyze({'id': 'test', 'source': str(tmp_path / 'missing.mp4'), 'output': str(tmp_path / 'out.jsonl'), 'mode': 'inspect'}, threading.Event(), messages.append)
    assert messages[-1]['type'] == 'error'
