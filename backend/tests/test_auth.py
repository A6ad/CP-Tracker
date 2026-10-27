"""Auth flow: register, login, refresh, and token-type enforcement."""

from app.security import create_access_token, create_refresh_token, decode_token


def test_register_returns_tokens_and_user(client):
    response = client.post(
        "/auth/register", json={"email": "new@user.com", "password": "secret123"}
    )
    assert response.status_code == 201
    body = response.json()

    assert body["user"]["email"] == "new@user.com"
    assert body["token_type"] == "bearer"
    assert body["access_token"]
    assert body["refresh_token"]


def test_register_duplicate_email_conflicts(client):
    payload = {"email": "dup@user.com", "password": "secret123"}
    assert client.post("/auth/register", json=payload).status_code == 201

    second = client.post("/auth/register", json=payload)
    assert second.status_code == 409
    assert "already exists" in second.json()["detail"]


def test_register_rejects_short_password(client):
    response = client.post(
        "/auth/register", json={"email": "x@y.com", "password": "short"}
    )
    assert response.status_code == 422


def test_login_succeeds_with_correct_password(client):
    client.post("/auth/register", json={"email": "a@b.com", "password": "secret123"})

    response = client.post(
        "/auth/login", json={"email": "a@b.com", "password": "secret123"}
    )
    assert response.status_code == 200
    assert response.json()["access_token"]


def test_login_rejects_wrong_password(client):
    client.post("/auth/register", json={"email": "a@b.com", "password": "secret123"})

    response = client.post(
        "/auth/login", json={"email": "a@b.com", "password": "wrongpass"}
    )
    assert response.status_code == 401


def test_login_rejects_unknown_email(client):
    response = client.post(
        "/auth/login", json={"email": "nobody@b.com", "password": "secret123"}
    )
    assert response.status_code == 401


def test_login_is_case_insensitive_on_email(client):
    client.post("/auth/register", json={"email": "Mixed@Case.com", "password": "secret123"})

    response = client.post(
        "/auth/login", json={"email": "mixed@case.com", "password": "secret123"}
    )
    assert response.status_code == 200
    assert response.json()["user"]["email"] == "mixed@case.com"


def test_login_ignores_surrounding_whitespace(client):
    client.post("/auth/register", json={"email": "space@user.com", "password": "secret123"})

    response = client.post(
        "/auth/login", json={"email": "  space@user.com ", "password": "secret123"}
    )
    assert response.status_code == 200


def test_register_duplicate_ignores_email_case(client):
    payload = {"email": "Dup@Case.com", "password": "secret123"}
    assert client.post("/auth/register", json=payload).status_code == 201

    second = client.post(
        "/auth/register", json={"email": "dup@case.com", "password": "secret123"}
    )
    assert second.status_code == 409



def test_refresh_issues_a_new_pair(client):
    registered = client.post(
        "/auth/register", json={"email": "a@b.com", "password": "secret123"}
    ).json()

    response = client.post(
        "/auth/refresh", json={"refresh_token": registered["refresh_token"]}
    )
    assert response.status_code == 200
    refreshed = response.json()
    assert refreshed["access_token"]
    assert refreshed["user"]["email"] == "a@b.com"


def test_refresh_rejects_access_token(client):
    """An access token must not be usable as a refresh token."""
    registered = client.post(
        "/auth/register", json={"email": "a@b.com", "password": "secret123"}
    ).json()

    response = client.post(
        "/auth/refresh", json={"refresh_token": registered["access_token"]}
    )
    assert response.status_code == 401


def test_refresh_rejects_garbage(client):
    response = client.post("/auth/refresh", json={"refresh_token": "not-a-jwt"})
    assert response.status_code == 401


def test_token_type_claims_are_distinct():
    access = create_access_token(1)
    refresh = create_refresh_token(1)

    assert decode_token(access, "access") == 1
    assert decode_token(access, "refresh") is None
    assert decode_token(refresh, "refresh") == 1
    assert decode_token(refresh, "access") is None


def test_protected_route_requires_token(client):
    """Missing credentials yield 401, not 403."""
    assert client.get("/user/me").status_code == 401


def test_protected_route_rejects_bad_token(client):
    response = client.get(
        "/user/me", headers={"Authorization": "Bearer not-a-real-token"}
    )
    assert response.status_code == 401
