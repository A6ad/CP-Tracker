import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.email import send_verification_email
from app.models import User
from app.schemas import (
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    RegisterResponse,
    ResendVerificationRequest,
    ResendVerificationResponse,
    TokenResponse,
    UserResponse,
    VerifyEmailRequest,
)
from app.security import (
    REFRESH,
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _user_response(user: User) -> UserResponse:
    """Builds the API user payload, filling ratings from Codeforces when linked.

    Kept lazy: if Codeforces is unreachable the link still succeeds and the
    rating fields are simply omitted.
    """
    current: int | None = None
    peak: int | None = None

    if user.codeforces_handle:
        try:
            from app.codeforces import fetch_user_info

            info = fetch_user_info(user.codeforces_handle)
            current, peak = info.rating, info.max_rating
        except Exception:
            current, peak = None, None

    return UserResponse(
        id=str(user.id),
        email=user.email,
        email_verified=user.email_verified,
        codeforces_handle=user.codeforces_handle,
        current_rating=current,
        max_rating=peak,
    )


def _token_response(user: User) -> TokenResponse:
    return TokenResponse(
        user=_user_response(user),
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


_EMAIL_CODE_ATTEMPTS = 5


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    # SQLite round-trips timestamps without tzinfo.
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


def _new_email_code() -> str:
    """A 6-digit code; bcrypt protects it even though the space is small."""
    return f"{secrets.randbelow(1_000_000):06d}"


def _issue_email_code(user: User, db: Session) -> str:
    """Stores a fresh hashed code and sends it, returning the plain value."""
    code = _new_email_code()
    user.email_verification_hash = hash_password(code)
    user.email_verification_expires_at = _utcnow() + timedelta(
        minutes=settings.email_verification_ttl_minutes
    )
    user.email_verification_sent_at = _utcnow()
    user.email_verification_attempts = 0
    db.commit()
    db.refresh(user)
    send_verification_email(user.email, code)
    return code


def _dev_code(code: str) -> str | None:
    """Exposes the code to the client only when no real email is configured."""
    return code if settings.email_backend == "console" else None


@router.post("/register", response_model=RegisterResponse, status_code=201)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.scalar(select(User).where(User.email == payload.email))
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with that email already exists.",
        )

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        email_verified=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    code = _issue_email_code(user, db)
    tokens = _token_response(user)
    return RegisterResponse(
        user=tokens.user,
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        dev_verification_code=_dev_code(code),
    )


@router.post("/verify-email", response_model=UserResponse)
def verify_email(payload: VerifyEmailRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == payload.email))
    invalid = HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="That verification code is invalid or expired.",
    )

    if user is None:
        raise invalid
    if user.email_verified:
        return _user_response(user)
    if (
        user.email_verification_hash is None
        or user.email_verification_expires_at is None
    ):
        raise invalid
    if _as_utc(user.email_verification_expires_at) < _utcnow():
        raise invalid
    if user.email_verification_attempts >= _EMAIL_CODE_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Too many attempts. Request a new verification code.",
        )
    if not verify_password(payload.code, user.email_verification_hash):
        user.email_verification_attempts += 1
        db.commit()
        raise invalid

    user.email_verified = True
    user.email_verification_hash = None
    user.email_verification_expires_at = None
    user.email_verification_sent_at = None
    user.email_verification_attempts = 0
    db.commit()
    db.refresh(user)
    return _user_response(user)


@router.post("/resend-verification", response_model=ResendVerificationResponse)
def resend_verification(
    payload: ResendVerificationRequest, db: Session = Depends(get_db)
):
    """Reissues a code. The response never reveals whether the email exists."""
    user = db.scalar(select(User).where(User.email == payload.email))
    message = "If that account exists, a new verification code was sent."

    if user is None or user.email_verified:
        return ResendVerificationResponse(message=message)

    sent_at = user.email_verification_sent_at
    if sent_at is not None and (
        _utcnow() - _as_utc(sent_at)
    ).total_seconds() < settings.email_verification_resend_seconds:
        return ResendVerificationResponse(
            message="A code was sent recently. Please wait a moment and try again."
        )

    code = _issue_email_code(user, db)
    return ResendVerificationResponse(
        message=message,
        dev_verification_code=_dev_code(code),
    )


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == payload.email))
    if user is None or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password.",
        )
    return _token_response(user)


@router.post("/refresh", response_model=TokenResponse)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    user_id = decode_token(payload.refresh_token, REFRESH)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Your session expired. Please log in again.",
        )

    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Your session expired. Please log in again.",
        )
    return _token_response(user)
