"""Shared pytest fixtures.

Tests run against an in-memory SQLite database and a stubbed Codeforces
layer, so no Postgres server and no network access are required.
"""

import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# Make `app` importable when pytest is run from the backend directory.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import codeforces  # noqa: E402
from app.database import Base, get_db  # noqa: E402
from app.main import app as fastapi_app  # noqa: E402
from app import models  # noqa: E402,F401


@pytest.fixture
def db_session(monkeypatch):
    """A fresh in-memory SQLite database per test.

    StaticPool keeps a single connection alive so the schema survives across
    sessions — without it, each connection would get its own empty database.
    """
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    maker = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    # TestClient(app) runs the app lifespan, which calls create_all on the
    # *real* engine. Point the app's lazy engine at this SQLite instance so
    # startup never reaches for Postgres.
    from app import database

    monkeypatch.setattr(database, "_engine", engine)
    monkeypatch.setattr(database, "_SessionLocal", maker)

    session = maker()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


@pytest.fixture
def client(db_session):
    """TestClient with get_db overridden and caches cleared between tests."""

    def _override_get_db():
        try:
            yield db_session
        finally:
            pass

    fastapi_app.dependency_overrides[get_db] = _override_get_db

    # Caches are module-level singletons; without this, one test's cached
    # response would leak into the next.
    codeforces.clear_cache()
    from app.routers import stats as stats_module
    from app.routers import user as user_module

    user_module._dashboard_cache.clear()
    stats_module._derived_cache.clear()

    with TestClient(fastapi_app) as test_client:
        yield test_client

    fastapi_app.dependency_overrides.clear()


# --- Codeforces stub -------------------------------------------------------



def _submission(problem_id, name, rating, tags, day_offset=0, solved=True):
    from datetime import datetime, timedelta, timezone

    return codeforces.CfSubmission(
        problem_name=name,
        problem_id=problem_id,
        solved=solved,
        submitted_at=datetime.now(timezone.utc) - timedelta(days=day_offset),
        rating=rating,
        tags=tuple(tags),
    )


# Three solved problems across two days, one unsolved attempt.
FAKE_SUBMISSIONS = [
    _submission("100A", "Theatre Square", 1000, ["math"], day_offset=0),
    _submission("100B", "Fence", 1200, ["math", "dp"], day_offset=0),
    _submission("100C", "Binary Search", 1300, ["binary search"], day_offset=1),
    _submission("100D", "Nope", 1500, ["greedy"], day_offset=1, solved=False),
]

FAKE_RATING_HISTORY = [
    codeforces.CfRatingChange(
        date=__import__("datetime").datetime(2024, 1, 1, tzinfo=__import__("datetime").timezone.utc),
        new_rating=1100,
    ),
    codeforces.CfRatingChange(
        date=__import__("datetime").datetime(2024, 2, 1, tzinfo=__import__("datetime").timezone.utc),
        new_rating=1250,
    ),
]

# A small catalogue: 200A-C sit in a 1200-rated user's recommended band, 200D
# is too hard, 200E is unrated, and 100A-C are already solved (see above).
FAKE_PROBLEMS = [
    codeforces.CfProblem(100, "A", "Theatre Square", 1000, ("math",), 40000),
    codeforces.CfProblem(100, "B", "Fence", 1200, ("math", "dp"), 30000),
    codeforces.CfProblem(100, "C", "Binary Search", 1300, ("binary search",), 20000),
    codeforces.CfProblem(200, "A", "Queue Practice", 1100, ("greedy",), 5000),
    codeforces.CfProblem(200, "B", "Band Mid", 1200, ("dp",), 9000),
    codeforces.CfProblem(200, "C", "Band High", 1400, ("math", "binary search"), 3000),
    codeforces.CfProblem(200, "D", "Too Hard", 2000, ("graphs",), 1000),
    codeforces.CfProblem(200, "E", "Unrated Problem", None, (), 100),
    codeforces.CfProblem(200, "F", "April Fools", 1200, ("*special",), 8000),
]

_FAKE_NOW = __import__("datetime").datetime.now(
    __import__("datetime").timezone.utc
)

FAKE_CONTESTS = [
    codeforces.CfContest(
        3, "Future Round", "BEFORE", _FAKE_NOW + __import__("datetime").timedelta(days=2), 7200
    ),
    codeforces.CfContest(
        2, "Running Round", "CODING", _FAKE_NOW - __import__("datetime").timedelta(minutes=30), 7200
    ),
    codeforces.CfContest(
        1, "Past Round", "FINISHED", _FAKE_NOW - __import__("datetime").timedelta(days=7), 7200
    ),
    codeforces.CfContest(
        0, "Older Round", "FINISHED", _FAKE_NOW - __import__("datetime").timedelta(days=14), 7200
    ),
]


@pytest.fixture
def cf_stub(monkeypatch):
    """Replaces the Codeforces network layer with deterministic data.

    The returned dict holds the text reported as the user's profile name, so
    tests can simulate the user placing their verification code in their
    Codeforces profile.
    """
    state = {"profile": ""}

    def fake_user_info(handle, force_refresh=False):
        return codeforces.CfUserInfo(
            handle=handle,
            rating=3850,
            max_rating=3971,
            first_name=state["profile"] or None,
        )

    monkeypatch.setattr(codeforces, "fetch_user_info", fake_user_info)
    monkeypatch.setattr(
        codeforces, "fetch_submissions", lambda handle, count=500: list(FAKE_SUBMISSIONS)
    )
    monkeypatch.setattr(
        codeforces, "fetch_rating_history", lambda handle: list(FAKE_RATING_HISTORY)
    )
    monkeypatch.setattr(
        codeforces, "fetch_problemset_problems", lambda: list(FAKE_PROBLEMS)
    )
    monkeypatch.setattr(codeforces, "fetch_contest_list", lambda: list(FAKE_CONTESTS))
    for module_name in ("user", "stats", "practice", "contests"):
        module = __import__(f"app.routers.{module_name}", fromlist=["x"])
        for fn in (
            "fetch_user_info",
            "fetch_submissions",
            "fetch_rating_history",
            "fetch_problemset_problems",
            "fetch_contest_list",
        ):
            if hasattr(module, fn):
                monkeypatch.setattr(module, fn, getattr(codeforces, fn))
    return state


def link_handle(client, headers, handle, state, *, code_in_profile=True):
    """Runs the two-step ownership flow and returns the verify response."""
    start = client.post(
        "/user/link-codeforces/start", json={"handle": handle}, headers=headers
    )
    assert start.status_code == 200, start.text
    code = start.json()["verification_code"]
    if code_in_profile:
        state["profile"] = code
    return client.post(
        "/user/link-codeforces/verify", json={"code": code}, headers=headers
    )


def register_and_verify(client, email="a@b.com", password="secret123"):
    """Registers and completes email verification, returning auth headers."""
    response = client.post(
        "/auth/register", json={"email": email, "password": password}
    )
    assert response.status_code == 201, response.text
    body = response.json()
    verified = client.post(
        "/auth/verify-email",
        json={"email": email, "code": body["dev_verification_code"]},
    )
    assert verified.status_code == 200, verified.text
    return {"Authorization": f"Bearer {body['access_token']}"}


@pytest.fixture
def linked_user(client, cf_stub):
    """Registers a verified user, links a handle, returns auth headers."""
    headers = register_and_verify(client)
    linked = link_handle(client, headers, "tourist", cf_stub)
    assert linked.status_code == 200, linked.text
    return headers
