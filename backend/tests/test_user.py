"""User endpoints: linking, stats, goals, and recent submissions."""

from tests.conftest import FAKE_SUBMISSIONS, link_handle


def test_me_returns_the_authenticated_user(client):
    registered = client.post(
        "/auth/register", json={"email": "a@b.com", "password": "secret123"}
    ).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}

    response = client.get("/user/me", headers=headers)
    assert response.status_code == 200
    assert response.json()["email"] == "a@b.com"
    assert response.json()["codeforces_handle"] is None


def _auth_headers(client, email="a@b.com"):
    registered = client.post(
        "/auth/register", json={"email": email, "password": "secret123"}
    ).json()
    verified = client.post(
        "/auth/verify-email",
        json={"email": email, "code": registered["dev_verification_code"]},
    )
    assert verified.status_code == 200, verified.text
    return {"Authorization": f"Bearer {registered['access_token']}"}


def test_link_requires_profile_verification(client, cf_stub):
    """A correct code alone is not enough: it must be in the CF profile."""
    headers = _auth_headers(client)

    start = client.post(
        "/user/link-codeforces/start", json={"handle": "tourist"}, headers=headers
    )
    assert start.status_code == 200
    code = start.json()["verification_code"]

    response = client.post(
        "/user/link-codeforces/verify", json={"code": code}, headers=headers
    )
    assert response.status_code == 400
    assert client.get("/user/me", headers=headers).json()["codeforces_handle"] is None


def test_link_succeeds_when_code_is_in_profile(client, cf_stub):
    headers = _auth_headers(client)

    response = link_handle(client, headers, "tourist", cf_stub)

    assert response.status_code == 200
    assert response.json()["codeforces_handle"] == "tourist"
    # Ratings come from the (stubbed) Codeforces lookup.
    assert response.json()["current_rating"] == 3850


def test_verify_rejects_wrong_code(client, cf_stub):
    headers = _auth_headers(client)
    start = client.post(
        "/user/link-codeforces/start", json={"handle": "tourist"}, headers=headers
    )
    cf_stub["profile"] = start.json()["verification_code"]

    response = client.post(
        "/user/link-codeforces/verify", json={"code": "CPT-WRONG0"}, headers=headers
    )
    assert response.status_code == 400


def test_verify_without_start_is_rejected(client, cf_stub):
    headers = _auth_headers(client)

    response = client.post(
        "/user/link-codeforces/verify", json={"code": "CPT-ABC123"}, headers=headers
    )
    assert response.status_code == 400


def test_start_rejects_unknown_handle(client, monkeypatch):
    from app import codeforces

    def raise_not_found(handle, force_refresh=False):
        raise codeforces.CodeforcesError("Handle not found.", not_found=True)

    monkeypatch.setattr(codeforces, "fetch_user_info", raise_not_found)
    from app.routers import user as user_module

    monkeypatch.setattr(user_module, "fetch_user_info", raise_not_found)

    headers = _auth_headers(client)

    response = client.post(
        "/user/link-codeforces/start", json={"handle": "nope"}, headers=headers
    )
    assert response.status_code == 404


def test_start_rejects_handle_owned_by_another_account(client, cf_stub):
    first = _auth_headers(client, "one@b.com")
    second = _auth_headers(client, "two@b.com")

    assert link_handle(client, first, "tourist", cf_stub).status_code == 200

    conflict = client.post(
        "/user/link-codeforces/start", json={"handle": "tourist"}, headers=second
    )
    assert conflict.status_code == 409

    # Handles are case-insensitive, so a different casing is the same owner.
    conflict_upper = client.post(
        "/user/link-codeforces/start", json={"handle": "TOURIST"}, headers=second
    )
    assert conflict_upper.status_code == 409


def test_stats_endpoints_require_a_linked_handle(client):
    """Every /user and /stats data route 404s before a handle is linked."""
    registered = client.post(
        "/auth/register", json={"email": "a@b.com", "password": "secret123"}
    ).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}

    for path in (
        "/user/stats",
        "/user/goals",
        "/user/recent-submissions",
    ):
        assert client.get(path, headers=headers).status_code == 404

    for path in (
        "/stats/rating-history",
        "/stats/by-rating",
        "/stats/topics",
    ):
        assert client.get(path, headers=headers).status_code == 404


def test_stats_counts_solved_problems(client, linked_user):
    response = client.get("/user/stats", headers=linked_user)
    assert response.status_code == 200
    body = response.json()

    assert body["current_rating"] == 3850
    assert body["max_rating"] == 3971
    # 4 submissions, 1 unsolved -> 3 solved
    assert body["problems_solved"] == 3


def test_goals_reflects_target_rating(client, linked_user):
    before = client.get("/user/goals", headers=linked_user).json()
    assert before["target_rating"] is None
    assert before["current_rating"] == 3850

    updated = client.put(
        "/user/goals", json={"target_rating": 4000}, headers=linked_user
    )
    assert updated.status_code == 200
    assert updated.json()["target_rating"] == 4000

    after = client.get("/user/goals", headers=linked_user).json()
    assert after["target_rating"] == 4000


def test_goals_can_be_cleared(client, linked_user):
    client.put("/user/goals", json={"target_rating": 1600}, headers=linked_user)

    cleared = client.put(
        "/user/goals", json={"target_rating": None}, headers=linked_user
    )
    assert cleared.status_code == 200
    assert cleared.json()["target_rating"] is None


def test_goals_rejects_out_of_range_target(client, linked_user):
    response = client.put(
        "/user/goals", json={"target_rating": 99999}, headers=linked_user
    )
    assert response.status_code == 422


def test_recent_submissions_honours_limit(client, linked_user):
    response = client.get("/user/recent-submissions?limit=2", headers=linked_user)
    assert response.status_code == 200
    assert len(response.json()["submissions"]) == 2


def test_recent_submissions_newest_first(client, linked_user):
    response = client.get("/user/recent-submissions?limit=4", headers=linked_user)
    times = [s["submitted_at"] for s in response.json()["submissions"]]
    assert times == sorted(times, reverse=True)


def test_recent_submissions_rejects_bad_limit(client, linked_user):
    assert (
        client.get("/user/recent-submissions?limit=0", headers=linked_user).status_code
        == 422
    )
    assert (
        client.get("/user/recent-submissions?limit=999", headers=linked_user).status_code
        == 422
    )


def test_solved_problems_are_deduplicated(client, linked_user, monkeypatch):
    """The same problem submitted twice must count once."""
    from app import codeforces
    from app.routers import user as user_module

    duplicate = list(FAKE_SUBMISSIONS) + [
        FAKE_SUBMISSIONS[0]  # a second AC on 100A
    ]
    monkeypatch.setattr(user_module, "fetch_submissions", lambda h, count=500: duplicate)

    response = client.get("/user/stats", headers=linked_user)
    assert response.json()["problems_solved"] == 3
