"""Upcoming and recent Codeforces contests from the public contest list."""

from fastapi import APIRouter, HTTPException, Query, status

from app.codeforces import CfContest, CodeforcesError, fetch_contest_list
from app.schemas import ContestSchema, ContestsResponse

router = APIRouter(prefix="/contests", tags=["contests"])

# A contest that is currently running belongs at the top of "Upcoming".
_UPCOMING_PHASES = {"BEFORE", "CODING"}


def _contest_url(contest_id: int) -> str:
    return f"https://codeforces.com/contest/{contest_id}"


def _schema(contest: CfContest) -> ContestSchema:
    return ContestSchema(
        id=contest.id,
        name=contest.name,
        phase=contest.phase,
        start_time=contest.start_time.isoformat(),
        duration_seconds=contest.duration_seconds,
        url=_contest_url(contest.id),
    )


@router.get("", response_model=ContestsResponse)
def contests(limit: int = Query(default=20, ge=1, le=50)):
    try:
        catalogue = fetch_contest_list()
    except CodeforcesError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    upcoming = sorted(
        (c for c in catalogue if c.phase in _UPCOMING_PHASES),
        key=lambda c: c.start_time,
    )
    finished = sorted(
        (c for c in catalogue if c.phase == "FINISHED"),
        key=lambda c: c.start_time,
        reverse=True,
    )

    return ContestsResponse(
        upcoming=[_schema(c) for c in upcoming[:limit]],
        finished=[_schema(c) for c in finished[:limit]],
    )
