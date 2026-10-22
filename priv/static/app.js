const Playback = {
  mounted() {
    this.video = this.el.querySelector('video');
    this.canvas = this.el.querySelector('canvas');
    this.rows = [];
    this.abort = new AbortController();
    this.draw = () => {
      const v = this.video, c = this.canvas;
      c.width = v.videoWidth || 1920; c.height = v.videoHeight || 1080;
      const ctx = c.getContext('2d');
      const time = v.currentTime * 1000;
      let lo = 0, hi = this.rows.length - 1, index = -1;
      while (lo <= hi) { const mid = (lo + hi) >> 1; if ((this.rows[mid].playback_timestamp_ms ?? this.rows[mid].timestamp_ms) <= time) { index = mid; lo = mid + 1; } else hi = mid - 1; }
      const row = this.rows[index];
      if (row) {
        const sx = c.width / row.width, sy = c.height / row.height;
        ctx.lineWidth = 4; ctx.strokeStyle = '#b9ff66'; ctx.fillStyle = '#b9ff66'; ctx.font = '24px sans-serif';
        for (const box of row.detections) { const [x1,y1,x2,y2] = box.bbox_xyxy; ctx.strokeRect(x1*sx,y1*sy,(x2-x1)*sx,(y2-y1)*sy); ctx.fillText('SYNTHETIC ' + box.class, x1*sx, Math.max(24, y1*sy-10)); }
      }
      this.raf = requestAnimationFrame(this.draw);
    };
    this.capture = () => {
      try {
        const video = this.video;
        if (video.readyState < 2 || !video.videoWidth) throw new Error('Wait for the video frame to load.');
        video.pause();
        const frame = document.createElement('canvas');
        const scale = Math.min(1, 960 / video.videoWidth);
        frame.width = Math.round(video.videoWidth * scale);
        frame.height = Math.round(video.videoHeight * scale);
        frame.getContext('2d').drawImage(video, 0, 0, frame.width, frame.height);
        this.pushEvent('classify_frame', {run_id: this.el.dataset.runId, timestamp: video.currentTime, image: frame.toDataURL('image/jpeg', 0.85)});
      } catch (error) { this.pushEvent('frame_capture_error', {error: error.message}); }
    };
    window.addEventListener('rocketclass:classify-frame', this.capture);
    this.draw(); this.load();
  },
  updated() { this.load(); },
  async load() {
    const url = this.el.dataset.results;
    if (!url || this.loaded === url) return;
    this.loaded = url;
    try {
      const response = await fetch(url, {signal: this.abort.signal});
      if (!response.ok) throw new Error('Results unavailable');
      this.rows = (await response.text()).trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
      this.el.querySelector('[data-playback-status]').textContent = `${this.rows.length} frame records loaded · overlays aligned to video presentation timestamps`;
    } catch (error) { if (error.name !== 'AbortError') this.el.querySelector('[data-playback-status]').textContent = error.message; }
  },
  destroyed() { window.removeEventListener('rocketclass:classify-frame', this.capture); cancelAnimationFrame(this.raf); this.abort.abort(); }
};
const liveSocket = new LiveView.LiveSocket('/live', Phoenix.Socket, {hooks: {Playback}, params: {_csrf_token: document.querySelector('meta[name="csrf-token"]').content}});
liveSocket.connect();
