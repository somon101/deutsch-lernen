"""Verification utility (not part of the app itself): dumps this repo's
Python parser/generator port's output for lesson1/lesson2 as JSON, for
diffing against the real TypeScript parser's output. See
import_legacy_content.py's docstring — this is how Решение 1/2's fidelity
was empirically proven before that script's first real run.

Run from backend/: venv/Scripts/python.exe scripts/dump_py_reference.py
"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.legacy_parser.generate_exercises import build_lesson_exercises  # noqa: E402
from app.legacy_parser.parse_lesson_text import parse_lesson_text  # noqa: E402
from app.legacy_parser.parse_vocabulary import parse_vocabulary  # noqa: E402

LESSONS = [
    {
        "id": "lesson1",
        "dir": "c:/Users/Somon/Desktop/lesson/lesson1",
        "vocab_file": "словарь.txt",
        "material_file": "урок1.txt",
    },
    {
        "id": "lesson2",
        "dir": "c:/Users/Somon/Desktop/lesson/lessons/lesson2",
        "vocab_file": "словарь.txt",
        "material_file": "урок.txt",
    },
]

out = {}

for lesson in LESSONS:
    with open(f"{lesson['dir']}/{lesson['vocab_file']}", encoding="utf-8") as f:
        vocab_raw = f.read()
    with open(f"{lesson['dir']}/{lesson['material_file']}", encoding="utf-8") as f:
        material_raw = f.read()

    vocabulary = parse_vocabulary(vocab_raw, lesson["id"])
    parsed = parse_lesson_text(material_raw)
    blocks = parsed["blocks"]
    phrases = parsed["phrases"]

    exercises = build_lesson_exercises(lesson["id"], vocabulary, phrases)

    out[lesson["id"]] = {
        "vocabulary": vocabulary,
        "materialBlocks": blocks,
        "phrases": phrases,
        "exercises": {"miniTest": exercises["minitest"], "practice": exercises["practice"], "review": exercises["review"]},
    }

OUT_PATH = "C:/Users/Somon/AppData/Local/Temp/claude/c--Users-Somon-Desktop-lesson/4bdcc285-12c3-4a2d-902a-a5a9de7062fe/scratchpad/py_reference.json"
with open(OUT_PATH, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=2)
print("wrote py_reference.json")
