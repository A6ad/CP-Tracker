"""Upcoming and recent contests from the public contest list."""

from app import codeforces


def test_lists_upcoming_and_finished(client, cf_stub):
    response = client.get("/contests")

    assert response.status_code == 200
    body = response.json()
    assert [c["name"] for c in body["upcoming"]] == [
        "Running Round",
        "Future Round",
    ]
    assert [c["name"] for c in body["finished"]] == [
        "Past Round",
        "Older Round",
    ]


def test_contest_payload_has_link_and_times(client, cf_stub):
    body = client.get("/contests").json()

    running = body["upcoming"][0]
    assert running["phase"] == "CODING"
    assert running["url"] == "https://codeforces.com/contest/2"
    assert running["start_time"]
    assert running["duration_seconds"] == 7200


def test_limit_applies_per_section(client, cf_stub):
    body = client.get("/contests?limit=1").json()

    assert len(body["upcoming"]) == 1
    assert len(body["finished"]) == 1


def test_limit_validation(client, cf_stub):
    assert client.get("/contests?limit=0").status_code == 422
    assert client.get("/contests?limit=51").status_code == 422


def test_returns_502_when_codeforces_fails(client, cf_stub, monkeypatch):
    from app.routers import contests as contests_module

    def boom():
        raise codeforces.CodeforcesError("Codeforces is unreachable right now.")

    monkeypatch.setattr(contests_module, "fetch_contest_list", boom)

    response = client.get("/contests")

    assert response.status_code == 502
    assert "unreachable" in response.json()["detail"]
