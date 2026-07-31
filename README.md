<div align="center">

# RustDevblogCheatChecker

**Fast Windows file verification by exact size and SHA-256.**  
**Быстрая проверка файлов Windows по точному размеру и SHA-256.**

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-2783DE?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-2783DE?style=flat-square)
![Everything](https://img.shields.io/badge/Powered%20by-Everything-D5803B?style=flat-square)
![Version](https://img.shields.io/badge/version-1.1.0-46A171?style=flat-square)

[English](#english) · [Русский](#русский)

</div>

> [!IMPORTANT]
> This project is built on the original **Everything** search engine and the **ES** command-line interface created by [voidtools](https://www.voidtools.com/). Everything and ES are third-party software. This project is not affiliated with or endorsed by voidtools.
>
> Этот проект основан на оригинальной поисковой системе **Everything** и консольном интерфейсе **ES**, созданных [voidtools](https://www.voidtools.com/). Everything и ES являются сторонним программным обеспечением. Проект не связан с voidtools и не является официальным продуктом voidtools.

---

# English

## Overview

RustDevblogCheatChecker searches all drives indexed by Everything and checks files against `byte size | SHA-256` pairs from `List/list.txt`.

The scanner is optimized to avoid hashing every file on the computer:

1. ES queries Everything only for files whose byte size appears in the hash list.
2. SHA-256 is calculated only for those candidates.
3. Results are displayed after the complete scan finishes.

This approach is significantly faster than reading and hashing every file on every drive.

## Features

- Searches all drives configured in Everything.
- Filters candidates by exact byte size before hashing.
- Verifies candidates using SHA-256.
- Parallel hashing on a hardware-accelerated SHA-256 provider, one thread per logical CPU by default.
- Includes optimized launchers for SSD/NVMe and HDD storage.
- Prints matching paths in red after the full verification completes.
- Reports every candidate it could **not** read instead of silently counting it as clean.
- Downloads ES and portable Everything from voidtools.com when they are missing, each pinned to a known SHA-256.
- Automatically downloads database-only updates.
- Validates downloaded databases using SHA-256 before installation.
- Continues with the local database when the update server is unavailable.

## Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1 or PowerShell 7+.
- Administrator privileges. Everything needs them to index NTFS volumes, and the scanner needs them to read protected files.
- Nothing else. If [Everything](https://www.voidtools.com/) and ES are not present, they are downloaded on the first run.

## Project structure

```text
RustDevblogCheatChecker/
├── Utils/
│   ├── es.exe            (downloaded when missing)
│   ├── Everything.exe    (downloaded only when Everything is not running)
│   └── Find-File.ps1
├── List/
│   └── list.txt
├── Run-SSD.bat
├── Run-HDD.bat
├── manifest.json
└── README.md
```


## Quick start

Run the appropriate launcher as Administrator:

- `Run-SSD.bat` — one hashing thread per logical CPU.
- `Run-HDD.bat` — 2 hashing threads.

That is all. On the first run the scanner fetches whatever is missing from `Utils`, and `List/list.txt` keeps itself up to date.

If Everything is already installed and running, that instance is used as it is — check its index settings so every drive you care about is covered. Otherwise a portable copy is downloaded and started.

To build your own database instead, replace the size and SHA-256 pairs in `List/list.txt`.

Manual launch:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Utils\Find-File.ps1"
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `-Threads <1-64>` | `0` (auto) | Hashing threads. `0` uses one thread per logical CPU. |
| `-Reindex` | off | Force Everything to rebuild its database before scanning. |
| `-SkipUpdate` | off | Skip the online manifest check and scan with the local database. |
| `-NoDownload` | off | Never fetch ES or Everything; a missing tool becomes an error. |
| `-NoWait` | off | Exit without waiting for a key press, for unattended runs. |

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Utils\Find-File.ps1" -Threads 4 -SkipUpdate
```

## Tools

Two voidtools programs are required, and the scanner fetches them itself when they are missing from `Utils`:

| Tool | Version | Fetched when |
|---|---|---|
| ES (command line interface) | 1.1.0.37 | `Utils\es.exe` is missing |
| Everything (portable) | 1.4.1.1032 | Everything is not running **and** `Utils\Everything.exe` is missing |

Downloads come from `https://www.voidtools.com/` over HTTPS. The package matching the machine's architecture (x64, x86, ARM64) is chosen automatically, and the executable extracted from it is checked against a SHA-256 pinned in the script before it is installed or run. On mismatch the file is discarded and the scan aborts.

A running Everything is always preferred. The portable copy is started only when nothing is running, and the scanner then waits for the index to be built before scanning.

`-NoDownload` disables all of this: a missing tool becomes an error telling you what to install by hand.

### About `-Reindex`

Everything tracks NTFS volumes live through the USN journal, so its index is already current and a rebuild changes nothing for a size lookup. `-Reindex` exists for volumes Everything cannot watch live — non-NTFS media such as exFAT drives, and network locations.

ES queues the rebuild and returns immediately, so the scanner then polls the index size until it stops changing (up to 10 minutes). This is a best-effort wait, not a guarantee: on a very large machine let Everything settle before trusting a `-Reindex` run.

## Hash-list format

Each non-empty line in `List/list.txt` must contain an exact byte size and SHA-256 hash separated by `|`:

```text
1048576 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
5242880 | 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

- The size must be specified in bytes.
- SHA-256 must contain exactly 64 hexadecimal characters.
- Empty lines and lines beginning with `#` are ignored.
- Hash comparison is case-insensitive.
- Anything after a second `|` is treated as a comment.
- The same size may appear on several lines with different hashes.

## Update system

- When a newer database is detected, the scanner downloads only `List/list.txt`. The PowerShell script and BAT launchers are not replaced.
- Program updates are notification-only and are never installed automatically.

## Performance recommendations

| Storage | Recommended threads | Launcher |
|---|---:|---|
| NVMe / SSD | auto (one per logical CPU) | `Run-SSD.bat` |
| Single HDD | 1–2 | `Run-HDD.bat` |
| Multiple physical drives | 2–8 | Manual `-Threads` value |

More threads are not always faster. Excessive parallel reads can reduce HDD performance because the drive head must constantly seek between files.

## Reading the results

The final line reports what was actually verified:

```text
Finished in 4.2 s (hashing 3.1 s). Verified: 812 file(s), 1.90 GB at 627 MB/s. Matches: 0. Unverified: 3. Threads: 16.
```

`Unverified` counts candidates that could not be opened — usually files in protected locations or held under an exclusive lock. Those files were **not** checked. A run that reports no matches but a non-zero `Unverified` count is not a clean result; re-run as Administrator.

## Security and privacy

- File names, contents, and hashes are processed locally.
- Only `manifest.json` and database updates are requested from GitHub, over HTTPS.
- ES and portable Everything are downloaded from voidtools.com and executed. Both are checked against a SHA-256 pinned in the script and discarded on mismatch. Use `-NoDownload` if you would rather install them yourself.
- A downloaded database is installed only after its SHA-256 matches the value in `manifest.json`.
- The hash and the file it verifies come from the same repository, so this check protects against a corrupt or truncated download — not against a compromised repository. There is no code signature to fall back on.
- Use the scanner only on systems and files you are authorized to inspect.

## Everything attribution

The fast filename and metadata search is provided by the original **Everything** software from voidtools. RustDevblogCheatChecker acts as a PowerShell-based size and SHA-256 verification layer on top of Everything and ES.

- Official website: [voidtools.com](https://www.voidtools.com/)
- Everything documentation: [voidtools.com/support/everything](https://www.voidtools.com/support/everything/)
- ES documentation: [Everything Command Line Interface](https://www.voidtools.com/support/everything/command_line_interface/)


---

# Русский

## Описание

RustDevblogCheatChecker выполняет поиск по всем дискам, проиндексированным Everything, и сверяет файлы с парами `размер в байтах | SHA-256` из `List/list.txt`.

Сканер не вычисляет хеш каждого файла на компьютере:

1. ES запрашивает у Everything только файлы, размеры которых присутствуют в списке.
2. SHA-256 вычисляется только для отобранных кандидатов.
3. Совпадения выводятся после завершения полной проверки.

Такой подход значительно быстрее последовательного чтения и хеширования всех файлов на всех дисках.

## Возможности

- Поиск по всем дискам, настроенным в Everything.
- Предварительная фильтрация по точному размеру файла.
- Финальная проверка по SHA-256.
- Многопоточное хеширование на аппаратно-ускоренном провайдере SHA-256, по потоку на логическое ядро.
- Отдельные режимы запуска для SSD/NVMe и HDD.
- Вывод найденных путей красным цветом после полной проверки.
- Каждый файл, который **не удалось** прочитать, попадает в отчёт, а не считается молча чистым.
- Скачивание ES и портативного Everything с voidtools.com, если их нет, с проверкой каждого по закреплённому SHA-256.
- Автоматическое обновление только базы хешей.
- Проверка SHA-256 загруженной базы перед установкой.
- Использование локальной базы при отсутствии интернета или недоступности сервера.

## Требования

- Windows 10 или Windows 11.
- Windows PowerShell 5.1 или PowerShell 7+.
- Права администратора. Они нужны Everything для индексации томов NTFS и сканеру для чтения защищённых файлов.
- Больше ничего. Если [Everything](https://www.voidtools.com/) и ES отсутствуют, они скачиваются при первом запуске.

## Структура проекта

```text
RustDevblogCheatChecker/
├── Utils/
│   ├── es.exe            (скачивается, если отсутствует)
│   ├── Everything.exe    (скачивается, только если Everything не запущен)
│   └── Find-File.ps1
├── List/
│   └── list.txt
├── Run-SSD.bat
├── Run-HDD.bat
├── manifest.json
└── README.md
```


## Быстрый запуск

Запусти подходящий BAT-файл от имени администратора:

- `Run-SSD.bat` — по потоку хеширования на логическое ядро.
- `Run-HDD.bat` — 2 потока хеширования.

Это всё. При первом запуске сканер сам догрузит недостающее в `Utils`, а `List/list.txt` обновляется автоматически.

Если Everything уже установлен и запущен, используется именно он — проверь в его настройках, что нужные диски включены в индекс. Иначе будет скачана и запущена портативная копия.

Чтобы собрать свою базу, замени пары размера и SHA-256 в `List/list.txt`.

Ручной запуск:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Utils\Find-File.ps1"
```

## Параметры

| Параметр | По умолчанию | Описание |
|---|---|---|
| `-Threads <1-64>` | `0` (авто) | Потоки хеширования. `0` — по потоку на логическое ядро. |
| `-Reindex` | выкл | Принудительно перестроить базу Everything перед сканированием. |
| `-SkipUpdate` | выкл | Пропустить проверку обновлений и работать с локальной базой. |
| `-NoDownload` | выкл | Никогда не скачивать ES и Everything; отсутствие инструмента станет ошибкой. |
| `-NoWait` | выкл | Не ждать нажатия клавиши при выходе, для запуска по расписанию. |

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Utils\Find-File.ps1" -Threads 4 -SkipUpdate
```

## Инструменты

Нужны две программы voidtools, и сканер сам догружает их, если в `Utils` их нет:

| Инструмент | Версия | Когда скачивается |
|---|---|---|
| ES (консольный интерфейс) | 1.1.0.37 | отсутствует `Utils\es.exe` |
| Everything (портативный) | 1.4.1.1032 | Everything не запущен **и** отсутствует `Utils\Everything.exe` |

Загрузка идёт с `https://www.voidtools.com/` по HTTPS. Пакет под архитектуру машины (x64, x86, ARM64) выбирается автоматически, а извлечённый из него исполняемый файл сверяется с SHA-256, закреплённым в скрипте, до установки и запуска. При расхождении файл выбрасывается, а сканирование прерывается.

Уже запущенный Everything всегда в приоритете. Портативная копия стартует, только если ничего не запущено, и тогда сканер дожидается построения индекса.

`-NoDownload` полностью это отключает: отсутствие инструмента становится ошибкой с указанием, что поставить вручную.

### О параметре `-Reindex`

Everything отслеживает тома NTFS в реальном времени через журнал USN, поэтому его индекс уже актуален, и перестроение ничего не меняет для поиска по размеру. `-Reindex` нужен для томов, которые Everything не может отслеживать вживую: не-NTFS носители (например, exFAT) и сетевые расположения.

ES только ставит задачу на перестроение и сразу возвращает управление, поэтому скрипт затем опрашивает размер индекса, пока тот не перестанет меняться (до 10 минут). Это ожидание по возможности, а не гарантия: на очень большой машине дай Everything устояться, прежде чем полагаться на результат `-Reindex`.

## Формат списка хешей

Каждая непустая строка `List/list.txt` должна содержать точный размер в байтах и SHA-256, разделённые символом `|`:

```text
1048576 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
5242880 | 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

- Размер указывается в байтах.
- SHA-256 должен содержать ровно 64 шестнадцатеричных символа.
- Пустые строки и строки, начинающиеся с `#`, игнорируются.
- Регистр символов SHA-256 не имеет значения.
- Всё, что идёт после второго `|`, считается комментарием.
- Один и тот же размер может встречаться в нескольких строках с разными хешами.

## Система обновлений

- Если найдена новая версия базы, скрипт скачивает и заменяет только `List/list.txt`. PowerShell-скрипт и BAT-файлы не изменяются.
- Обновления программы устанавливаются вручную. Скрипт только показывает уведомление и ссылку.

## Рекомендации по производительности

| Накопитель | Рекомендуемые потоки | Запуск |
|---|---:|---|
| NVMe / SSD | авто (по одному на логическое ядро) | `Run-SSD.bat` |
| Один HDD | 1–2 | `Run-HDD.bat` |
| Несколько физических дисков | 2–8 | Ручной параметр `-Threads` |

Больше потоков не всегда означает большую скорость. Чрезмерное количество параллельных операций чтения может замедлить HDD из-за постоянного перемещения головки диска.

## Как читать результат

Последняя строка показывает, что именно было проверено:

```text
Finished in 4.2 s (hashing 3.1 s). Verified: 812 file(s), 1.90 GB at 627 MB/s. Matches: 0. Unverified: 3. Threads: 16.
```

`Unverified` — количество кандидатов, которые не удалось открыть: обычно это файлы в защищённых расположениях или занятые эксклюзивной блокировкой. Эти файлы **не проверены**. Запуск без совпадений, но с ненулевым `Unverified`, чистым результатом не является — перезапусти от имени администратора.

## Безопасность и конфиденциальность

- Имена, содержимое и хеши файлов обрабатываются локально.
- Через GitHub по HTTPS запрашиваются только `manifest.json` и обновления базы.
- ES и портативный Everything скачиваются с voidtools.com и запускаются. Оба сверяются с SHA-256, закреплённым в скрипте, и выбрасываются при расхождении. Если предпочитаешь ставить их сам — используй `-NoDownload`.
- Загруженная база устанавливается только после успешной проверки SHA-256.
- Хеш и проверяемый им файл берутся из одного репозитория, поэтому эта проверка защищает от повреждённой или оборванной загрузки, но не от компрометации самого репозитория. Подписи кода, на которую можно было бы опереться, нет.
- Используй сканер только на компьютерах и для файлов, которые имеешь право проверять.

## Упоминание Everything

Быстрый поиск имён файлов и метаданных обеспечивает оригинальная программа **Everything** от voidtools. RustDevblogCheatChecker является PowerShell-надстройкой над Everything и ES, которая добавляет фильтрацию по размеру и проверку SHA-256.

- Официальный сайт: [voidtools.com](https://www.voidtools.com/)
- Документация Everything: [voidtools.com/support/everything](https://www.voidtools.com/support/everything/)
- Документация ES: [Everything Command Line Interface](https://www.voidtools.com/support/everything/command_line_interface/)


---

<div align="center">

**RustDevblogCheatChecker is a community project built on Everything by voidtools.**  
**RustDevblogCheatChecker — сторонний проект, основанный на Everything от voidtools.**

</div>
