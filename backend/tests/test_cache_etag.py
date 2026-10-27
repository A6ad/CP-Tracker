"""ETag / conditional-request behaviour and cache correctness.

These cover the byte-cache layer: 304 short-circuiting, key scoping, and
invalidation on writes.
"""

import pytest
from fastapi import Response

from app.cache import Rendered, RenderedCache, TtlCache, etag_matches, make_etag
from app.routers import user as user_module


# --- Unit-level: cache primitives -----------------------------------------


def test_ttl_cache_computes_once_and_reuses():
    calls = []

    def producer():
        calls.append(1)
        return "value"

    cache = TtlCache()
    assert cache.get_or_set("k", 60, producer) == "value"
    assert cache.get_or_set("k", 60, producer) == "value"
    assert len(calls) == 1


def test_ttl_cache_peek_does_not_compute():
    calls = []

    def producer():
        calls.append(1)
        return "value"

    cache = TtlCache()
    assert cache.peek("missing", 60) is None
    assert calls == []

    cache.get_or_set("k", 60, producer)
    assert cache.peek("k", 60) == "value"
    assert len(calls) == 1


def test_rendered_cache_get_returns_none_when_cold():
    cache = RenderedCache(ttl=60)
    assert cache.get("nope") is None


def test_etag_is_stable_for_same_bytes():
    assert make_etag(b'{"a":1}') == make_etag(b'{"a":1}')


def test_etag_differs_for_different_bytes():
    assert make_etag(b'{"a":1}') != make_etag(b'{"a":2}')


@pytest.mark.parametrize(
    "header,expected",
    [
        (None, False),
        ("", False),
        ('"abc"', True),
        ('W/"abc"', True),
        ('"zzz", "abc"', True),
        ("*", True),
        ('"zzz"', False),
    ],
)
def test_etag_matches_variants(header, expected):
    assert etag_matches(header, '"abc"') is expected


# --- Integration: conditional responses ------------------------------------


def test_stats_returns_etag_header(client, linked_user):
    response = client.get("/user/stats", headers=linked_user)
    assert response.status_code == 200
    assert "etag" in {k.lower() for k in response.headers}
    assert response.json()["problems_solved"] == 3


def test_matching_etag_returns_304_with_no_body(client, linked_user):
    first = client.get("/user/stats", headers=linked_user)
    etag = first.headers["etag"]

    second = client.get(
        "/user/stats", headers={**linked_user, "If-None-Match": etag}
    )
    assert second.status_code == 304
    assert second.content == b""


def test_stale_etag_returns_full_200(client, linked_user):
    response = client.get(
        "/user/stats", headers={**linked_user, "If-None-Match": '"stale-value"'}
    )
    assert response.status_code == 200
    assert response.json()["problems_solved"] == 3


def test_304_short_circuits_before_rendering(client, linked_user, monkeypatch):
    """A conditional hit must not call Codeforces or rebuild the payload."""
    calls = []
    real_fetch = user_module.fetch_user_info

    def counting_fetch(handle):
        calls.append(handle)
        return real_fetch(handle)

    monkeypatch.setattr(user_module, "fetch_user_info", counting_fetch)

    first = client.get("/user/stats", headers=linked_user)
    assert len(calls) == 1
    etag = first.headers["etag"]

    second = client.get(
        "/user/stats", headers={**linked_user, "If-None-Match": etag}
    )
    assert second.status_code == 304
    # Still 1: the cache hit never reached the render function.
    assert len(calls) == 1


def test_repeated_uncached_reads_hit_cache_not_upstream(
    client, linked_user, monkeypatch
):
    calls = []
    real_fetch = user_module.fetch_user_info

    def counting_fetch(handle):
        calls.append(handle)
        return real_fetch(handle)

    monkeypatch.setattr(user_module, "fetch_user_info", counting_fetch)

    client.get("/user/stats", headers=linked_user)
    client.get("/user/stats", headers=linked_user)
    client.get("/user/stats", headers=linked_user)
    assert len(calls) == 1


def test_goals_cache_is_invalidated_by_put(client, linked_user):
    """A write must not be masked by a still-fresh cached body."""
    before = client.get("/user/goals", headers=linked_user)
    assert before.json()["target_rating"] is None

    updated = client.put(
        "/user/goals", json={"target_rating": 2500}, headers=linked_user
    )
    assert updated.json()["target_rating"] == 2500

    after = client.get("/user/goals", headers=linked_user)
    assert after.json()["target_rating"] == 2500
    # The ETag must change, since the body changed.
    assert after.headers["etag"] != before.headers["etag"]


def test_goals_cache_key_includes_target_rating(client, linked_user):
    """Different target values must not collide in the cache."""
    client.put("/user/goals", json={"target_rating": 2000}, headers=linked_user)
    first = client.get("/user/goals", headers=linked_user).json()

    client.put("/user/goals", json={"target_rating": 3000}, headers=linked_user)
    second = client.get("/user/goals", headers=linked_user).json()

    assert first["target_rating"] == 2000
    assert second["target_rating"] == 3000


def test_recent_submissions_cache_key_includes_limit(client, linked_user):
    two = client.get("/user/recent-submissions?limit=2", headers=linked_user).json()
    four = client.get("/user/recent-submissions?limit=4", headers=linked_user).json()

    assert len(two["submissions"]) == 2
    assert len(four["submissions"]) == 4


def test_cached_and_uncached_endpoints_do_not_collide(client, linked_user):
    """stats and goals share upstream data but must cache separately."""
    stats = client.get("/user/stats", headers=linked_user)
    goals = client.get("/user/goals", headers=linked_user)

    assert stats.status_code == 200
    assert goals.status_code == 200
    assert stats.headers["etag"] != goals.headers["etag"]
