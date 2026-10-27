"""Client for the public Codeforces API (https://codeforces.com/apiHelp).

Every call is best-effort: network failures and unknown handles surface as
[CodeforcesError] so routers can translate them into proper HTTP responses.

Responses are memoised in-process with a short TTL (see [TtlCache]) so repeated
dashboard requests do not hammer Codeforces.
"""

import time
from dataclasses import dataclass
from datetime import datetime, timezone

import httpx

from app.cache import TtlCache

BASE_URL = "https://codeforces.com/api"
TIMEOUT = 15.0

# How long each kind of response stays fresh.
TTL_USER_INFO = 300.0        # 5 min — rating changes slowly
TTL_RATING_HISTORY = 900.0   # 15 min — only updates after a contest
TTL_SUBMISSIONS = 60.0       # 1 min — new submissions arrive often
TTL_PROBLEMSET = 21600.0     # 6 h — grows only when contests are published
TTL_CONTESTS = 600.0         # 10 min — phases/start times change

_cache = TtlCache()


class CodeforcesError(Exception):
    """Raised when Codeforces rejects a request or cannot be reached."""

    def __init__(self, message: str, *, not_found: bool = False):
        super().__init__(message)
        self.not_found = not_found


def clear_cache() -> None:
    """Drops all cached Codeforces responses (used by tests)."""
    _cache.clear()


@dataclass(frozen=True)
class CfUserInfo:
    handle: str
    rating: int
    max_rating: int
    # Profile fields used to prove handle ownership. Codeforces exposes these
    # publicly through user.info; they are absent when the profile is blank.
    first_name: str | None = None
    last_name: str | None = None
    organization: str | None = None


@dataclass(frozen=True)
class CfRatingChange:
    date: datetime
    new_rating: int


@dataclass(frozen=True)
class CfSubmission:
    problem_name: str
    problem_id: str
    solved: bool
    submitted_at: datetime
    rating: int | None
    tags: tuple[str, ...]


@dataclass(frozen=True)
class CfProblem:
    """A problem from the public problemset catalogue."""

    contest_id: int | None
    index: str
    name: str
    rating: int | None
    tags: tuple[str, ...]
    solved_count: int | None = None

    @property
    def problem_id(self) -> str:
        if self.contest_id is None:
            return self.index
        return f"{self.contest_id}{self.index}"


@dataclass(frozen=True)
class CfContest:
    id: int
    name: str
    phase: str
    start_time: datetime
    duration_seconds: int


# Codeforces rate-limits bursts and occasionally drops a request. Retry those
# transient failures a couple of times before surfacing an error to the user.
RETRIES = 3
RETRY_BACKOFF = 0.5


def _get(path: str, params: dict[str, str]) -> dict:
    last_error: Exception | None = None

    for attempt in range(RETRIES):
        try:
            response = httpx.get(f"{BASE_URL}/{path}", params=params, timeout=TIMEOUT)
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            transient = exc.response.status_code == 429 or exc.response.status_code >= 500
            if transient and attempt < RETRIES - 1:
                last_error = exc
                time.sleep(RETRY_BACKOFF * (2**attempt))
                continue
            raise CodeforcesError("Codeforces is unreachable right now.") from exc
        except httpx.HTTPError as exc:
            if attempt < RETRIES - 1:
                last_error = exc
                time.sleep(RETRY_BACKOFF * (2**attempt))
                continue
            raise CodeforcesError("Codeforces is unreachable right now.") from exc

        try:
            payload = response.json()
        except ValueError as exc:
            raise CodeforcesError("Codeforces returned an invalid response.") from exc

        if payload.get("status") != "OK":
            comment = payload.get("comment", "")
            # CF reports its own rate limit as a 200/FAILED payload.
            if "limit" in comment.lower() and attempt < RETRIES - 1:
                time.sleep(RETRY_BACKOFF * (2**attempt))
                continue
            raise CodeforcesError(
                comment or "Codeforces rejected the request.",
                not_found="not found" in comment.lower(),
            )
        return payload

    raise CodeforcesError("Codeforces is unreachable right now.") from last_error


def fetch_user_info(handle: str, *, force_refresh: bool = False) -> CfUserInfo:
    """Cached: Codeforces user rating snapshot.

    [force_refresh] bypasses the TTL cache, which ownership verification needs
    because the user edits their profile moments before we re-read it.
    """
    key = ("user.info", handle)
    if force_refresh:
        _cache.delete(key)
    return _cache.get_or_set(
        key,
        TTL_USER_INFO,
        lambda: _fetch_user_info(handle),
    )


