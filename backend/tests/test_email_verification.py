"""Email verification: registration, code checks, resend, and the linking gate."""

from datetime import datetime, timedelta, timezone

from app.models import User

PASSWORD = "secret123"


def _register(client, email="new@user.com"):
    response = client.post(
        "/auth/register", json={"email": email, "password": PASSWORD}
    )
    assert response.status_code == 201, response.text
    return response.json()


def _verify(client, email, code):
    return client.post(
        "/auth/verify-email", json={"email": email, "code": code}
    )


def test_register_returns_unverified_user_and_dev_code(client):
    body = _register(client)

    assert body["user"]["email_verified"] is False
    assert body["dev_verification_code"] is not None
    assert len(body["dev_verification_code"]) == 6


def test_verify_email_marks_the_account_verified(client):
    body = _register(client)

    response = _verify(client, "new@user.com", body["dev_verification_code"])

    assert response.status_code == 200
    assert response.json()["email_verified"] is True

    login = client.post(
        "/auth/login", json={"email": "new@user.com", "password": PASSWORD}
    )
    assert login.json()["user"]["email_verified"] is True


def test_verify_email_rejects_wrong_code(client):
    body = _register(client)
    wrong = "000000" if body["dev_verification_code"] != "000000" else "111111"

    response = _verify(client, "new@user.com", wrong)

    assert response.status_code == 400
    login = client.post(
        "/auth/login", json={"email": "new@user.com", "password": PASSWORD}
    )
    assert login.json()["user"]["email_verified"] is False


def test_verify_email_rejects_expired_code(client, db_session):
    body = _register(client)
    user = db_session.query(User).filter_by(email="new@user.com").one()
    user.email_verification_expires_at = datetime.now(timezone.utc) - timedelta(
        minutes=1
    )
    db_session.commit()

    response = _verify(client, "new@user.com", body["dev_verification_code"])

    assert response.status_code == 400


def test_verify_email_locks_after_too_many_attempts(client):
    body = _register(client)
    wrong = "000000" if body["dev_verification_code"] != "000000" else "111111"

    for _ in range(5):
        assert _verify(client, "new@user.com", wrong).status_code == 400

    response = _verify(client, "new@user.com", body["dev_verification_code"])

    assert response.status_code == 400
    assert "Too many" in response.json()["detail"]


def test_verify_email_is_idempotent(client):
    body = _register(client)

    assert _verify(client, "new@user.com", body["dev_verification_code"]).status_code == 200
    assert _verify(client, "new@user.com", body["dev_verification_code"]).status_code == 200


def test_verify_email_rejects_unknown_address(client):
    response = _verify(client, "nobody@user.com", "123456")

    assert response.status_code == 400


def test_unverified_user_cannot_link_a_handle(client, cf_stub):
    body = _register(client)
    headers = {"Authorization": f"Bearer {body['access_token']}"}

    response = client.post(
        "/user/link-codeforces/start", json={"handle": "tourist"}, headers=headers
    )

    assert response.status_code == 403
    assert "verify your email" in response.json()["detail"].lower()


def test_resend_issues_a_usable_new_code(client, db_session):
    _register(client)
    user = db_session.query(User).filter_by(email="new@user.com").one()
    user.email_verification_sent_at = datetime.now(timezone.utc) - timedelta(
        minutes=2
    )
    db_session.commit()

    response = client.post(
        "/auth/resend-verification", json={"email": "new@user.com"}
    )

    assert response.status_code == 200
    new_code = response.json()["dev_verification_code"]
    assert new_code is not None
    assert _verify(client, "new@user.com", new_code).status_code == 200


def test_resend_is_throttled(client):
    _register(client)

    response = client.post(
        "/auth/resend-verification", json={"email": "new@user.com"}
    )

    assert response.status_code == 200
    assert response.json()["dev_verification_code"] is None


def test_resend_does_not_reveal_unknown_addresses(client):
    response = client.post(
        "/auth/resend-verification", json={"email": "nobody@user.com"}
    )

    assert response.status_code == 200
    assert response.json()["dev_verification_code"] is None
