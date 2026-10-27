# DaVinciResolve-RU

Дополнение русского перевода интерфейса DaVinci Resolve. Официальный русский
перевод Resolve 21 неполный; проект переводит недостающие строки и подгружает
их в Resolve модом Windhawk, не изменяя файлы программы.

Подробный контекст, история решений и текущее состояние —
`.ai/PROJECT_CONTEXT.md` (локальный файл, не в git). Прочитай его перед
работой.

## Как это устроено

- Переводы Resolve — файлы Qt `.qm`, вшитые в программу:
  - основной интерфейс — 18 сжатых (qCompress) `.qm` в `Resolve.exe`, без
    тега языка, язык определяется по алфавиту;
  - страница Fusion — свои `.qm` в `fusionsystem.dll` (часть сжата, часть нет,
    с тегами языка).
- Мод `mod/davinci-resolve-ru.wh.cpp` (Windhawk, `Resolve.exe`) перехватывает
  `QCoreApplication::installTranslator` в `Qt5Core.dll`. Когда Resolve
  ставит свой русский переводчик (проверка: строки `ActionDefinitions`
  Undo/Redo/Save Project переводятся кириллицей), мод загружает
  `%ProgramData%\DaVinciResolve-RU\resolve_ru_extra.qm` и ставит его перед
  русским — он ищется первым. Поэтому через него можно и переопределять
  официальные строки (`translations/overrides.json`).
- Настройка мода `logUntranslated` перехватывает
  `QCoreApplication::translate` и пишет в лог Windhawk каждую строку,
  показанную без перевода (`Untranslated: <контекст> | <строка>`).

## Конвейер (tools/)

Все скрипты Python запускаются с `-I` из корня проекта.

| Шаг | Команда | Результат |
| --- | --- | --- |
| Извлечь Resolve | `tools/extract.py "E:/DaVinci Resolve/Resolve.exe"` | `work/missing.json`, `work/ru_existing.json`, `work/extracted/` |
| Извлечь Fusion | `tools/extract_fusion.py "E:/DaVinci Resolve/fusionsystem.dll"` | `work/fusion_missing.json`, `work/fusion_ru_existing.json` |
| Глоссарий | `tools/glossary.py` | `work/glossary.tsv` (официальные термины) |
| Пакеты | `tools/make_batches.py --size 250` | `work/batches/bNNN.json`, только новые строки |
| Перевод | субагенты по `RULES.md` | `work/out/bNNN.json` |
| Проверка | `tools/check.py --all` | плейсхолдеры, теги, `&`, `...`, `:`, формы мн. числа |
| Строки из лога | `tools/runtime_batch.py work/untranslated.log` | `work/batches/rNNN.json` (ключ «контекст\u0004строка») |
| Слияние | `tools/assemble.py` | `translations/ru.json`, `translations/overrides.json` |
| Сборка | `tools/build.py` | `dist/resolve_ru_extra.qm` |

Установка для проверки: скопировать `dist/resolve_ru_extra.qm` в
`C:\ProgramData\DaVinciResolve-RU\`, мод — `tools/dev-install.ps1`
(`-LogUntranslated` включает запись непереведённых строк; сам просит права
администратора; нужны инструменты разработчика Windhawk). Лог мода —
`tools/dbwin.ps1 -Seconds N -Filter davinci-resolve-ru -OutFile <файл>`.
Перевод загружается только при запуске Resolve.

Проверка компиляции мода без установки:
`"C:/Program Files/Windhawk/Compiler/bin/clang++.exe" @"C:/Program Files/Windhawk/Compiler/compile_flags.txt" -I"C:/Program Files/Windhawk/Compiler/include" -fsyntax-only -Wall mod/davinci-resolve-ru.wh.cpp`

## Правила

- Перевод — по `RULES.md`: смысл, официальная терминология из глоссария,
  инфинитив для команд, «е» вместо «ё», латиница для продуктов и форматов.
- Не более трёх субагентов одновременно.
- `work/` и `dist/` не в git; переводы — в `translations/`. Существующие
  пакеты не пересоздавать: `make_batches.py` и `runtime_batch.py` только
  дописывают новые.
- Вывод кириллицы в консоль Bash искажается (cp1251) — для просмотра пиши в
  файл и читай инструментом Read.
- Публикация на GitHub (аккаунт coinman-dev) — только по решению
  пользователя.
