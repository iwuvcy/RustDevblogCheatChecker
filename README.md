<div align="center">

# RustDevblogCheatChecker

**Fast Windows file verification by exact size and SHA-256.**  
**Быстрая проверка файлов Windows по точному размеру и SHA-256.**

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-2783DE?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-2783DE?style=flat-square)
![Everything](https://img.shields.io/badge/Powered%20by-Everything-D5803B?style=flat-square)
![Version](https://img.shields.io/badge/version-1.0.0-46A171?style=flat-square)

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

1. Everything rebuilds its indexes for all configured drives.
2. ES queries only files whose byte size appears in the hash list.
3. SHA-256 is calculated only for those candidates.
4. Results are displayed after the complete scan finishes.

This approach is significantly faster than reading and hashing every file on every drive.

## Features

- Searches all drives configured in Everything.
- Filters candidates by exact byte size before hashing.
- Verifies candidates using SHA-256.
- Supports parallel hashing in Windows PowerShell 5.1 and newer.
- Includes optimized launchers for SSD/NVMe and HDD storage.
- Prints matching paths in red after the full verification completes.
- Automatically downloads database-only updates.
- Validates downloaded databases using SHA-256 before installation.
- Continues with the local database when the update server is unavailable.

## Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1 or PowerShell 7+.
- [Everything](https://www.voidtools.com/) installed and running.
- Administrator privileges are recommended for access to protected files.

## Project structure

```text
RustDevblogCheatChecker/
├── Utils/
│   ├── es.exe
│   └── Find-File.ps1
├── List/
│   └── list.txt
├── Run-SSD.bat
├── Run-HDD.bat
├── manifest.json
└── README.md
```


## Quick start

1. Install and start Everything.
2. Make sure every required drive is enabled in the Everything index settings.
3. Place `es.exe` inside the `Utils` directory.
4. Put the required size and SHA-256 pairs in `List/list.txt`.
5. Run the appropriate launcher, preferably as Administrator:
   - `Run-SSD.bat` — 12 hashing threads.
   - `Run-HDD.bat` — 2 hashing threads.

Manual launch:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Utils\Find-File.ps1" -Threads 8
```

The thread count can be set from `1` to `64`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Utils\Find-File.ps1" -Threads 4
```

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

## Update system

- When a newer database is detected, the scanner downloads only `List/list.txt`. The PowerShell script and BAT launchers are not replaced.
- Program updates are notification-only and are never installed automatically.

## Performance recommendations

| Storage | Recommended threads | Launcher |
|---|---:|---|
| NVMe / SSD | 8 | `Run-SSD.bat` |
| Single HDD | 1–2 | `Run-HDD.bat` |
| Multiple physical drives | 2–8 | Manual `-Threads` value |

More threads are not always faster. Excessive parallel reads can reduce HDD performance because the drive head must constantly seek between files.

## Security and privacy

- File names, contents, and hashes are processed locally.
- Only `manifest.json` and database updates are requested from GitHub.
- A downloaded database is installed only after its SHA-256 matches the value in `manifest.json`.
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

1. Everything перестраивает индексы всех настроенных дисков.
2. ES выбирает только файлы, размеры которых присутствуют в списке.
3. SHA-256 вычисляется только для отобранных кандидатов.
4. Совпадения выводятся после завершения полной проверки.

Такой подход значительно быстрее последовательного чтения и хеширования всех файлов на всех дисках.

## Возможности

- Поиск по всем дискам, настроенным в Everything.
- Предварительная фильтрация по точному размеру файла.
- Финальная проверка по SHA-256.
- Многопоточное хеширование в Windows PowerShell 5.1 и новее.
- Отдельные режимы запуска для SSD/NVMe и HDD.
- Вывод найденных путей красным цветом после полной проверки.
- Автоматическое обновление только базы хешей.
- Проверка SHA-256 загруженной базы перед установкой.
- Использование локальной базы при отсутствии интернета или недоступности сервера.

## Требования

- Windows 10 или Windows 11.
- Windows PowerShell 5.1 или PowerShell 7+.
- Установленный и запущенный [Everything](https://www.voidtools.com/).
- Для доступа к защищённым файлам рекомендуется запуск от имени администратора.

## Структура проекта

```text
RustDevblogCheatChecker/
├── Utils/
│   ├── es.exe
│   └── Find-File.ps1
├── List/
│   └── list.txt
├── Run-SSD.bat
├── Run-HDD.bat
├── manifest.json
└── README.md
```


## Быстрый запуск

1. Установи и запусти Everything.
2. Убедись, что все необходимые диски включены в настройках индексирования Everything.
3. Заполни `List/list.txt` парами размера и SHA-256.
4. Запусти подходящий BAT-файл, желательно от имени администратора:
   - `Run-SSD.bat` — 12 потоков хеширования.
   - `Run-HDD.bat` — 2 потока хеширования.

Ручной запуск:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Utils\Find-File.ps1" -Threads 8
```

Количество потоков можно установить от `1` до `64`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\Utils\Find-File.ps1" -Threads 4
```

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

## Система обновлений

- Если найдена новая версия базы, скрипт скачивает и заменяет только `List/list.txt`. PowerShell-скрипт и BAT-файлы не изменяются.
- Обновления программы устанавливаются вручную. Скрипт только показывает уведомление и ссылку.

## Рекомендации по производительности

| Накопитель | Рекомендуемые потоки | Запуск |
|---|---:|---|
| NVMe / SSD | 8 | `Run-SSD.bat` |
| Один HDD | 1–2 | `Run-HDD.bat` |
| Несколько физических дисков | 2–8 | Ручной параметр `-Threads` |

Больше потоков не всегда означает большую скорость. Чрезмерное количество параллельных операций чтения может замедлить HDD из-за постоянного перемещения головки диска.

## Безопасность и конфиденциальность

- Имена, содержимое и хеши файлов обрабатываются локально.
- Через GitHub запрашиваются только `manifest.json` и обновления базы.
- Загруженная база устанавливается только после успешной проверки SHA-256.
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
