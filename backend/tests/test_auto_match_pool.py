# -*- coding: utf-8 -*-
"""The word-selection rule for "Сопоставление авто" (§ auto match, 2026-09-02).

Exercised against a stub session rather than the live API, because the rule
turns on WHEN a word was learned: "yesterday" can't be produced through the
API without waiting a day, and the tiering — today's still-free words first,
everything earlier only as fallback — is the whole point of the feature.
"""
import asyncio
from datetime import timedelta

from app.services import auto_match
from app.utils import utcnow

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond)))
    print(("  PASS  " if cond else "  FAIL  ") + name + (f"\n           -> {detail}" if detail and not cond else ""))


class _Rows:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class FakeSession:
    """Answers the two reads _today_first_pool makes."""

    def __init__(self, progress_rows):
        self._rows = progress_rows

    async def execute(self, _stmt):
        return _Rows(self._rows)


def build(*, today_words, earlier_words, used_by_translate):
    """Wires a pool made of the given words, with control over when each was
    learned and which ones "Переведи слово" has claimed."""
    now = utcnow()
    rows = [(w, now) for w in today_words] + [(w, now - timedelta(days=3)) for w in earlier_words]
    cards = {w: {"wordId": w, "word": w, "translation": f"перевод_{w}"} for w in today_words + earlier_words}

    async def fake_used(db, *, user_id, lesson_id):
        return set(used_by_translate)

    async def fake_get_words(db, ids):
        return [cards[i] for i in ids if i in cards]

    auto_match.words_used_by_translate_word = fake_used
    auto_match.get_words = fake_get_words
    return asyncio.run(auto_match._today_first_pool(FakeSession(rows), user_id="u", lesson_id="l"))


T = [f"today{i}" for i in range(10)]
E = [f"earlier{i}" for i in range(12)]

print("=== Тест 1: сегодня 10, «Переводи слово» занял 2 ===")
pool = build(today_words=T, earlier_words=E, used_by_translate=T[:2])
head = [c["wordId"] for c in pool[:8]]
check("первые 8 — сегодняшние свободные", set(head) <= set(T[2:]), f"{head}")
check("занятые переводом исключены полностью", not ({"today0", "today1"} & {c['wordId'] for c in pool}), "занятое слово попало в пул")
check("ранее изученные идут ПОСЛЕ сегодняшних",
      [c["wordId"] for c in pool[:8]] == [c["wordId"] for c in pool if c["wordId"] in T][:8], f"{[c['wordId'] for c in pool[:10]]}")

print("\n=== Тест 2: «Переводи слово» занял 6, нужно 8 -> 4 сегодня + 4 ранее ===")
pool = build(today_words=T, earlier_words=E, used_by_translate=T[:6])
first8 = [c["wordId"] for c in pool[:8]]
today_part = [w for w in first8 if w in T]
earlier_part = [w for w in first8 if w in E]
check("4 сегодняшних", len(today_part) == 4, f"{today_part}")
check("4 ранее изученных", len(earlier_part) == 4, f"{earlier_part}")
check("сегодняшние стоят первыми", first8[:4] == today_part, f"{first8}")

print("\n=== Тест 3: все сегодняшние заняты «Переводи слово» ===")
pool = build(today_words=T, earlier_words=E, used_by_translate=T)
first8 = [c["wordId"] for c in pool[:8]]
check("все 8 из ранее изученных", set(first8) <= set(E), f"{first8}")
check("ни одного сегодняшнего", not (set(first8) & set(T)))

print("\n=== Тест 4: сегодняшних меньше, чем требуется ===")
pool = build(today_words=T[:3], earlier_words=E, used_by_translate=[])
first8 = [c["wordId"] for c in pool[:8]]
check("3 сегодняшних + 5 ранее", len([w for w in first8 if w in T]) == 3 and len([w for w in first8 if w in E]) == 5, f"{first8}")
check("сегодняшние первыми", first8[:3] == [w for w in first8 if w in T], f"{first8}")

print("\n=== Тест 5: у пользователя нет изученных слов ===")
pool = build(today_words=[], earlier_words=[], used_by_translate=[])
check("пул пуст, без исключения", pool == [], f"{pool}")

print("\n=== Тест 5b: есть только сегодняшние, и все заняты ===")
pool = build(today_words=T, earlier_words=[], used_by_translate=T)
check("пул пуст — fallback брать неоткуда", pool == [], f"{pool}")

print("\n=== Дубликаты и мусор ===")
now = utcnow()
dup_rows = [("a", now), ("b", now), ("c", now - timedelta(days=2))]
dup_cards = {
    "a": {"wordId": "a", "word": "Hund", "translation": "собака"},
    "b": {"wordId": "b", "word": "hund!", "translation": "пёс"},      # same word, different card
    "c": {"wordId": "c", "word": "Katze", "translation": "  "},        # blank translation
}


async def _used(db, *, user_id, lesson_id):
    return set()


async def _cards(db, ids):
    return [dup_cards[i] for i in ids if i in dup_cards]


auto_match.words_used_by_translate_word = _used
auto_match.get_words = _cards
pool = asyncio.run(auto_match._today_first_pool(FakeSession(dup_rows), user_id="u", lesson_id="l"))
ids = [c["wordId"] for c in pool]
check("одно и то же слово не попадает дважды", len(ids) == 1 and ids[0] == "a", f"{ids}")
check("слово без перевода исключено (нечего сопоставлять)", "c" not in ids, f"{ids}")

print("\n=== Разрешённые значения количества ===")
check("допустимы ровно 2/4/6/8", auto_match.ALLOWED_PAIR_COUNTS == (2, 4, 6, 8), f"{auto_match.ALLOWED_PAIR_COUNTS}")


class _Q:
    def __init__(self, data):
        self.data = data


for good in (2, 4, 6, 8):
    check(f"read_config принимает {good}", auto_match.read_config(_Q({"count": good})) == good)
for bad in (3, 5, 7, 0, 1, 9, -2, None, "abc", 2.5):
    check(f"read_config отвергает {bad!r} (-> 0)", auto_match.read_config(_Q({"count": bad})) == 0, f"{auto_match.read_config(_Q({'count': bad}))}")

passed = sum(1 for _, ok in results if ok)
print(f"\n{'='*58}\nИТОГ: {passed}/{len(results)} PASS")
for n, ok in results:
    if not ok:
        print("  FAILED:", n)
raise SystemExit(0 if passed == len(results) else 1)
