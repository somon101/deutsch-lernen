/// Mirrors TrueFalseView.tsx: correct iff the learner's Верно/Неверно
/// pick equals the stored `correct` boolean — no text comparison involved.
bool gradeTrueFalse(bool selected, bool correct) => selected == correct;
