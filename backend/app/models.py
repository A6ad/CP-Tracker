from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(
        String(255), unique=True, index=True, nullable=False
    )
    hashed_password: Mapped[str] = mapped_column(String(255), nullable=False)
    # Email ownership. New accounts start unverified and must enter the code
    # sent to their inbox before linking a Codeforces handle.
    email_verified: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )
    email_verification_hash: Mapped[str | None] = mapped_column(
        String(255), nullable=True
    )
    email_verification_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    email_verification_sent_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    email_verification_attempts: Mapped[int] = mapped_column(
        Integer, default=0, nullable=False
    )
    codeforces_handle: Mapped[str | None] = mapped_column(
        String(64), unique=True, index=True, nullable=True
    )
    # Pending handle-ownership verification. The user proves they own the
    # handle by placing [verification_code] in their Codeforces profile, then
    # calling the verify endpoint. Cleared once linking succeeds.
    pending_codeforces_handle: Mapped[str | None] = mapped_column(
        String(64), nullable=True
    )
    verification_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    verification_requested_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    target_rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
