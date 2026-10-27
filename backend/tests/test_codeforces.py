"""Unit tests for the Codeforces HTTP client's retry behaviour."""

import httpx
import pytest

from app import codeforces


class FakeResponse:
    def __init__(self, payload=None, *, status_code=200, bad_json=False):
        self._payload = payload
        self.status_code = status_code
        self._bad_json = bad_json

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPStatusError(
                "error",
                request=httpx.Request("GET", "http://example.test"),
                response=self,
            )

    def json(self):
        if self._bad_json:
            raise ValueError("not json")
        return self._payload


def _stub(monkeypatch, responses):
    calls = []

    def fake_get(*args, **kwargs):
        calls.append(1)
        return responses.pop(0)

    monkeypatch.setattr(codeforces.httpx, "get", fake_get)
    monkeypatch.setattr(codeforces.time, "sleep", lambda _: None)
    return calls


def test_get_retries_codeforces_rate_limit(monkeypatch):
    calls = _stub(
        monkeypatch,
        [
            FakeResponse({"status": "FAILED", "comment": "Call limit exceeded"}),
            FakeResponse({"status": "OK", "result": [1]}),
        ],
    )

    payload = codeforces._get("user.info", {"handles": "x"})

    assert payload["result"] == [1]
    assert len(calls) == 2


def test_get_retries_http_429(monkeypatch):
    calls = _stub(
        monkeypatch,
        [
            FakeResponse(status_code=429),
            FakeResponse({"status": "OK", "result": []}),
        ],
    )

    assert codeforces._get("user.info", {"handles": "x"})["status"] == "OK"
    assert len(calls) == 2


def test_get_gives_up_after_retries(monkeypatch):
    def boom(*args, **kwargs):
        raise httpx.ConnectError("down")

    monkeypatch.setattr(codeforces.httpx, "get", boom)
    monkeypatch.setattr(codeforces.time, "sleep", lambda _: None)

    with pytest.raises(codeforces.CodeforcesError, match="unreachable"):
        codeforces._get("user.info", {"handles": "x"})


def test_get_marks_unknown_handle_as_not_found(monkeypatch):
    _stub(
        monkeypatch,
        [
            FakeResponse(
                {
                    "status": "FAILED",
                    "comment": "handles: User with handle nope not found",
                }
            )
        ],
    )

    with pytest.raises(codeforces.CodeforcesError) as excinfo:
        codeforces._get("user.info", {"handles": "nope"})

    assert excinfo.value.not_found is True


def test_get_does_not_retry_non_transient_http_error(monkeypatch):
    calls = _stub(monkeypatch, [FakeResponse(status_code=404)])

    with pytest.raises(codeforces.CodeforcesError):
        codeforces._get("user.info", {"handles": "x"})

    assert len(calls) == 1


def test_get_rejects_invalid_json(monkeypatch):
    _stub(monkeypatch, [FakeResponse(bad_json=True)])

    with pytest.raises(codeforces.CodeforcesError, match="invalid response"):
        codeforces._get("user.info", {"handles": "x"})


def test_problemset_parsing_builds_ids_and_tags(monkeypatch):
    monkeypatch.setattr(
        codeforces,
        "_get",
        lambda path, params: {
            "status": "OK",
            "result": {
                "problems": [
                    {
                        "contestId": 1920,
                        "index": "B",
                        "name": "Array Craft",
                        "rating": 1200,
                        "tags": ["constructive", "greedy"],
                    },
                    {"index": "A", "name": "No Contest"},
                ],
                "problemStatistics": [
                    {"contestId": 1920, "index": "B", "solvedCount": 12345}
                ],
            },
        },
    )

    problems = codeforces._fetch_problemset_problems()

    assert problems[0].problem_id == "1920B"
    assert problems[0].tags == ("constructive", "greedy")
    assert problems[0].solved_count == 12345
    assert problems[1].problem_id == "A"
    assert problems[1].rating is None


def test_contest_list_parsing_converts_start_times(monkeypatch):
    monkeypatch.setattr(
        codeforces,
        "_get",
        lambda path, params: {
            "status": "OK",
            "result": [
                {
                    "id": 2000,
                    "name": "Round 2000",
                    "phase": "BEFORE",
                    "startTimeSeconds": 1_700_000_000,
                    "durationSeconds": 7200,
                }
            ],
        },
    )

    contests = codeforces._fetch_contest_list()

    assert contests[0].id == 2000
    assert contests[0].start_time.tzinfo is not None
    assert contests[0].duration_seconds == 7200
