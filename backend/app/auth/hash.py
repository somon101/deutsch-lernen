from passlib.context import CryptContext

# bcrypt cost 10 — matches server/src/auth/hash.ts's SALT_ROUNDS exactly, and
# passlib's bcrypt backend is wire-format compatible with bcryptjs (both
# produce/consume standard $2a$/$2b$ hashes), so existing password hashes in
# the DB keep working with zero migration.
_pwd_context = CryptContext(schemes=["bcrypt"], bcrypt__rounds=10)


def hash_password(plain: str) -> str:
    return _pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return _pwd_context.verify(plain, hashed)
