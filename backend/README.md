# CP Tracker — FastAPI Backend

Backend for the CP Tracker Flutter app. Serves the auth, user, and stats
endpoints the client calls in `cp_tracker/lib/services/api_client.dart`.

## Requirements

- Python 3.11+
- A running **PostgreSQL** server (no SQLite/JSON fallback — Postgres is required)
- Network access to `codeforces.com` (stats are fetched live)
- [uv](https://docs.astral.sh/uv/) (recommended) or plain `pip`

## 1. Start PostgreSQL

The default `DATABASE_URL` expects a database named `cp_tracker` owned by a
`cp_tracker` role with password `cp_tracker`.

Using Docker:

```bash
docker run --name cp-tracker-db \
  -e POSTGRES_USER=cp_tracker \
  -e POSTGRES_PASSWORD=cp_tracker \
  -e POSTGRES_DB=cp_tracker \
  -p 5432:5432 -d postgres:16
```

Or with a local Postgres install:

```bash
sudo -u postgres psql -c "CREATE USER cp_tracker WITH PASSWORD 'cp_tracker';"
sudo -u postgres psql -c "CREATE DATABASE cp_tracker OWNER cp_tracker;"
```

Verify it is reachable:

```bash
psql postgresql://cp_tracker:cp_tracker@localhost:5432/cp_tracker -c '\conninfo'
```

## 2. Install dependencies

```bash
cd backend
uv sync
```

With plain pip:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
```

## 3. Configure

```bash
cp .env.example .env
```

Then **change `SECRET_KEY`** to a real random value:

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Tables are created automatically on first startup.

## 4. Run

```bash
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

- Interactive docs: http://localhost:8000/docs
- Health check: http://localhost:8000/health

`--host 0.0.0.0` matters: the phone must reach this machine over the LAN.

## 5. Point the Flutter app at it

Your phone cannot see `localhost`. Use the host machine's LAN IP:

```bash
ip route get 1 | awk '{print $7; exit}'   # e.g. 192.168.1.42
```

```bash
cd ../cp_tracker
flutter run -d 29abb8f5 --dart-define=API_BASE_URL=http://192.168.1.42:8000
```

The default (`http://10.0.2.2:8000`) is the Android-emulator alias for the
host machine and will **not** work from a physical phone.

Make sure the phone is on the same Wi-Fi and the firewall allows port 8000.

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/auth/register` | – | 409 if email taken |
| POST | `/auth/login` | – | 401 on bad credentials |
| POST | `/auth/refresh` | – | 401 if refresh token invalid |
| GET | `/user/me` | Bearer | |
| POST | `/user/link-codeforces` | Bearer | 404 unknown handle, 409 handle taken |
| GET | `/user/stats` | Bearer | |
| GET | `/user/goals` | Bearer | needs `target_rating` set |
| PUT | `/user/goals` | Bearer | `{"target_rating": int \| null}`, 0–4000 |
| GET | `/user/recent-submissions?limit=N` | Bearer | 1–50, default 3 |
| GET | `/stats/rating-history` | Bearer | |
| GET | `/stats/by-rating` | Bearer | |
| GET | `/stats/topics` | Bearer | |

Endpoints other than auth return **404** when no Codeforces handle is linked,
and **502** when Codeforces itself is unreachable.

## Codeforces caching

Upstream responses are memoised **in-process** by `app/codeforces.py`:

| Call | TTL | Why |
|---|---|---|
| `user.info` | 5 min | rating changes only after a contest |
| `user.rating` | 15 min | same |
| `user.status` | 1 min | new submissions arrive often |

The submissions key includes the requested `count`, so the dashboard (20) and
the stats endpoints (500) cache separately rather than fighting over one entry.
The cache is a plain dict guarded by a `threading.Lock` — it is **per-process
and lost on restart**. Behind multiple uvicorn workers each worker keeps its
own copy, so raise `workers` only alongside a shared cache (e.g. Redis).

### Derived `/stats/*` cache

`/stats/by-rating` and `/stats/topics` re-bucket the full solved list on every
call, and `/stats/rating-history` reconstructs the whole series. These are
memoised separately in `app/routers/stats.py`:

| Endpoint | TTL | Key |
|---|---|---|
| `/stats/rating-history` | 15 min | handle |
| `/stats/by-rating` | 1 min | handle |
| `/stats/topics` | 1 min | handle |

Failures are **not** cached: a `CodeforcesError` propagates out of the producer
before anything is stored, so a transient outage does not pin an error for the
whole TTL.

## Conditional requests (ETag)

`GET /user/stats`, `GET /user/goals`, and `GET /user/recent-submissions`
return a strong `ETag` and honour `If-None-Match`:

```bash
curl -sD- localhost:8000/user/stats -H "Authorization: Bearer $TOKEN" -o /dev/null
# note the ETag header, then:
curl -sD- localhost:8000/user/stats -H "Authorization: Bearer $TOKEN" \
  -H 'If-None-Match: "<etag>"' -o /dev/null   # -> 304 Not Modified
```

Responses carry `Cache-Control: private, no-cache` — `no-cache` means "revalidate
before use", not "do not store", which is what an ETag flow needs. The validator
handles the `W/` weak prefix, comma-separated lists, and `*`.

### How the short-circuit works

`app/routers/user.py` keeps a `RenderedCache` holding each response **already
serialised**, together with its ETag. Request handling order is:

1. Probe the cache for a fresh entry.
2. **Hit** — compare the stored ETag against `If-None-Match` and return either
   304 or 200 directly from the cached bytes. No Codeforces call, no model
   rebuild, no re-serialisation.
3. **Miss** — call the render function, freeze it to bytes + ETag, store it,
   then serve it conditionally.

So a 304 costs one dict lookup and one header comparison. The payload is only
built when the cache is cold.

Cache keys include everything the body depends on:

| Endpoint | Key | Invalidated by |
|---|---|---|
| `/user/stats` | `(stats, handle)` | handle change |
| `/user/goals` | `(goals, handle, target_rating)` | `PUT /user/goals`, handle change |
| `/user/recent-submissions` | `(recent, handle, limit)` | handle change |

`PUT /user/goals` and `POST /user/link-codeforces` call `_dashboard_cache.clear()`
so a write cannot be masked by a still-fresh cached body.

Because a hit never reaches the render function, the TTL bounds how stale a
200 can be — it is not just a computation cache.

## Tests

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -e . pytest email-validator
.venv/bin/python -m pytest
```

**No PostgreSQL and no network are required.** Tests run against an in-memory
SQLite database (`get_db` is overridden and the app's lazy engine is repointed)
and the Codeforces layer is stubbed via `monkeypatch` in `tests/conftest.py`.

| File | Covers |
|---|---|
| `test_auth.py` | register/login/refresh, duplicate email, token-type enforcement |
| `test_user.py` | linking, handle conflicts, stats, goals CRUD, submissions |
| `test_stats.py` | rating history, bucket labels, topic counts, streak logic, 502/404 mapping |
| `test_cache_etag.py` | TTL cache, ETag matching, 304 short-circuit, cache invalidation |

Notable cases:

- `test_304_short_circuits_before_rendering` counts calls into the render path
  and asserts a conditional hit never reaches it.
- `test_goals_cache_is_invalidated_by_put` guards the write-after-cache hazard.
- `test_solved_problems_are_deduplicated` covers repeat ACs on one problem.

### Caveats

- SQLite is a test double, **not** the production database. Postgres-specific
  behaviour (real `unique` violations, connection pooling, `TEXT` vs `VARCHAR`)
  is not exercised. Run the manual smoke test against Postgres before shipping.
- `bcrypt` is pinned directly rather than via `passlib`. `passlib` 1.7.4 (2020)
  is incompatible with `bcrypt` 5.x and raises `ValueError` on every hash — see
  Security notes below.

## Manual smoke test
```bash
# Register
curl -s -X POST localhost:8000/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"a@b.com","password":"secret123"}'

# Save the access_token from the response, then:
TOKEN=<paste>
curl -s localhost:8000/user/me -H "Authorization: Bearer $TOKEN"

# Link a real handle, then fetch stats
curl -s -X POST localhost:8000/user/link-codeforces \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"handle":"tourist"}'
curl -s localhost:8000/user/stats -H "Authorization: Bearer $TOKEN"

# Set a rating goal, then clear it
curl -s -X PUT localhost:8000/user/goals \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"target_rating":1600}'
curl -s -X PUT localhost:8000/user/goals \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"target_rating":null}'
```

## Known limitations

- **Refresh tokens are stateless.** `/auth/refresh` validates the JWT
  signature and expiry but keeps no server-side revocation list, so a stolen
  refresh token stays valid until it expires. Add a token table to revoke.
- **Codeforces calls are synchronous** inside request handlers. A user with a
  long submission history makes the request wait on upstream latency. The
  first request for a handle is therefore slow; subsequent ones hit the cache.
- **No rate limiting** on `/auth/login`, so it is open to credential stuffing.
- **`/user/goals` returns 404 without a linked handle**, because its response
  embeds the live current rating and streak.
- `SECRET_KEY` defaults to an insecure placeholder so the app boots before
  configuration. Never run it that way outside local development.
- **Passwords longer than 72 bytes are truncated** before hashing, because
  bcrypt's API rejects longer input outright. This matches bcrypt's own
  behaviour and does not weaken short passwords, but it means two passwords
  sharing a 72-byte prefix hash identically.

## Security notes

`bcrypt` is used directly instead of `passlib`. `passlib` 1.7.4 has not been
released since 2020 and breaks against `bcrypt` 5.x: it probes a removed
`bcrypt.__about__.__version__` attribute and then raises

```
ValueError: password cannot be longer than 72 bytes
```

on **every** `hash()` call, which would fail all registration and login. Using
the `bcrypt` library directly avoids the unmaintained shim.

