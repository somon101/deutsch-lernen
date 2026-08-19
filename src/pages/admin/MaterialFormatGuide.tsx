/**
 * Documents the exact syntax `content/parseLessonText.ts` recognizes, so the
 * in-admin help panel can never drift from what the parser actually does —
 * this text is the single source of truth; keep it in sync with that file.
 */
export default function MaterialFormatGuide() {
  return (
    <details className="material-format-guide">
      <summary>Формат материала</summary>
      <div className="material-format-guide__body">
        <p>
          Текст разбирается построчно (пустые строки игнорируются) тем же парсером, что и файлы существующих уроков —
          результат выглядит одинаково независимо от источника.
        </p>

        <table className="material-format-guide__table">
          <thead>
            <tr>
              <th>Что нужно</th>
              <th>Как написать</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Название урока</td>
              <td>
                Самая первая строка материала — что угодно, включая <code># Заголовок</code>
              </td>
            </tr>
            <tr>
              <td>Новый раздел (своя страница)</td>
              <td>
                <code>Шаг 1. Название раздела</code>
              </td>
            </tr>
            <tr>
              <td>Подраздел (внутри текущего раздела)</td>
              <td>
                <code>## Название</code> или строка, начинающаяся с эмодзи: <code>👥 Неформальное общение:</code>
              </td>
            </tr>
            <tr>
              <td>Карточка слова/фразы</td>
              <td>
                <code>Hallo! [ˈhaloː] — Привет!</code> — немецкий, транскрипция в квадратных скобках, тире-разделитель
                «пробел—пробел», перевод
              </td>
            </tr>
            <tr>
              <td>Транскрипция</td>
              <td>
                В квадратных скобках сразу после слова: <code>[ˈhaloː]</code>
              </td>
            </tr>
            <tr>
              <td>Перевод</td>
              <td>Всё, что после « — » (пробел, тире, пробел) в строке карточки</td>
            </tr>
            <tr>
              <td>Кнопка озвучивания</td>
              <td>Добавляется автоматически к каждой карточке слова/фразы — отдельно указывать не нужно</td>
            </tr>
            <tr>
              <td>Обычный текст (без карточки)</td>
              <td>Любая строка без « — » и не начинающаяся с эмодзи или «Шаг N.»</td>
            </tr>
            <tr>
              <td>Список, пример, примечание, диалог</td>
              <td>
                Отдельного синтаксиса нет — пишите обычными строками (для примечания в скобках) или карточками «фраза —
                перевод» для реплик диалога
              </td>
            </tr>
            <tr>
              <td>Где заканчивается блок</td>
              <td>На следующей непустой строке — каждая строка это один блок, кроме таблиц Markdown</td>
            </tr>
          </tbody>
        </table>

        <p className="material-format-guide__note">
          Также понимается Markdown: <code>**жирный**</code>, <code># Заголовок</code>, таблицы <code>| A | B |</code>{" "}
          и разделитель <code>---</code> — но обычный формат выше используется в существующих уроках и рекомендуется.
        </p>
      </div>
    </details>
  );
}
