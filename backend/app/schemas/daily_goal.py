from typing import Literal

from pydantic import BaseModel


class DailyGoalInput(BaseModel):
    """The five goals a learner may choose (§ daily goal, 2026-09-03).

    A Literal rather than a range: 3, 5, 10, 15 and 20 are the whole set, and
    anything else — 1, 7, 25, 60, a float, a string — is refused by the
    schema before any handler runs. The service checks the same set again,
    so a value that reached storage another way still cannot take effect.
    """

    dailyGoalMinutes: Literal[3, 5, 10, 15, 20]
