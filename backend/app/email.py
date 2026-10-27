"""Outbound email.

Only the console backend is implemented, which logs the message instead of
delivering it. That keeps local development free of SMTP credentials while
preserving the real two-step flow: the address must be proven before the
account unlocks handle linking.

To go live, set `EMAIL_BACKEND=smtp` and implement delivery here; the router
does not change.
"""

import logging

from app.config import settings

logger = logging.getLogger("cp_tracker.email")


def send_verification_email(to: str, code: str) -> None:
    """Sends (or, for the console backend, logs) a verification code."""
    if settings.email_backend == "console":
        # WARNING level so it is visible under uvicorn's default logging.
        logger.warning("Email verification code for %s: %s", to, code)
        return

    raise RuntimeError(
        f"EMAIL_BACKEND={settings.email_backend!r} is not implemented. "
        "Use 'console' for local development."
    )