def _fetch_user_info(handle: str) -> CfUserInfo:
    payload = _get("user.info", {"handles": handle})
    results = payload.get("result") or []
    if not results:
        raise CodeforcesError(f"Handle '{handle}' was not found.", not_found=True)

    entry = results[0]
    rating = entry.get("rating")
    if rating is None:
        raise CodeforcesError(
            f"'{handle}' has no rating history yet (unrated account).",
            not_found=True,
        )
    return CfUserInfo(
        handle=entry["handle"],
        rating=int(rating),
        max_rating=int(entry.get("maxRating", rating)),
        first_name=entry.get("firstName"),
        last_name=entry.get("lastName"),
        organization=entry.get("organization"),
    )


def fetch_rating_history(handle: str) -> list[CfRatingChange]:
    """Cached: full rating-change history, oldest first."""
    return _cache.get_or_set(
        ("user.rating", handle),
        TTL_RATING_HISTORY,
        lambda: _fetch_rating_history(handle),
    )


def _fetch_rating_history(handle: str) -> list[CfRatingChange]:
    payload = _get("user.rating", {"handle": handle})
    changes = []
    for entry in payload.get("result") or []:
        changes.append(
            CfRatingChange(
                date=datetime.fromtimestamp(
                    entry["ratingUpdateTimeSeconds"], tz=timezone.utc
                ),
                new_rating=int(entry["newRating"]),
            )
        )
    changes.sort(key=lambda c: c.date)
    return changes


def fetch_submissions(handle: str, count: int = 500) -> list[CfSubmission]:
    """Cached: most recent submissions, newest first.

    The cache key includes [count] because different callers request different
    depths (the dashboard wants 20, the stats endpoints want 500).
    """
    return _cache.get_or_set(
        ("user.status", handle, count),
        TTL_SUBMISSIONS,
        lambda: _fetch_submissions(handle, count),
    )


def _fetch_submissions(handle: str, count: int = 500) -> list[CfSubmission]:
    payload = _get("user.status", {"handle": handle, "from": "1", "count": str(count)})
    submissions = []
    for entry in payload.get("result") or []:
        problem = entry.get("problem", {})
        tags = tuple(problem.get("tags", []) or ())
        submissions.append(
            CfSubmission(
                problem_name=problem.get("name", "Unknown"),
                problem_id=_problem_id(problem),
                solved=entry.get("verdict") == "OK",
                submitted_at=datetime.fromtimestamp(
                    entry["creationTimeSeconds"], tz=timezone.utc
                ),
                rating=problem.get("rating"),
                tags=tags,
            )
        )
    return submissions


def _problem_id(problem: dict) -> str:
    """Formats a problem as its Codeforces id, e.g. '1920B'."""
    contest_id = problem.get("contestId")
    index = problem.get("index", "")
    if contest_id is None:
        return str(index)
    return f"{contest_id}{index}"


def fetch_problemset_problems() -> list[CfProblem]:
    """Cached: the full public problemset catalogue."""
    return _cache.get_or_set(
        ("problemset.problems",),
        TTL_PROBLEMSET,
        _fetch_problemset_problems,
    )


def _fetch_problemset_problems() -> list[CfProblem]:
    payload = _get("problemset.problems", {})
    result = payload.get("result") or {}
    statistics = {
        (entry.get("contestId"), entry.get("index")): entry.get("solvedCount")
        for entry in result.get("problemStatistics") or []
    }
    problems = []
    for entry in result.get("problems") or []:
        key = (entry.get("contestId"), entry.get("index"))
        problems.append(
            CfProblem(
                contest_id=entry.get("contestId"),
                index=str(entry.get("index", "")),
                name=entry.get("name", "Unknown"),
                rating=entry.get("rating"),
                tags=tuple(entry.get("tags", []) or ()),
                solved_count=statistics.get(key),
            )
        )
    return problems


def fetch_contest_list() -> list[CfContest]:
    """Cached: every regular Codeforces contest with its current phase."""
    return _cache.get_or_set(("contest.list",), TTL_CONTESTS, _fetch_contest_list)


def _fetch_contest_list() -> list[CfContest]:
    payload = _get("contest.list", {"gym": "false"})
    contests = []
    for entry in payload.get("result") or []:
        contests.append(
            CfContest(
                id=int(entry["id"]),
                name=entry.get("name", "Unknown"),
                phase=entry.get("phase", ""),
                start_time=datetime.fromtimestamp(
                    entry["startTimeSeconds"], tz=timezone.utc
                ),
                duration_seconds=int(entry.get("durationSeconds", 0)),
            )
        )
    return contests
