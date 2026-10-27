import secrets
from datetime import datetime, timedelta, timezone
from typing import Callable

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.cache import RenderedCache, conditional_response, render_model
from app.codeforces import (
    CodeforcesError,
    TTL_SUBMISSIONS,
    fetch_submissions,
    fetch_user_info,
)
from app.database import get_db
from app.deps import get_current_user, require_verified
from app.models import User
from app.routers.auth import _user_response
from app.schemas import (
    GoalsResponse,
    LinkCodeforcesRequest,
    LinkStartResponse,
    RecentSubmissionsResponse,
    StatsResponse,
    SubmissionSchema,
    UpdateGoalsRequest,
    UserResponse,
    VerifyCodeforcesRequest,
)

router = APIRouter(prefix="/user", tags=["user"])

# Caches the serialised dashboard responses so a conditional request with a
# matching ETag is answered from bytes — no Codeforces call, no model rebuild.
# TTLs mirror the underlying upstream TTLs in app.codeforces.
_dashboard_cache = RenderedCache(ttl=TTL_SUBMISSIONS)


def _cf_http_error(exc: CodeforcesError) -> HTTPException:
    return HTTPException(
        status_code=(
            status.HTTP_404_NOT_FOUND
            if exc.not_found
            else status.HTTP_502_BAD_GATEWAY
        ),
        detail=str(exc),
    )


def _serve_cached(
    request: Request,
    key: object,
    render: Callable[[], BaseModel],
) -> Response:
    """Serves a rendered response, short-circuiting 304 from cached bytes.

    Order matters: a fresh cache entry is probed *before* [render] is called,
    so both a 304 and a plain 200 hit cost no upstream work.
    """
    if_none_match = request.headers.get("if-none-match")
    cached = _dashboard_cache.get(key)

    if cached is not None:
        return conditional_response(cached, if_none_match=if_none_match)

    try:
        rendered = render_model(render())
    except CodeforcesError as exc:
        raise _cf_http_error(exc) from exc

    _dashboard_cache.get_or_render(key, lambda: rendered)
    return conditional_response(rendered, if_none_match=if_none_match)


def _require_handle(user: User) -> str:
    if not user.codeforces_handle:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Connect your Codeforces account first.",
        )
    return user.codeforces_handle


def _solved_problems(handle: str, count: int = 500) -> list:
    """Deduplicated solved submissions (first AC per problem id)."""
    seen: set[str] = set()
    solved = []
    for sub in fetch_submissions(handle, count=count):
        if sub.solved and sub.problem_id not in seen:
            seen.add(sub.problem_id)
            solved.append(sub)
    return solved


@router.get("/me", response_model=UserResponse)
def me(user: User = Depends(get_current_user)):
    return _user_response(user)


_VERIFICATION_TTL = timedelta(minutes=30)


def _handle_taken(db: Session, handle: str, user: User) -> bool:
    """True when another account already owns [handle].

    Codeforces handles are case-insensitive, so compare lowercased values.
    """
    return (
        db.scalar(
            select(User).where(
                func.lower(User.codeforces_handle) == handle.lower(),
                User.id != user.id,
            )
        )
        is not None
    )


def _verification_expired(requested: datetime) -> bool:
    # SQLite round-trips timestamps without tzinfo; normalise before comparing.
    if requested.tzinfo is None:
        requested = requested.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc) - requested > _VERIFICATION_TTL


@router.post("/link-codeforces/start", response_model=LinkStartResponse)
def start_link_codeforces(
    payload: LinkCodeforcesRequest,
    user: User = Depends(require_verified),
    db: Session = Depends(get_db),
):
    """Validates the handle and issues a code to place in the CF profile.

    Linking is a two-step flow so a user cannot claim a handle they do not own.
    """
    handle = payload.handle.strip()

    try:
        info = fetch_user_info(handle)
    except CodeforcesError as exc:
        raise _cf_http_error(exc) from exc

    # Store the canonical spelling Codeforces uses so two casing variants
    # cannot be linked as separate accounts.
    handle = info.handle

    if _handle_taken(db, handle, user):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="That handle is already linked to another account.",
        )

    code = f"CPT-{secrets.token_hex(3).upper()}"
    user.pending_codeforces_handle = handle
    user.verification_code = code
    user.verification_requested_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(user)

    return LinkStartResponse(
        handle=handle,
        verification_code=code,
        instructions=(
            f"Add the code {code} to the First name, Last name, or "
            "Organization field of your Codeforces profile, save it, then "
            "press Verify. You can remove the code once linking succeeds."
        ),
    )


