"""Stats aggregation endpoints and their pure helper functions."""

import pytest

from app.routers.stats import _bucket_label, _bucket_sort_key
from app.routers.user import _streak_days


# --- Pure helpers ----------------------------------------------------------


@pytest.mark.parametrize(
    "rating,expected",
    [
        (700, "<800"),
        (800, "800-1000"),
        (999, "800-1000"),
        (1000, "1000-1200"),
        (1350, "1200-1400"),
        (2599, "2400-2600"),
        (2600, "2600+"),
        (3500, "2600+"),
    ],
)
def test_bucket_label(rating, expected):
    assert _bucket_label(rating) == expected


def test_bucket_sort_key_orders_numerically():
    labels = ["2600+", "1200-1400", "<800", "800-1000"]
    ordered = sorted(labels, key=_bucket_sort_key)
    assert ordered == ["<800", "800-1000", "1200-1400", "2600+"]


def test_streak_empty_is_zero():
    assert _streak_days([]) == 0


def test_streak_counts_consecutive_days():
    from datetime import date, datetime, timezone

    from app.codeforces import CfSubmission

    def sub(day_offset):
        return CfSubmission(
            problem_name="P",
            problem_id=f"P{day_offset}",
            solved=True,
            submitted_at=datetime(2026, 3, 10, tzinfo=timezone.utc)
            - __import__("datetime").timedelta(days=day_offset),
            rating=1000,
            tags=(),
        )

    assert _streak_days([sub(0)]) == 1
    assert _streak_days([sub(0), sub(1), sub(2)]) == 3
    # A gap breaks the run: today and day-2 do not form a 2-day streak.
    assert _streak_days([sub(0), sub(2)]) == 1
    # Multiple solves on one day still count as one day.
    assert _streak_days([sub(0), sub(0), sub(1)]) == 2


# --- Endpoints -------------------------------------------------------------


def test_rating_history_shape(client, linked_user):
    response = client.get("/stats/rating-history", headers=linked_user)
    assert response.status_code == 200
    points = response.json()["points"]
    assert len(points) == 2
    assert points[0]["rating"] == 1100
    assert points[1]["rating"] == 1250


def test_by_rating_buckets_only_solved(client, linked_user):
    response = client.get("/stats/by-rating", headers=linked_user)
    assert response.status_code == 200
    buckets = {b["bucket"]: b["solved"] for b in response.json()["buckets"]}

    # Solved: 1000 (100A), 1200 (100B), 1300 (100C). 1500 was unsolved.
    # Buckets are [lower, upper): 1000 -> "1000-1200", 1200/1300 -> "1200-1400".
    assert buckets == {"1000-1200": 1, "1200-1400": 2}


def test_by_rating_is_sorted_by_bucket(client, linked_user):
    buckets = client.get("/stats/by-rating", headers=linked_user).json()["buckets"]
    labels = [b["bucket"] for b in buckets]
    assert labels == sorted(labels, key=_bucket_sort_key)


def test_topics_counts_every_tag(client, linked_user):
    response = client.get("/stats/topics", headers=linked_user)
    assert response.status_code == 200
    topics = {t["topic"]: t["solved"] for t in response.json()["topics"]}

    assert topics["math"] == 2       # 100A and 100B
    assert topics["dp"] == 1
    assert topics["binary search"] == 1
    assert "greedy" not in topics    # 100D was unsolved


def test_topics_sorted_descending(client, linked_user):
    topics = client.get("/stats/topics", headers=linked_user).json()["topics"]
    counts = [t["solved"] for t in topics]
    assert counts == sorted(counts, reverse=True)


def test_stats_endpoints_are_cached(client, linked_user, monkeypatch):
    """Repeat calls must not re-hit the Codeforces layer."""
    from app.routers import stats as stats_module

    calls = []
    real = stats_module.fetch_rating_history

    def counting(handle):
        calls.append(handle)
        return real(handle)

    monkeypatch.setattr(stats_module, "fetch_rating_history", counting)

    client.get("/stats/rating-history", headers=linked_user)
    client.get("/stats/rating-history", headers=linked_user)
    assert len(calls) == 1


def test_codeforces_failure_maps_to_502(client, linked_user, monkeypatch):
    from app import codeforces
    from app.routers import stats as stats_module

    def boom(handle):
        raise codeforces.CodeforcesError("upstream down")

    monkeypatch.setattr(stats_module, "fetch_rating_history", boom)

    response = client.get("/stats/rating-history", headers=linked_user)
    assert response.status_code == 502


def test_codeforces_not_found_maps_to_404(client, linked_user, monkeypatch):
    from app import codeforces
    from app.routers import stats as stats_module

    def missing(handle):
        raise codeforces.CodeforcesError("no such handle", not_found=True)

    monkeypatch.setattr(stats_module, "fetch_rating_history", missing)

    response = client.get("/stats/rating-history", headers=linked_user)
    assert response.status_code == 404
