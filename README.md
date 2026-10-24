# tmv

## About the project

`tmv` ("timer mv") is a file sorter written purely in Bash. It moves files into named folders based on presets or glob patterns, either on demand from the command line or automatically through a systemd user timer.

## Technical overview

### Repository layout

```
tmv/
├── install.sh          # installer (copy or symlink, systemd units, example env)
├── bin/
│   └── tmv             # entry point: argument parsing, dispatch
├── lib/
│   ├── presets.sh      # preset -> extensions map, selector -> globs
│   ├── sorter.sh       # core logic: tmv_move_matching
│   └── validate.sh     # env file parser and rule checks (tmv -t)
├── systemd/
│   ├── tmv.service     # oneshot service: validate, then sort
│   └── tmv.timer       # runs the service every 15 minutes
├── examples/
│   └── tmv.env         # example rules file
├── tests/
│   └── run.sh          # manual test script (works in /tmp/t)
├── DESIGN.md           # design decisions, edge cases, roadmap
└── LICENSE
```

### How it works

Both modes use the same core function, `tmv_move_matching <dir> <selector> <dest_name>`: one logic, two entry points.

- **CLI mode:** arguments are read in pairs (`<selector> <folder>`) and files are sorted in the current directory.
- **Timer mode:** `tmv.timer` triggers `tmv.service`, which first runs `tmv -t` (validation) and only then `tmv --env` (sorting). If the env file breaks a rule, the service fails and nothing is moved.

### Installed files

| Path | Purpose |
|---|---|
| `~/.local/share/tmv/` | program files (`bin/`, `lib/`) |
| `~/.local/bin/tmv` | symlink to the entry point |
| `~/.config/tmv/tmv.env` | your rules |
| `~/.config/systemd/user/tmv.{service,timer}` | systemd user units |

Everything is installed per user. No root is needed.

### Requirements

Bash 4+ (associative arrays), GNU `find`, `flock`, `readlink`, and `systemctl` (systemd) for timer mode.

## Getting started

```bash
git clone https://github.com/SamerKolasevic29/tmv.git
cd tmv
./install.sh
```

Then:

```bash
# 1. edit your rules
$EDITOR ~/.config/tmv/tmv.env

# 2. validate them
tmv -t

# 3. see what would happen, without moving anything
tmv -n --env

# 4. start the timer
systemctl --user enable --now tmv.timer
```

Or do steps 2 and 4 at once: `./install.sh --enable` validates the env and enables the timer only if the validation passes.

The timer does **not** start automatically after a plain install, because the example env sorts `~/Downloads` and you should review the rules first.

### Installer options

| Option | Description |
|---|---|
| *(none)* | copy the program, install units and the example env |
| `--enable` | also validate the env, then enable and start `tmv.timer` |
| `--link` | development mode: symlink `~/.local/bin/tmv` to the repo |
| `--uninstall` | remove tmv and the units (keeps `~/.config/tmv`) |

### Useful commands

```bash
systemctl --user list-timers tmv.timer   # next run
systemctl --user start tmv.service       # run now
journalctl --user -u tmv -e              # logs
loginctl enable-linger "$USER"           # keep the timer running without an active session
```

### Changing the interval

The default is every 15 minutes (`OnCalendar=*:0/15`). To override it without touching the repo:

```bash
systemctl --user edit tmv.timer
```

```ini
[Timer]
OnCalendar=
OnCalendar=hourly
```

The empty `OnCalendar=` line is required, otherwise the new value is added to the old one.

## Key features

### CLI usage

```bash
tmv [options] <selector> <folder> [<selector> <folder> ...]
tmv [options] --env [file]
tmv -t [file]
```

```bash
tmv --video-files Videos
tmv "*.mp3" Music
tmv --video-files Videos --music-files Music "*.docx" Word_documents
tmv -n --images-files Pictures      # dry run
```

Always quote globs (`"*.mp3"`), otherwise the shell expands them before `tmv` sees them.

### Flags

| Flag | Description |
|---|---|
| `-n`, `--dry-run` | print what would be moved, change nothing |
| `--min-age N` | skip files modified in the last N minutes (default `1`) |
| `-t`, `--test [file]` | validate an env file (default `~/.config/tmv/tmv.env`) |
| `--env [file]` | sort `TARGET_DIR` using an env file |
| `-h`, `--help` | show help |

### Selectors

A selector is either a preset or a glob (case-insensitive, no `/` allowed).

| Preset | Extensions |
|---|---|
| `--video-files` | mp4 mkv avi mov wmv flv webm m4v mpg mpeg |
| `--music-files` | mp3 flac wav ogg m4a aac opus wma |
| `--images-files` | jpg jpeg png gif bmp webp svg tiff heic |
| `--docs-files` | pdf doc docx odt txt rtf xls xlsx ods ppt pptx odp csv |
| `--archives-files` | zip tar gz bz2 xz 7z rar |

In env files the leading `--` is optional and so is `-files` (`video`, `--video-files` and `video-files` all work).

### Env file and rules

```bash
TARGET_DIR="$HOME/Downloads"

TARGET_FILES="--video-files"
DIR_NAME="Videos"

TARGET_FILES="*.iso"
DIR_NAME="ISO"
```

`tmv -t` checks three rules:

1. The first significant line is `TARGET_DIR`.
2. Every `TARGET_FILES` is directly followed by a `DIR_NAME` (strict pair).
3. The file ends with a `DIR_NAME`.

Additionally: `TARGET_DIR` must exist and be writable, presets must be known, and `DIR_NAME` must be a plain name (no `/`, not `.` or `..`). Blank lines and `#` comments are ignored. Only a leading `~` or `$HOME` is expanded in values.

The env file is **parsed, never sourced**, so it cannot execute code and repeated keys do not overwrite each other. Currently one `TARGET_DIR` per file is supported.

### Safety behaviour

- **Never overwrites:** name collisions get a numeric suffix (`film.mp4`, `film_1.mp4`, `film_2.mp4`).
- **Not recursive:** only files directly inside the target directory are touched; folders and symlinks are left alone.
- **Downloads are safe:** files modified within the last minute and temporary files (`.part`, `.crdownload`, `.tmp`, `.download`, `.partial`) are skipped.
- **Hidden files** are ignored unless a glob explicitly starts with `.`.
- **First rule wins** if a file matches several rules.
- **All-or-nothing validation:** CLI pairs and env files are fully validated before the first file is moved.
- **No overlapping runs:** a lock (`flock`) prevents two instances from running at once.
- **Missed runs are caught up** (`Persistent=true`) when the machine was off.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | invalid env file, or at least one move failed |
| `2` | invalid command-line usage |

## License

Released under the [MIT License](LICENSE).
