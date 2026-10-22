import json
import struct
import sys
import time


def send(msg):
    body = json.dumps({'v': 1, **msg}).encode()
    sys.stdout.buffer.write(struct.pack('>I', len(body)) + body)
    sys.stdout.buffer.flush()


send({'type': 'ready'})
while True:
    header = sys.stdin.buffer.read(4)
    if not header:
        break
    request = json.loads(sys.stdin.buffer.read(struct.unpack('>I', header)[0]))
    if request['type'] == 'cancel':
        send({'type': 'cancelled', 'id': request['id']})
    elif 'crash' in request['source']:
        sys.exit(23)
    elif 'malformed' in request['source']:
        sys.stdout.buffer.write(b'\x00\x00\x00\x01{')
        sys.stdout.buffer.flush()
    elif 'hang' in request['source']:
        time.sleep(60)
    elif 'wait' in request['source']:
        pass
    else:
        send({'type': 'complete', 'id': request['id'], 'frames': 1, 'summary': {}})
