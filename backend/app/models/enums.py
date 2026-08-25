import enum


class Role(str, enum.Enum):
    ADMIN = "ADMIN"
    TEACHER = "TEACHER"
    USER = "USER"


class UserStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    BLOCKED = "BLOCKED"


class CourseStatus(str, enum.Enum):
    DRAFT = "DRAFT"
    PUBLISHED = "PUBLISHED"
