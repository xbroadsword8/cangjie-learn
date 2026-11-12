# Cangjie Learn (倉頡學習版)

[English](README.en.md) | [繁體中文](README.md)

[![Download Cangjie Learn](https://img.shields.io/github/v/release/xbroadsword8/cangjie-learn?label=Download%20for%20Windows&style=for-the-badge&logo=windows)](https://github.com/xbroadsword8/cangjie-learn/releases/latest)

Download the installer, run it, and start typing.

**Cangjie Learn** is a Cangjie input method for Traditional Chinese that learns as you type: it picks candidates from the characters you just typed and remembers which characters you actually use. Available for Windows 10/11, Linux (IBus) and macOS.

## Why

Many Cangjie codes are shared by several characters. Classic Cangjie input methods rank them by a fixed frequency, so the same code always gives the same character. 已 and 己 share a code, for example, so either 已經 or 自己 always needs a manual pick.

Cangjie Learn instead:

- **Uses context**: looks at the previous 1–3 characters and whether a candidate forms a common word with them. After 自 it offers 己, after 而 it offers 已, and typing 自己 a lot does not make a sentence-initial 已經 turn into 己經.
- **Learns your choices**: picking a different candidate counts as a correction and moves it up next time.
- **Exact codes first**: characters matching the full code always rank above completions of a longer code. Completions show the remaining components in small orange text, which helps you learn the radicals.
- **Punctuation like 酷倉 (Cool Cangjie)**: in Chinese mode the punctuation keys give ASCII punctuation; **hold Ctrl for Chinese punctuation**, so code and URLs need no mode switch. You can also switch to full-width punctuation by default, like Microsoft Cangjie.

## Download and install (Windows)

Download `cangjie-learn-setup-<date>.exe` from [Releases](https://github.com/xbroadsword8/cangjie-learn/releases/latest):

1. Run the installer and click "Yes" when Windows asks for permission.
2. Cangjie Learn is added to the input method list of "Chinese (Traditional, Taiwan)".
3. Press **Win+Space** to switch to it. A 倉 icon appears in the taskbar, next to a 中/英 icon showing the current Chinese/English mode.

The installer is not code-signed, so Windows SmartScreen may show "Windows protected your PC" on first run. Click "More info → Run anyway".

- **Update**: run the newer installer. The old version is removed automatically and your learning data is kept.
- **Uninstall**: Settings → Apps → Installed apps → Cangjie Learn (倉頡學習版). Learning data is kept by default.

Linux and macOS currently need to be built from source; see "Building" below.

## Usage

| Key | Action |
|---|---|
| Shift (tap) | Toggle Chinese / English |
| Shift+Space | Toggle full-width / half-width letters and digits (Windows) |
| Space | Commit the first candidate |
| 1–9 | Pick a candidate |
| `-` `=` or PageUp / PageDown | Previous / next page |
| Enter | Commit the typed code as plain letters |
| Esc | Cancel |

### Ctrl + punctuation

| Keys | Output | Keys | Output |
|---|---|---|---|
| Ctrl+, | ， | Ctrl+. | 。 |
| Ctrl+; | ； | Ctrl+Shift+; | ： |
| Ctrl+Shift+/ | ？ | Ctrl+Shift+1 | ！ |
| Ctrl+' or Ctrl+\ | 、 | Ctrl+[ / ] | 「 」 |
| Ctrl+Shift+[ / ] | 『 』 | Ctrl+Shift+9 / 0 | （ ） |
| Ctrl+Shift+, / . | 《 》 | Ctrl+Shift+6 | …… |
| Ctrl+Shift+- | —— | Ctrl+Shift+` | ～ |

### Options

**Right-click** the 倉 or 中/英 icon in the taskbar (on Linux use the IBus input method menu, on macOS the input menu in the menu bar):

- **Clear invalid code with Space** (on by default): when a mistyped code has no candidates, Space clears it instead of leaving it stuck.
- **Full-width punctuation** (off by default): for Microsoft Cangjie users. Keys such as `，。；：？！（）「」` give full-width punctuation without Ctrl. `@ # - = /`, common in URLs, email and math, stay half-width.
- **Full-width letters and digits**: same as Shift+Space.

## Learning data and privacy

- Learning data stays on your own computer, and the input method itself **never connects to the internet**:
  - Windows: `%APPDATA%\PIME\cjlearn\user.db`
  - Linux: `~/.local/share/cangjie-learn/user.db`
  - macOS: `~/Library/Application Support/CangjieLearn/user.db`
- To share learning data between computers you can set up your own git repository for syncing (off by default); see the [development notes](docs/開發筆記.md) (Chinese).

## Limitations

- The Windows version supports Windows 10/11 (x64) only.
- The Windows 11 Start menu search box is a sandboxed app that cannot read your learning data. There, candidates come from the built-in dictionary only (typing works normally; nothing learned there is saved).
- macOS: build it yourself and add it manually in System Settings → Keyboard → Input Sources. Linux: `install.sh` currently targets IBus on GNOME.

## Building

The candidate logic has three implementations, kept identical step by step by differential tests: Python (Linux), Rust (Windows) and Swift (macOS).

```bash
# Linux (IBus): build the dictionary and register with ibus (no root needed)
./install.sh
python3 -m pytest -q tests
```

```bash
# Windows: cross-compile on Linux and build the NSIS installer (needs mingw-w64 and rustup target x86_64-pc-windows-gnu)
windows/package-tsf.sh
```

```bash
# macOS: build on a Mac and install to ~/Library/Input Methods (generate data/model.db first)
mac/build.sh
```

Implementation details, test methods and pitfalls are in the [development notes](docs/開發筆記.md) (Chinese).

### Layout

| Path | Contents |
|---|---|
| `cjlearn/` | Python core (composer, candidate model, learning) and the IBus engine |
| `windows/tsf/` | Windows version: the New Chewing TSF shell adapted to Cangjie (`crates/cangjie_core` is the Rust port of the core, `tip/` is the shell) |
| `windows/installer/` | Windows installer (NSIS) |
| `mac/` | macOS version: `Core/` Swift port of the core, `App/` InputMethodKit shell |
| `scripts/build_data.py` | Builds `data/model.db` from the code table and word frequencies |
| `tests/` | Logic tests, IBus end-to-end tests, cross-implementation differential tests |

## Acknowledgements and license

This input method is built on the work of many people. Thank you to:

- **Chu Bong-Foo (朱邦復)**, who invented the Cangjie input method and gave up its patent so that everyone can use it freely.
- **ChineseCJ (倉頡之友‧馬來西亞, chinesecj.com)** and the maintainers of ibus-table-chinese (Yu Yuwei, Caius Chance, Ding-Yi Chen, Mike FABIAN and others), who compiled and published the Cangjie 3 code table. Our table comes from [ibus-table-chinese](https://github.com/mike-fabian/ibus-table-chinese).
- **The Chewing (新酷音) project team**:
  - The Windows TSF shell is adapted from [windows-chewing-tsf](https://github.com/chewing/windows-chewing-tsf) (GPL-3.0-or-later). We replaced the Zhuyin engine with our Cangjie core; most of the windowing, icons, installation and compatibility work is theirs, built up over many years. Their copyright notices and license are kept in `windows/tsf/`.
  - Word frequencies come from [libchewing-data](https://github.com/chewing/libchewing-data) (LGPL-2.1-or-later).
- **The PIME project** ([EasyIME/PIME](https://github.com/EasyIME/PIME)): the earlier Windows version (`windows/pime/`) runs on PIME.
- **酷倉 (Cool Cangjie)**: the "hold Ctrl for Chinese punctuation" habit follows how it works.
- The installer is built with [NSIS](https://nsis.sourceforge.io/) and bundles [MinGit](https://github.com/git-for-windows/git) (Git for Windows, GPL-2.0) for syncing learning data.

License: [GPL-3.0](LICENSE). You may use, modify and redistribute it freely; if you distribute a modified version, you must publish its source code under the same license.

This software is provided "as is", without warranty of any kind.

Windows is a trademark of Microsoft. This project is not affiliated with Microsoft.
