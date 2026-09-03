from app.models.user import User
from app.utils import to_iso_z, utcnow

# 5 minutes — the "online" window shown in the admin UI. Deliberately a
# separate constant from auth/deps.py's 2-minute activity-update throttle
# (kept wider so the indicator doesn't flicker offline between two of a
# user's own requests) — same split as admin.routes.ts.
ONLINE_WINDOW_SECONDS = 5 * 60


def public_user(user: User) -> dict:
    """Every route returning a user must go through this — passwordHash and
    usernameLower are never sent to the client, exactly like publicUser() in
    server/src/serialize.ts."""
    return {
        "id": user.id,
        "publicId": user.publicId,
        "firstName": user.firstName,
        "lastName": user.lastName,
        "email": user.email,
        "username": user.username,
        "role": user.role.value,
        "status": user.status.value,
        "avatarUrl": user.avatarUrl,
        "bio": user.bio,
        "birthDate": to_iso_z(user.birthDate),
        "canEditProfile": user.canEditProfile,
        "selectedLanguageId": user.selectedLanguageId,
        "lastLoginAt": to_iso_z(user.lastLoginAt),
        "lastActiveAt": to_iso_z(user.lastActiveAt),
    }


def with_online_status(user: User) -> dict:
    online = user.lastActiveAt is not None and (utcnow() - user.lastActiveAt).total_seconds() <= ONLINE_WINDOW_SECONDS
    return {**public_user(user), "online": online}