@router.post("/link-codeforces/verify", response_model=UserResponse)
def verify_link_codeforces(
    payload: VerifyCodeforcesRequest,
    user: User = Depends(require_verified),
    db: Session = Depends(get_db),
):
    """Completes linking after the code appears in the Codeforces profile."""
    handle = user.pending_codeforces_handle
    expected = user.verification_code
    requested = user.verification_requested_at

    if not handle or not expected or requested is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Start the linking process first.",
        )

    if _verification_expired(requested):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="That verification code expired. Please start again.",
        )

    if payload.code.strip().upper() != expected.upper():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="That verification code is incorrect.",
        )

    try:
        info = fetch_user_info(handle, force_refresh=True)
    except CodeforcesError as exc:
        raise _cf_http_error(exc) from exc

    profile = " ".join(
        part for part in (info.first_name, info.last_name, info.organization) if part
    ).upper()
    if expected.upper() not in profile:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "We couldn't find the code in your Codeforces profile. Add it "
                "to your First name, Last name, or Organization and try again."
            ),
        )

    if _handle_taken(db, handle, user):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="That handle is already linked to another account.",
        )

    user.codeforces_handle = handle
    user.pending_codeforces_handle = None
    user.verification_code = None
    user.verification_requested_at = None
    db.commit()
    db.refresh(user)

    # Cached bodies are keyed by handle, so a relink can strand entries for the
    # previous handle. Drop them rather than let them linger.
    _dashboard_cache.clear()

    return _user_response(user)


@router.get("/stats", response_model=None)
def stats(request: Request, user: User = Depends(get_current_user)):
    handle = _require_handle(user)

    def render() -> StatsResponse:
        info = fetch_user_info(handle)
        solved = _solved_problems(handle)
        return StatsResponse(
            current_rating=info.rating,
            max_rating=info.max_rating,
            problems_solved=len(solved),
            current_streak=_streak_days(solved),
        )

    return _serve_cached(request, ("stats", handle), render)


@router.get("/goals", response_model=None)
def goals(request: Request, user: User = Depends(get_current_user)):
    handle = _require_handle(user)

    def render() -> GoalsResponse:
        info = fetch_user_info(handle)
        solved = _solved_problems(handle)
        return GoalsResponse(
            target_rating=user.target_rating,
            current_rating=info.rating,
            streak_days=_streak_days(solved),
        )

    # target_rating is part of the payload, so it belongs in the cache key.
    return _serve_cached(request, ("goals", handle, user.target_rating), render)


@router.put("/goals", response_model=GoalsResponse)
def update_goals(
    payload: UpdateGoalsRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sets or clears the user's target rating, returning the updated goal view.

    Requires a linked Codeforces handle because the response embeds the live
    current rating and streak.
    """
    handle = _require_handle(user)

    user.target_rating = payload.target_rating
    db.commit()
    db.refresh(user)

    # The cached /goals bodies are now stale for every target_rating variant.
    _dashboard_cache.clear()

    try:
        info = fetch_user_info(handle)
        solved = _solved_problems(handle)
    except CodeforcesError as exc:
        raise _cf_http_error(exc) from exc

    return GoalsResponse(
        target_rating=user.target_rating,
        current_rating=info.rating,
        streak_days=_streak_days(solved),
    )


@router.get("/recent-submissions", response_model=None)
def recent_submissions(
    request: Request,
    limit: int = Query(default=3, ge=1, le=50),
    user: User = Depends(get_current_user),
):
    handle = _require_handle(user)

    def render() -> RecentSubmissionsResponse:
        submissions = fetch_submissions(handle, count=20)
        submissions.sort(key=lambda s: s.submitted_at, reverse=True)
        return RecentSubmissionsResponse(
            submissions=[
                SubmissionSchema(
                    problem_name=s.problem_name,
                    problem_id=s.problem_id,
                    solved=s.solved,
                    submitted_at=s.submitted_at.isoformat(),
                )
                for s in submissions[:limit]
            ]
        )

    # limit changes the body, so it is part of the cache key.
    return _serve_cached(request, ("recent", handle, limit), render)


def _streak_days(solved: list) -> int:
    """Consecutive days ending today (or yesterday) with >=1 accepted solve."""
    if not solved:
        return 0

    days = sorted({s.submitted_at.date() for s in solved}, reverse=True)
    today = max(days)

    streak = 0
    expected = today
    for day in days:
        if day == expected:
            streak += 1
            expected = expected.fromordinal(expected.toordinal() - 1)
        else:
            break
    return streak
