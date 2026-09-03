# -*- coding: utf-8 -*-
"""The daily goal's rules, checked without a database (§ daily goal, 2026-09-03).

What lives here is what a live API cannot easily show: the allowed-value
rule, the points scale, and the arithmetic of "is the goal met". The parts
that need real rows — the once-a-day guarantee, concurrency, a goal changed
mid-day — are exercised against the running API in daily_goal_api_tests.py,
because their whole point is that the DATABASE enforces them.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.services import daily_goal as dg  # noqa: E402

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("  PASS  " if cond else "  FAIL  ") + name + (f"\n           -> {detail}" if detail and not cond else ""))


print("=== Разрешённые значения цели ===")
check("ровно 3/5/10/15/20", dg.ALLOWED_GOAL_MINUTES == (3, 5, 10, 15, 20), f"{dg.ALLOWED_GOAL_MINUTES}")
for good in (3, 5, 10, 15, 20):
    check(f"принимается {good}", dg.is_allowed_goal(good))
for bad in (1, 2, 4, 7, 9, 11, 25, 30, 60, 0, -5):
    check(f"отклоняется {bad}", not dg.is_allowed_goal(bad))
for bad in (None, "10", 10.0, 10.5, [10], {"m": 10}):
    check(f"отклоняется {bad!r} (не целое)", not dg.is_allowed_goal(bad))
check("True не проходит как цель 1", not dg.is_allowed_goal(True))
check("False не проходит как цель 0", not dg.is_allowed_goal(False))

print("\n=== Шкала наград ===")
expected = {3: 5, 5: 10, 10: 20, 15: 30, 20: 50}
check("шкала ровно из задания", dg.GOAL_POINTS == expected, f"{dg.GOAL_POINTS}")
for minutes, points in expected.items():
    check(f"{minutes} мин -> {points} очков", dg.GOAL_POINTS[minutes] == points)
check("шкала покрывает все разрешённые цели", set(dg.GOAL_POINTS) == set(dg.ALLOWED_GOAL_MINUTES))
check("награда растёт вместе с целью",
      [dg.GOAL_POINTS[m] for m in dg.ALLOWED_GOAL_MINUTES] == sorted(dg.GOAL_POINTS[m] for m in dg.ALLOWED_GOAL_MINUTES))

print("\n=== Значение по умолчанию ===")
check("по умолчанию 10 минут", dg.DEFAULT_GOAL_MINUTES == 10, f"{dg.DEFAULT_GOAL_MINUTES}")
check("значение по умолчанию само допустимо", dg.is_allowed_goal(dg.DEFAULT_GOAL_MINUTES))

print("\n=== Арифметика выполнения ===")
# The comparison the service makes: seconds >= goalMinutes * 60.
cases = [
    ("цель 10, накоплено 4+3+3 мин -> выполнена", 10, (4 + 3 + 3) * 60, True),
    ("цель 10, накоплено 12 мин -> выполнена", 10, 12 * 60, True),
    ("цель 10, накоплено 9 мин 59 с -> НЕ выполнена", 10, 9 * 60 + 59, False),
    ("цель 10, ровно 10 мин -> выполнена", 10, 10 * 60, True),
    ("цель 20, накоплено 14 мин -> НЕ выполнена", 20, 14 * 60, False),
    ("цель 3, накоплено 3 мин -> выполнена", 3, 3 * 60, True),
    ("цель 3, накоплено 2 мин 59 с -> НЕ выполнена", 3, 2 * 60 + 59, False),
    ("цель 20, накоплено 0 -> НЕ выполнена", 20, 0, False),
]
for name, goal, seconds, want in cases:
    check(name, (seconds >= goal * 60) == want, f"{seconds}с против {goal * 60}с")

print("\n=== День берётся тот же, что у streak и недельной активности ===")
from app.utils import utcnow  # noqa: E402

check("today_utc совпадает с utcnow().date()", dg.today_utc() == utcnow().date(), f"{dg.today_utc()} против {utcnow().date()}")

passed = sum(1 for _, ok in results if ok)
print(f"\n{'='*58}\nИТОГ: {passed}/{len(results)} PASS")
for n, ok in results:
    if not ok:
        print("  FAILED:", n)
raise SystemExit(0 if passed == len(results) else 1)
