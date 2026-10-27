"""Shared in-process TTL cache and ETag helpers.

The cache here is deliberately the same shape as the one in
`app/codeforces.py`: a plain dict guarded by a lock, per-process, lost on
restart. It exists to avoid recomputing derived aggregates (bucket counts,
topic tallies) from an already-cached submission list.
"""

import hashlib
import threading
import time
from dataclasses import dataclass
from typing import Callable, TypeVar

from fastapi import Response
from pydantic import BaseModel

T = TypeVar("T")


class TtlCache:
    """Thread-safe TTL cache.

    FastAPI runs sync endpoints in a threadpool, so concurrent access is real
    and the lock is required.
    """

    def __init__(self) -> None:
        self._entries: dict[object, tuple[float, object]] = {}
        self._lock = threading.Lock()

    def get_or_set(self, key: object, ttl: float, producer: Callable[[], T]) -> T:
        now = time.monotonic()
        with self._lock:
            hit = self._entries.get(key)
            if hit is not None and now - hit[0] < ttl:
                return hit[1]  # type: ignore[return-value]

        # Compute outside the lock so a slow producer cannot block readers.
        value = producer()

        with self._lock:
            self._entries[key] = (now, value)
        return value

    def peek(self, key: object, ttl: float) -> T | None:
        """Returns a fresh entry without computing one, or None if absent/stale."""
        now = time.monotonic()
        with self._lock:
            hit = self._entries.get(key)
            if hit is not None and now - hit[0] < ttl:
                return hit[1]  # type: ignore[return-value]
        return None

    def clear(self) -> None:
        with self._lock:
            self._entries.clear()

    def delete(self, key: object) -> None:
        """Drops a single entry, e.g. to force a fresh read for one handle."""
        with self._lock:
            self._entries.pop(key, None)


def make_etag(payload: bytes) -> str:
    """Builds a strong ETag from already-serialised response bytes."""
    return '"' + hashlib.sha256(payload).hexdigest()[:32] + '"'


def etag_matches(if_none_match: str | None, etag: str) -> bool:
    """True when the client's cached copy is still valid.

    Handles the `W/` weak-validator prefix and comma-separated lists, and
    treats `*` as a match per RFC 9110.
    """
    if not if_none_match:
        return False

    candidates = [c.strip() for c in if_none_match.split(",") if c.strip()]
    for candidate in candidates:
        if candidate == "*":
            return True
        if candidate.removeprefix("W/") == etag:
            return True
    return False


@dataclass(frozen=True)
class Rendered:
    """A response body frozen as bytes alongside its ETag.

    Caching the serialised form means a conditional request can be answered
    from these bytes without rebuilding the Pydantic model at all.
    """

    body: bytes
    etag: str


class RenderedCache:
    """TTL cache holding [Rendered] responses, keyed per resource.

    Built on [TtlCache] so the eviction and locking behaviour is shared.
    """

    def __init__(self, ttl: float) -> None:
        self._ttl = ttl
        self._cache = TtlCache()

    def get_or_render(self, key: object, render: Callable[[], Rendered]) -> Rendered:
        return self._cache.get_or_set(key, self._ttl, render)

    def get(self, key: object) -> Rendered | None:
        """Returns a fresh entry without computing one, or None if absent."""
        return self._cache.peek(key, self._ttl)

    def clear(self) -> None:
        self._cache.clear()


def render_model(model: BaseModel) -> Rendered:
    """Freezes a Pydantic model into its wire bytes plus an ETag."""
    body = model.model_dump_json().encode()
    return Rendered(body=body, etag=make_etag(body))


def conditional_response(
    cached: Rendered,
    *,
    if_none_match: str | None,
) -> Response:
    """Serves [cached], answering 304 when the client's copy is current.

    The body is already bytes, so a 304 costs one header parse and one
    comparison — no model rebuild, no re-serialisation.
    """
    headers = {"ETag": cached.etag, "Cache-Control": "private, no-cache"}

    if etag_matches(if_none_match, cached.etag):
        return Response(status_code=304, headers=headers)

    return Response(
        content=cached.body,
        media_type="application/json",
        headers=headers,
    )


def cached_conditional_response(
    cache: RenderedCache,
    key: object,
    render: Callable[[], Rendered],
    *,
    if_none_match: str | None,
) -> Response:
    """Convenience wrapper: render if needed, then serve conditionally.

    Note this still renders on a miss; callers that want a hard short-circuit
    should probe with `cache.get(key)` first (see the dashboard endpoints).
    """
    return conditional_response(
        cache.get_or_render(key, render), if_none_match=if_none_match
    )
