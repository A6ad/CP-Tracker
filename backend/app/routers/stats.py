from fastapi import APIRouter, Depends, HTTPException, status

from app.cache import TtlCache
from app.codeforces import (
    CodeforcesError,
    TTL_RATING_HISTORY,
    TTL_SUBMISSIONS,
    fetch_rating_history,
)
from app.deps import get_current_user
from app.models import User
from app.routers.user import _require_handle, _solved_problems
from app.schemas import (
    ByRatingResponse,
    RatingBucketSchema,
    RatingHistoryResponse,
    RatingPointSchema,
    TopicStatSchema,
    TopicsResponse,
)

router = APIRouter(prefix="/stats", tags=["stats"])

# Caches the derived aggregates below. These are computed from submissions that
# are themselves already cached, so the TTL need not be long — it exists to
# avoid re-bucketing a 500-item list on every dashboard refresh.
_derived_cache = TtlCache()

# Codeforces-style rating buckets.
BUCKET_EDGES = [800, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2400, 2600]


def _bucket_label(rating: int) -> str:
    """Maps a problem rating to its bucket label, e.g. 1350 -> '1200-1400'."""
    for lower, upper in zip(BUCKET_EDGES, BUCKET_EDGES[1:]):
        if lower <= rating < upper:
            return f"{lower}-{upper}"
    if rating < BUCKET_EDGES[0]:
        return f"<{BUCKET_EDGES[0]}"
    return f"{BUCKET_EDGES[-1]}+"


def _cf_error_response(exc: CodeforcesError) -> HTTPException:
    return HTTPException(
        status_code=(
            status.HTTP_404_NOT_FOUND
            if exc.not_found
            else status.HTTP_502_BAD_GATEWAY
        ),
        detail=str(exc),
    )


@router.get("/rating-history", response_model=RatingHistoryResponse)
def rating_history(user: User = Depends(get_current_user)):
    handle = _require_handle(user)

    def build() -> RatingHistoryResponse:
        try:
            changes = fetch_rating_history(handle)
        except CodeforcesError as exc:
            raise _cf_error_response(exc) from exc

        return RatingHistoryResponse(
            points=[
                RatingPointSchema(date=c.date.date().isoformat(), rating=c.new_rating)
                for c in changes
            ]
        )

    return _derived_cache.get_or_set(
        ("rating-history", handle), TTL_RATING_HISTORY, build
    )


@router.get("/by-rating", response_model=ByRatingResponse)
def by_rating(user: User = Depends(get_current_user)):
    handle = _require_handle(user)

    def build() -> ByRatingResponse:
        solved = _solved_problems(handle)

        counts: dict[str, int] = {}
        for sub in solved:
            if sub.rating is None:
                continue
            label = _bucket_label(sub.rating)
            counts[label] = counts.get(label, 0) + 1

        return ByRatingResponse(
            buckets=[
                RatingBucketSchema(bucket=label, solved=count)
                for label, count in sorted(
                    counts.items(), key=lambda kv: _bucket_sort_key(kv[0])
                )
            ]
        )

    return _derived_cache.get_or_set(("by-rating", handle), TTL_SUBMISSIONS, build)


def _bucket_sort_key(label: str) -> int:
    if label.startswith("<"):
        return 0
    if label.endswith("+"):
        return int(label[:-1])
    return int(label.split("-")[0])


@router.get("/topics", response_model=TopicsResponse)
def topics(user: User = Depends(get_current_user)):
    handle = _require_handle(user)

    def build() -> TopicsResponse:
        solved = _solved_problems(handle)

        counts: dict[str, int] = {}
        for sub in solved:
            for tag in sub.tags:
                counts[tag] = counts.get(tag, 0) + 1

        ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)
        return TopicsResponse(
            topics=[TopicStatSchema(topic=tag, solved=n) for tag, n in ranked]
        )

    return _derived_cache.get_or_set(("topics", handle), TTL_SUBMISSIONS, build)
