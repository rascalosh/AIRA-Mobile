"""A small in-memory sliding-window rate limiter.

ponytail: per process (the API runs as one process) and keyed by client address, so behind a reverse proxy every
client looks like the proxy until uvicorn's --proxy-headers is set up. Use the proxy's or an API gateway's limiter
(or Redis) if the API is ever scaled out.
"""

import threading
import time
from collections import defaultdict, deque

from app.core import errors


class RateLimiter:
    def __init__(self, clock=time.monotonic) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()
        self._clock = clock

    def check(self, key: str, limit: int, window_seconds: int) -> None:
        """Count a request for `key`; raise 429 when it exceeds `limit` in the last `window_seconds`."""
        now = self._clock()
        with self._lock:
            hits = self._hits[key]
            while hits and now - hits[0] >= window_seconds:
                hits.popleft()
            if len(hits) >= limit:
                raise errors.too_many_requests(int(window_seconds - (now - hits[0])) + 1)
            hits.append(now)
            if len(self._hits) > 10_000:  # forget idle keys so the table cannot grow without bound
                for k in [k for k, v in self._hits.items() if not v or now - v[-1] >= window_seconds]:
                    del self._hits[k]
