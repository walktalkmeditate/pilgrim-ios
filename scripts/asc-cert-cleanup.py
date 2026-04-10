#!/usr/bin/env python3
"""
App Store Connect development certificate cleanup.

Used by the TestFlight and Release GitHub Actions workflows to
prevent orphaned "Created via API" development certificates from
accumulating in the Apple Developer portal. Each CI build that
signs an archive creates a fresh development cert via Apple's
automatic cert generation; without cleanup, these pile up forever.

Flow:
    1. Before the archive step, `snapshot` captures the set of
       existing development cert IDs to a file.
    2. After the upload step, `revoke` diffs the current cert list
       against the snapshot and deletes any new ones.

Usage:
    asc-cert-cleanup.py snapshot <snapshot_file>
    asc-cert-cleanup.py revoke <snapshot_file>

Environment variables (all required):
    APP_STORE_API_KEY         Apple Key ID (10-char alphanumeric)
    APP_STORE_API_ISSUER      Apple Issuer ID (UUID)
    APP_STORE_API_KEY_PATH    Absolute path to the .p8 private key

Exits non-zero only on argument / invocation errors. API failures
and missing credentials return exit 0 so the wider build isn't
broken by a cert cleanup problem; everything is logged loudly so
the CI log makes the state obvious.

Background on the original bug (2026-04-10): the previous
bash + openssl implementation of JWT generation was producing
ECDSA signatures in DER format, but Apple's App Store Connect API
requires raw r||s concatenation (64 bytes). Every API call was
returning 401 NOT_AUTHORIZED, but the errors were swallowed by
`2>/dev/null || true` in the shell pipeline, so the cleanup
silently did nothing for weeks. PyJWT's `ES256` algorithm handles
the format conversion correctly, which is why this script exists.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request


API_BASE = "https://api.appstoreconnect.apple.com/v1"
LIST_ENDPOINT = (
    f"{API_BASE}/certificates?filter%5BcertificateType%5D=DEVELOPMENT&limit=200"
)

# Marker string Apple sets as `displayName` on certificates it auto-
# generates in response to App Store Connect API calls. Manually-created
# certs have a human name (e.g., "Frank Zhu") and must NEVER be revoked
# by this script, no matter what state the snapshot is in.
API_CREATED_DISPLAY_NAME = "Created via API"


def log(msg: str) -> None:
    print(msg, flush=True)


def warn(msg: str) -> None:
    print(f"⚠️  {msg}", flush=True)


def mask_key_id(key_id: str) -> str:
    """Mask a key ID for logging — shows first 4 characters only."""
    if len(key_id) <= 4:
        return "****"
    return f"{key_id[:4]}…"


def generate_jwt(key_id: str, issuer_id: str, key_path: str) -> str:
    """Generate a short-lived ES256 JWT for App Store Connect."""
    import jwt  # PyJWT, installed by the workflow step before this runs

    with open(key_path, "rb") as f:
        private_key = f.read()

    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,  # 20 minutes, Apple's maximum
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": key_id, "typ": "JWT"}
    token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    # PyJWT 2.x returns str directly; older versions return bytes.
    token_str = token if isinstance(token, str) else token.decode("ascii")
    log(
        f"🔐 Generated JWT for Apple App Store Connect "
        f"(kid={mask_key_id(key_id)}, aud=appstoreconnect-v1, exp=1200s)"
    )
    return token_str


def list_dev_certs(token: str) -> list[dict]:
    """Return the list of Development certs for the current team.

    Each entry is a dict with `id` and `displayName` keys. We need the
    displayName to distinguish auto-created ("Created via API") certs
    from manually-created ones (named after the developer), so that
    the revoke step never touches personal dev certs.
    """
    req = urllib.request.Request(
        LIST_ENDPOINT,
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.load(resp)
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", errors="replace")[:500]
        warn(
            f"Apple API returned HTTP {err.code} listing certs — "
            f"skipping. Response body:\n{body}"
        )
        return []
    except (urllib.error.URLError, TimeoutError) as err:
        warn(f"Apple API request failed: {err} — skipping")
        return []

    data = payload.get("data", [])
    certs: list[dict] = []
    for item in data:
        cert_id = item.get("id")
        if not cert_id:
            continue
        display_name = item.get("attributes", {}).get("displayName", "")
        certs.append({"id": cert_id, "displayName": display_name})
    return certs


def is_api_created(cert: dict) -> bool:
    """Only API-generated dev certs are safe to revoke."""
    return cert.get("displayName", "") == API_CREATED_DISPLAY_NAME


def revoke_cert(token: str, cert_id: str) -> bool:
    req = urllib.request.Request(
        f"{API_BASE}/certificates/{cert_id}",
        method="DELETE",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        urllib.request.urlopen(req, timeout=30)
        return True
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", errors="replace")[:300]
        log(f"   ❌ delete failed with HTTP {err.code}: {body}")
        return False
    except (urllib.error.URLError, TimeoutError) as err:
        log(f"   ❌ delete failed: {err}")
        return False


def load_credentials() -> tuple[str, str, str] | None:
    key_id = os.environ.get("APP_STORE_API_KEY", "").strip()
    issuer_id = os.environ.get("APP_STORE_API_ISSUER", "").strip()
    key_path = os.environ.get("APP_STORE_API_KEY_PATH", "").strip()

    if not key_id:
        warn("APP_STORE_API_KEY env var is empty — skipping cert cleanup")
        return None
    if not issuer_id:
        warn("APP_STORE_API_ISSUER env var is empty — skipping cert cleanup")
        return None
    if not key_path:
        warn("APP_STORE_API_KEY_PATH env var is empty — skipping cert cleanup")
        return None
    if not os.path.isfile(key_path):
        warn(f"API key file not found at {key_path} — skipping cert cleanup")
        return None

    return key_id, issuer_id, key_path


def do_snapshot(snapshot_path: str) -> int:
    log("▶️  asc-cert-cleanup snapshot")
    creds = load_credentials()
    if creds is None:
        # IMPORTANT: do NOT create an empty snapshot file here. If the
        # revoke step later finds an empty snapshot, it would treat
        # every current cert as "new" and delete them all — including
        # personal dev certs belonging to the team owner. Leaving the
        # file missing causes the revoke step to bail safely.
        return 0

    token = generate_jwt(*creds)
    certs = list_dev_certs(token)
    with open(snapshot_path, "w") as f:
        for cert in certs:
            f.write(cert["id"] + "\n")

    log(f"📋 Snapshotted {len(certs)} pre-build development cert(s):")
    for cert in certs:
        tag = "🤖 API" if is_api_created(cert) else "👤 manual"
        log(f"  {cert['id']}  [{tag}] {cert['displayName']}")
    return 0


def do_revoke(snapshot_path: str) -> int:
    log("▶️  asc-cert-cleanup revoke")
    if not os.path.isfile(snapshot_path):
        warn(f"Snapshot file missing: {snapshot_path} — skipping cert revoke")
        return 0

    creds = load_credentials()
    if creds is None:
        return 0

    with open(snapshot_path) as f:
        pre_certs = {line.strip() for line in f if line.strip()}
    log(f"📂 Loaded {len(pre_certs)} pre-build cert ID(s) from snapshot")

    token = generate_jwt(*creds)
    current = list_dev_certs(token)
    log(f"📋 Found {len(current)} current development cert(s)")

    # Partition the current certs into four categories so we can log
    # what's happening with each one and only delete the ones that are
    # BOTH API-created AND new since the snapshot. Belt and suspenders:
    # even if the snapshot logic is broken, we refuse to delete any
    # cert whose displayName isn't "Created via API".
    preserved_known: list[dict] = []         # in snapshot — definitely keep
    preserved_manual: list[dict] = []        # not in snapshot but not API-created — keep
    to_revoke: list[dict] = []               # new AND API-created — safe to delete

    for cert in current:
        if cert["id"] in pre_certs:
            preserved_known.append(cert)
        elif not is_api_created(cert):
            preserved_manual.append(cert)
        else:
            to_revoke.append(cert)

    log(f"🛡️  Preserving {len(preserved_known)} cert(s) already in snapshot")
    log(f"🛡️  Preserving {len(preserved_manual)} manually-created cert(s) "
        f"(new since snapshot but NOT API-generated — personal dev certs)")
    if preserved_manual:
        for cert in preserved_manual:
            log(f"     · {cert['id']}  {cert['displayName']}")
    log(f"🎯 Targeting {len(to_revoke)} API-created cert(s) for revoke")

    revoked = 0
    failed = 0
    for cert in to_revoke:
        log(f"🗑️  Revoking: {cert['id']}  [{cert['displayName']}]")
        if revoke_cert(token, cert["id"]):
            log("   ✅ revoked")
            revoked += 1
        else:
            failed += 1

    log(f"📊 Revoke summary: {revoked} revoked, {failed} failed")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in ("snapshot", "revoke"):
        print(
            "Usage: asc-cert-cleanup.py snapshot <file> | revoke <file>",
            file=sys.stderr,
        )
        return 2

    mode = argv[1]
    path = argv[2]

    try:
        if mode == "snapshot":
            return do_snapshot(path)
        return do_revoke(path)
    except Exception as err:  # noqa: BLE001 - keep CI green on unexpected errors
        warn(f"Unexpected error in cert cleanup ({mode}): {err}")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
