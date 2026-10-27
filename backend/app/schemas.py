"""Pydantic response/request schemas.

Field names are snake_case to match the Dart models exactly
(see cp_tracker/lib/models/*.dart).
"""

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class _EmailNormalizer(BaseModel):
    """Lowercases and trims the email so lookups are case/space-insensitive.

    EmailStr validates the format but preserves case and surrounding
    whitespace, so "Alice@Example.com " would otherwise miss the account
    stored as "alice@example.com".
    """

    @field_validator("email", check_fields=False)
    @classmethod
    def _normalize_email(cls, value: str) -> str:
        return value.strip().lower()


class RegisterRequest(_EmailNormalizer):
    email: EmailStr
    password: str = Field(min_length=6, max_length=128)


class LoginRequest(_EmailNormalizer):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class LinkCodeforcesRequest(BaseModel):
    handle: str = Field(min_length=1, max_length=64)


class LinkStartResponse(BaseModel):
    """Returned when the user starts proving ownership of a handle."""

    handle: str
    verification_code: str
    instructions: str


class VerifyCodeforcesRequest(BaseModel):
    code: str = Field(min_length=1, max_length=32)


class UpdateGoalsRequest(BaseModel):
    """Body for PUT /user/goals.

    `target_rating` is required in the payload but accepts null, so a client
    can explicitly clear an existing goal. Range matches Codeforces' own
    0–4000 rating scale.
    """

    target_rating: int | None = Field(default=None, ge=0, le=4000)


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    email: str
    email_verified: bool = False
    codeforces_handle: str | None = None
    current_rating: int | None = None
    max_rating: int | None = None


class TokenResponse(BaseModel):
    user: UserResponse
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RegisterResponse(TokenResponse):
    """Token pair plus, in console-email mode only, the code for local testing."""

    dev_verification_code: str | None = None


class VerifyEmailRequest(_EmailNormalizer):
    email: EmailStr
    code: str = Field(min_length=4, max_length=12)


class ResendVerificationRequest(_EmailNormalizer):
    email: EmailStr


class ResendVerificationResponse(BaseModel):
    message: str
    dev_verification_code: str | None = None


class StatsResponse(BaseModel):
    current_rating: int
    max_rating: int
    problems_solved: int
    current_streak: int


class GoalsResponse(BaseModel):
    target_rating: int | None
    current_rating: int
    streak_days: int


class RatingPointSchema(BaseModel):
    date: str
    rating: int


class RatingHistoryResponse(BaseModel):
    points: list[RatingPointSchema]


class RatingBucketSchema(BaseModel):
    bucket: str
    solved: int


class ByRatingResponse(BaseModel):
    buckets: list[RatingBucketSchema]


class TopicStatSchema(BaseModel):
    topic: str
    solved: int


class TopicsResponse(BaseModel):
    topics: list[TopicStatSchema]


class SubmissionSchema(BaseModel):
    problem_name: str
    problem_id: str
    solved: bool
    submitted_at: str


class RecentSubmissionsResponse(BaseModel):
    submissions: list[SubmissionSchema]


class PracticeProblemSchema(BaseModel):
    problem_id: str
    contest_id: int | None
    index: str
    name: str
    rating: int | None
    tags: list[str]
    url: str


class PracticeResponse(BaseModel):
    mode: str
    rating: int | None
    problems: list[PracticeProblemSchema]


class ContestSchema(BaseModel):
    id: int
    name: str
    phase: str
    start_time: str
    duration_seconds: int
    url: str


class ContestsResponse(BaseModel):
    upcoming: list[ContestSchema]
    finished: list[ContestSchema]
