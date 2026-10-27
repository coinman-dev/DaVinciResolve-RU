[English](/README.md) | [Русский](/README.ru_RU.md)

# DaVinciResolve-RU

[![DaVinci Resolve 21](https://img.shields.io/badge/DaVinci%20Resolve-21-233A51.svg)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE.svg)](#requirements)
[![Downloads](https://img.shields.io/github/downloads/coinman-dev/DaVinciResolve-RU/total.svg)](https://github.com/coinman-dev/DaVinciResolve-RU/releases/latest)

**DaVinciResolve-RU** completes the Russian interface translation of DaVinci Resolve 21. The official translation covers about 16,500 of 29,000 strings. The project adds almost 20,000 missing strings, the Fusion page included. Resolve's own files aren't changed.

## Quick start

Open PowerShell and run:

```powershell
irm https://github.com/coinman-dev/DaVinciResolve-RU/releases/latest/download/Install-ResolveRU.ps1 | iex
```

Or download [`Install-ResolveRU.ps1`](https://github.com/coinman-dev/DaVinciResolve-RU/releases/latest/download/Install-ResolveRU.ps1) from the latest release and choose *Run with PowerShell*. The script finds Resolve and opens a menu:

```text
  DaVinci Resolve 21.1.2.10
  Folder: C:\Program Files\Blackmagic Design\DaVinci Resolve
  Translation completion: not installed

   * 1. Install / update
     2. Remove
     0. Exit
```

Close DaVinci Resolve before installing. If Resolve is in Program Files, the script asks for administrator rights itself.

Installation puts a menu into the Resolve folder: `DaVinciResolve-RU\DaVinciResolve-RU.cmd` (usually `C:\Program Files\Blackmagic Design\DaVinci Resolve\DaVinciResolve-RU\DaVinciResolve-RU.cmd`). Double-click it to update or remove the translation. There's no need to download the script again.

The Resolve interface language must be Russian, or Auto on Russian Windows: **DaVinci Resolve → Preferences → User → UI Settings → Language**.

## How it works

The Resolve translations are Qt `.qm` files embedded in `Resolve.exe` and `fusionsystem.dll`. The script puts two files into the Resolve folder:

| File | What it is |
|---|---|
| `resolve_ru_extra.qm` | the missing Russian strings |
| `dxva2.dll` | the translation loader |

`Resolve.exe` uses the system library `dxva2.dll` and looks for it in its own folder first. The loader passes all its functions to the system `dxva2.dll` unchanged. It also watches which translations Resolve installs. When Resolve installs its Russian translation, the loader installs `resolve_ru_extra.qm` in front of it. Resolve looks a string up there first and falls back to its own translation. With an interface language other than Russian, the loader does nothing.

The loader source is [`loader/dxva2.c`](loader/dxva2.c). The script doesn't replace a foreign `dxva2.dll` already in the Resolve folder.

## Updating and removing

- **New translation:** run `DaVinciResolve-RU.cmd` from the Resolve folder and choose *Install / update*. The script downloads the latest release.
- **Resolve update:** if the translation is gone after an update, install it again. Strings new in that version stay in English until the next translation release.
- **Removing:** *Remove* (`-Action Remove`) deletes `dxva2.dll`, `resolve_ru_extra.qm` and the `DaVinciResolve-RU` folder. You can also delete them by hand.

## Parameters

| Parameter | Purpose |
|---|---|
| `-Action Menu` | menu (default) |
| `-Action Install` | install or update |
| `-Action Remove` | remove |
| `-Action Status` | show the state |
| `-ResolvePath <folder>` | the Resolve folder, if the script didn't find it |
| `-Release v1.0.0` | a specific release instead of the latest |
| `-Source <folder>` | take `dxva2.dll` and `resolve_ru_extra.qm` from a local folder |
| `-Yes` | no questions |
| `-UILang ru\|en` | language of the script messages (default: the Windows language) |
| `-NoPause` | don't wait for a key before exiting |

Release files are verified with `SHA256SUMS.txt`.

## Antivirus

The loader works the way some malware does: a DLL named after a system library, in a program folder. An antivirus may therefore flag it. The loader is open source and builds from [`loader/dxva2.c`](loader/dxva2.c) with `python -I tools/build_loader.py`. Please report a false positive to the antivirus vendor and in [Issues](https://github.com/coinman-dev/DaVinciResolve-RU/issues).

## Translation

- About 10,000 strings are newly translated with the official terminology of the Resolve Russian translation. About 7,400 more reuse the official translation of the same string elsewhere in the interface.
- Product names, formats and branded features (Magic Mask, Speed Warp, IntelliTrack) stay in Latin script.
- About 330 strings that no Resolve language file has were collected from the running program and translated too.
- A few official strings in the preferences are replaced with shorter ones: the original text didn't fit.

Translation errors and untranslated strings: [Issues](https://github.com/coinman-dev/DaVinciResolve-RU/issues).

## Requirements

- DaVinci Resolve 21, Windows x64. Tested with DaVinci Resolve Studio 21.1.2.
- Windows PowerShell 5.1 or PowerShell 7.

## For developers

The translation pipeline is described in [`AGENTS.md`](AGENTS.md). Building a release:

```powershell
python -I tools/build.py                # dist\resolve_ru_extra.qm
python -I tools/build_loader.py         # dist\dxva2.dll (clang from the Windhawk developer tools)
python -I tools/package.py v1.0.0       # dist\release\: ASCII copy of the installer, files, SHA256SUMS.txt
gh release create v1.0.0 dist/release/* --title v1.0.0 --notes-file CHANGELOG.md
```

`Install-ResolveRU.ps1` in the repository is UTF-8 with a BOM. The release gets a plain ASCII copy: with `irm | iex`, Windows PowerShell 5.1 reads a file from GitHub Releases as Latin-1.

The Windhawk mod [`mod/davinci-resolve-ru.wh.cpp`](mod/davinci-resolve-ru.wh.cpp) does the same as the loader. It can also log the strings Resolve shows untranslated, which is what it's for: working on the translation. Don't enable it together with the loader.

## License

[MIT](LICENSE).

---
DaVinci Resolve and Blackmagic Design are trademarks of Blackmagic Design Pty. Ltd. This project is not affiliated with Blackmagic Design.
