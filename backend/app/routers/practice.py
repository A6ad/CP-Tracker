"""Practice recommendations built from the public Codeforces problemset.

Only problems the user has not solved are returned, so the list stays useful
without any extra state: the catalogue is public and the solved set comes from
the user's recent submissions.
"""

import random
from typing import Literal

from fastapi import APIRouter, Depends, Query

from app.codeforces import (
    CodeforcesError,
    fetch_problemset_problems,
    fetch_user_info,
)
from app.deps import get_current_user
from app.models import User
from app.routers.user import _cf_http_error, _require_handle, _solved_problems
from app.schemas import PracticeProblemSchema, PracticeResponse

router = APIRouter(prefix="/practice", tags=["practice"])

# Used for unrated accounts so beginners still get an easy starting band.
DEFAULT_RATING = 800

# Fetch deep enough to catch older solved problems, not just the latest page.
SOLVED_HISTORY = 2000

PracticeMode = Literal["recommended", "unsolved", "harder", "random"]


def _problem_url(contest_id: int | None, index: str) -> str:
    if contest_id is None:
        return "https://codeforces.com/problemset"
    return f"https://codeforces.com/problemset/problem/{contest_id}/{index}"


@router.get("/problems", response_model=PracticeResponse)
def problems(
    mode: PracticeMode = "recommended",
    limit: int = Query(default=20, ge=1, le=50),
    user: User = Depends(get_current_user),
):
    handle = _require_handle(user)

    try:
        info = fetch_user_info(handle)
        rating = info.rating
    except CodeforcesError as exc:
        # An unrated handle is a valid starting point, not an error.
        if not exc.not_found:
            raise _cf_http_error(exc) from exc
        rating = DEFAULT_RATING

    try:
        solved = {s.problem_id for s in _solved_problems(handle, SOLVED_HISTORY)}
        catalogue = fetch_problemset_problems()
    except CodeforcesError as exc:
        raise _cf_http_error(exc) from exc

    unsolved = [
        p
        for p in catalogue
        if p.rating is not None
        and p.problem_id not in solved
        # "*special" marks experimental/April-Fools problems, not practice.
        and "*special" not in p.tags
    ]

    if mode == "recommended":
        low, high = rating - 200, rating + 300
        pool = [p for p in unsolved if low <= p.rating <= high]
        pool.sort(
            key=lambda p: (
                abs(p.rating - (rating + 100)),
                -(p.solved_count or 0),
                p.problem_id,
            )
        )
        if not pool:
            # High-rated accounts may have solved the whole band; fall back to
            # the closest difficulty instead of showing an empty screen.
            pool = sorted(
                unsolved, key=lambda p: (abs(p.rating - rating), p.problem_id)
            )
    elif mode == "harder":
        pool = [p for p in unsolved if p.rating >= rating + 200]
        pool.sort(key=lambda p: (p.rating, -(p.solved_count or 0), p.problem_id))
    elif mode == "random":
        pool = list(unsolved)
        random.shuffle(pool)
    else:  # unsolved
        pool = sorted(
            unsolved,
            key=lambda p: (p.rating, -(p.solved_count or 0), p.problem_id),
        )

    picked = pool[:limit]
    return PracticeResponse(
        mode=mode,
        rating=rating,
        problems=[
            PracticeProblemSchema(
                problem_id=p.problem_id,
                contest_id=p.contest_id,
                index=p.index,
                name=p.name,
                rating=p.rating,
                tags=list(p.tags),
                url=_problem_url(p.contest_id, p.index),
            )
            for p in picked
        ],
    )
