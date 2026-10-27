[English](/README.md) | [Русский](/README.ru_RU.md)

# DaVinciResolve-RU

[![DaVinci Resolve 21](https://img.shields.io/badge/DaVinci%20Resolve-21-233A51.svg)](#требования)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE.svg)](#требования)
[![Downloads](https://img.shields.io/github/downloads/coinman-dev/DaVinciResolve-RU/total.svg)](https://github.com/coinman-dev/DaVinciResolve-RU/releases/latest)

**DaVinciResolve-RU** дополняет русский перевод интерфейса DaVinci Resolve 21. Официальный перевод покрывает около 16 500 из 29 000 строк. Проект добавляет почти 20 000 недостающих строк, включая страницу Fusion. Файлы Resolve при этом не меняются.

## Быстрый старт

Откройте PowerShell и выполните:

```powershell
irm https://github.com/coinman-dev/DaVinciResolve-RU/releases/latest/download/Install-ResolveRU.ps1 | iex
```

Или скачайте [`Install-ResolveRU.ps1`](https://github.com/coinman-dev/DaVinciResolve-RU/releases/latest/download/Install-ResolveRU.ps1) из последнего релиза и запустите его: «Выполнить с помощью PowerShell». Скрипт найдёт Resolve и откроет меню:

```text
  DaVinci Resolve 21.1.2.10
  Папка: C:\Program Files\Blackmagic Design\DaVinci Resolve
  Дополнение перевода: не установлено

   * 1. Установить / обновить
     2. Удалить
     0. Выход
```

Перед установкой закройте DaVinci Resolve. Если Resolve стоит в Program Files, скрипт сам запросит права администратора.

Установка кладёт меню в папку Resolve: `DaVinciResolve-RU\DaVinciResolve-RU.cmd` (обычно `C:\Program Files\Blackmagic Design\DaVinci Resolve\DaVinciResolve-RU\DaVinciResolve-RU.cmd`). Запустите его двойным щелчком, чтобы обновить перевод или удалить его. Скачивать скрипт заново не нужно.

Язык интерфейса Resolve должен быть русским или «Auto» при русской Windows: **DaVinci Resolve → Preferences → User → UI Settings → Language**.

## Как это устроено

Переводы Resolve — файлы Qt `.qm`, вшитые в `Resolve.exe` и `fusionsystem.dll`. Скрипт кладёт в папку Resolve два файла:

| Файл | Что это |
|---|---|
| `resolve_ru_extra.qm` | недостающие русские строки |
| `dxva2.dll` | загрузчик перевода |

`Resolve.exe` использует системную библиотеку `dxva2.dll` и ищет её сначала в своей папке. Загрузчик передаёт все её функции системной `dxva2.dll` без изменений. Кроме того, он отслеживает, какие переводы ставит Resolve. Когда Resolve ставит свой русский перевод, загрузчик ставит перед ним `resolve_ru_extra.qm`. Resolve ищет строку сначала там, а не найдя её, берёт из своего перевода. Если язык интерфейса не русский, загрузчик ничего не делает.

Исходный код загрузчика — [`loader/dxva2.c`](loader/dxva2.c). Скрипт не заменяет чужую `dxva2.dll`, если она уже лежит в папке Resolve.

## Обновление и удаление

- **Новый перевод:** запустите `DaVinciResolve-RU.cmd` из папки Resolve и выберите «Установить / обновить». Скрипт скачает последний релиз.
- **Обновление Resolve:** если после обновления перевод пропал, установите его снова. Строки, появившиеся в новой версии, будут на английском до следующего релиза перевода.
- **Удаление:** пункт «Удалить» (`-Action Remove`) удаляет `dxva2.dll`, `resolve_ru_extra.qm` и папку `DaVinciResolve-RU`. Можно удалить их и вручную.

## Параметры

| Параметр | Назначение |
|---|---|
| `-Action Menu` | меню (по умолчанию) |
| `-Action Install` | установить или обновить |
| `-Action Remove` | удалить |
| `-Action Status` | показать состояние |
| `-ResolvePath <папка>` | папка Resolve, если скрипт её не нашёл |
| `-Release v1.0.0` | конкретный релиз вместо последнего |
| `-Source <папка>` | взять `dxva2.dll` и `resolve_ru_extra.qm` из локальной папки |
| `-Yes` | без вопросов |
| `-UILang ru\|en` | язык сообщений скрипта (по умолчанию — язык Windows) |
| `-NoPause` | не ждать клавишу перед выходом |

Файлы из релиза проверяются по `SHA256SUMS.txt`.

## Антивирус

Загрузчик устроен так же, как некоторые вредоносные программы: это DLL с именем системной библиотеки в папке программы. Поэтому антивирус может принять его за угрозу. Код загрузчика открыт, он собирается из [`loader/dxva2.c`](loader/dxva2.c) командой `python -I tools/build_loader.py`. О ложном срабатывании сообщите производителю антивируса и в [Issues](https://github.com/coinman-dev/DaVinciResolve-RU/issues).

## Перевод

- Около 10 000 строк переведены заново по официальной терминологии русского перевода Resolve. Ещё около 7 400 взяты из официального перевода той же строки в другом месте интерфейса.
- Названия продуктов, форматов и функций с торговыми названиями (Magic Mask, Speed Warp, IntelliTrack) оставлены латиницей.
- Около 330 строк, которых нет ни в одном языковом файле Resolve, собраны прямо из работающей программы и тоже переведены.
- Несколько официальных строк в настройках заменены более короткими: в исходном виде текст не помещался.

Ошибки перевода и непереведённые строки: [Issues](https://github.com/coinman-dev/DaVinciResolve-RU/issues).

## Требования

- DaVinci Resolve 21, Windows x64. Проверено на DaVinci Resolve Studio 21.1.2.
- Windows PowerShell 5.1 или PowerShell 7.

## Для разработчиков

Конвейер перевода — в [`AGENTS.md`](AGENTS.md). Сборка релиза:

```powershell
python -I tools/build.py                # dist\resolve_ru_extra.qm
python -I tools/build_loader.py         # dist\dxva2.dll (clang из инструментов разработчика Windhawk)
python -I tools/package.py v1.0.0       # dist\release\: ASCII-копия установщика, файлы, SHA256SUMS.txt
gh release create v1.0.0 dist/release/* --title v1.0.0 --notes-file CHANGELOG.md
```

`Install-ResolveRU.ps1` в репозитории — UTF-8 с BOM. В релиз кладётся его копия только из ASCII-символов: Windows PowerShell 5.1 читает файл из GitHub Releases при `irm | iex` как Latin-1.

Мод Windhawk [`mod/davinci-resolve-ru.wh.cpp`](mod/davinci-resolve-ru.wh.cpp) делает то же, что загрузчик. Кроме того, он может записывать в лог строки, которые Resolve показывает без перевода. Он нужен для работы над переводом. Вместе с загрузчиком его не включайте.

## Лицензия

[MIT](LICENSE).

---
DaVinci Resolve и Blackmagic Design — товарные знаки Blackmagic Design Pty. Ltd. Проект не связан с Blackmagic Design.
