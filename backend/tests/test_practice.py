"""Practice recommendations built from the public problemset."""

import pytest

from app import codeforces
from tests.conftest import register_and_verify


@pytest.fixture
def practice_client(client, linked_user, cf_stub, monkeypatch):
    """A linked user rerated to 1200 so the fake bands are meaningful."""

    def fake_info(handle, force_refresh=False):
        return codeforces.CfUserInfo(handle=handle, rating=1200, max_rating=1400)

    from app.routers import practice as practice_module

    monkeypatch.setattr(codeforces, "fetch_user_info", fake_info)
    monkeypatch.setattr(practice_module, "fetch_user_info", fake_info)
    # Every request in these tests runs as the linked user.
    client.headers.update(linked_user)
    return client


def _ids(body):
    return {p["problem_id"] for p in body["problems"]}


def test_recommended_returns_unsolved_problems_near_rating(practice_client):
    response = practice_client.get("/practice/problems")

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["mode"] == "recommended"
    assert body["rating"] == 1200
    assert _ids(body) == {"200A", "200B", "200C"}
    # Most-solved problem in the closest band comes first.
    assert body["problems"][0]["problem_id"] == "200B"


def test_special_problems_are_never_recommended(practice_client):
    for mode in ("recommended", "unsolved", "random"):
        body = practice_client.get(f"/practice/problems?mode={mode}").json()
        assert "200F" not in _ids(body)


def test_recommended_excludes_unrated_and_hard_problems(practice_client):
    ids = _ids(practice_client.get("/practice/problems").json())

    assert "200D" not in ids
    assert "200E" not in ids


def test_harder_mode_starts_200_above_rating(practice_client):
    body = practice_client.get("/practice/problems?mode=harder").json()

    assert _ids(body) == {"200C", "200D"}


def test_unsolved_mode_is_sorted_by_rating(practice_client):
    body = practice_client.get("/practice/problems?mode=unsolved").json()

    ratings = [p["rating"] for p in body["problems"]]
    assert ratings == sorted(ratings)
    assert _ids(body) == {"200A", "200B", "200C", "200D"}


def test_random_mode_returns_only_unsolved_problems(practice_client):
    body = practice_client.get("/practice/problems?mode=random").json()

    assert _ids(body) == {"200A", "200B", "200C", "200D"}


def test_limit_is_honoured(practice_client):
    body = practice_client.get("/practice/problems?limit=2").json()

    assert len(body["problems"]) == 2


def test_problem_urls_point_at_codeforces(practice_client):
    body = practice_client.get("/practice/problems").json()

    for problem in body["problems"]:
        assert problem["url"].startswith(
            "https://codeforces.com/problemset/problem/"
        )


def test_invalid_mode_is_rejected(practice_client):
    assert practice_client.get("/practice/problems?mode=nope").status_code == 422


def test_practice_requires_a_linked_handle(client):
    headers = register_and_verify(client, "nohandle@user.com")

    response = client.get("/practice/problems", headers=headers)

    assert response.status_code == 404
    assert "Connect your Codeforces account" in response.json()["detail"]


def test_practice_returns_502_when_the_problemset_fails(
    practice_client, monkeypatch
):
    from app.routers import practice as practice_module

    def boom():
        raise codeforces.CodeforcesError("Codeforces is unreachable right now.")

    monkeypatch.setattr(practice_module, "fetch_problemset_problems", boom)

    response = practice_client.get("/practice/problems")

    assert response.status_code == 502
    assert "unreachable" in response.json()["detail"]
