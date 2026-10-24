# tmv: design document

`tmv` ("timer mv") is a pure-Bash file sorter. It moves files from a directory
into named subfolders based on glob patterns or presets, either manually (CLI)
or automatically (systemd user timer).

## 1. Modes

### 1.1 CLI mode
Arguments come in pairs `<selector> <folder>`, consumed with `shift 2`.
Files are sorted in the current directory (`$PWD`).

```bash
tmv --video-files "Videos"
tmv "*.mp3" "Music"
tmv --video-files "Videos" --music-files "Music" "*.docx" "Word_documents"
```

### 1.2 Timer mode
A systemd **user** timer periodically runs `tmv --env <file>`, which sorts
`TARGET_DIR` according to the rules in the env file.

## 2. Repository layout

```
tmv/
├── install.sh          # installs tmv into PATH, systemd units, example env
├── bin/tmv             # entry point: argument parsing, dispatch
├── lib/
│   ├── presets.sh      # preset -> extensions map, selector -> globs
│   ├── sorter.sh       # core logic: tmv_move_matching
│   └── validate.sh     # env parser and `tmv -t`
├── systemd/
│   ├── tmv.service
│   └── tmv.timer
├── examples/tmv.env
├── tests/run.sh        # creates tmp dir with fake files, asserts results
├── DESIGN.md
└── README.md
```

One core function, `tmv_move_matching <dir> <selector> <dest_name>`, is used
by both CLI and timer mode: one logic, two entry points.

## 3. Env file format

```bash
TARGET_DIR="/home/user/Downloads"
TARGET_FILES="--video-files"
DIR_NAME="Videos"
TARGET_FILES="*.docx"
DIR_NAME="Word_documents"
```

The file is **parsed line by line, never `source`d**. Sourcing would overwrite
repeated variables so only the last pair would survive, and it would also
execute arbitrary code.

### Validation rules (`tmv -t`)
1. The first significant line is `TARGET_DIR`.
2. Every `TARGET_FILES` is immediately followed by a `DIR_NAME` (strict pair).
3. The last significant line is a `DIR_NAME`.

Additional checks:
- `TARGET_DIR` exists and is writable.
- At least one pair exists.
- Presets are known.
- `DIR_NAME` is a plain name: no `/`, not `.` or `..`.
- A second `TARGET_DIR` is rejected in v1 with a clear error.

If validation fails, the service does not run (`ExecStartPre=tmv -t`, non-zero
exit stops the unit) and the error lands in the journal.

"Significant" lines exclude blank lines and `#` comments.

## 4. Decisions

| Topic | Decision |
|---|---|
| Selector | **Glob** + presets (`--video-files`, `video`, `"*.mp3"`). No regex. |
| Name collision | Numeric suffix: `film.mp4` -> `film_1.mp4` -> `film_2.mp4`. Never overwrite. |
| Interval | Edit `tmv.timer` manually in v1. v2: `TMV_INTERVAL="15min"` in env + `tmv --apply-interval` generates a drop-in `~/.config/systemd/user/tmv.timer.d/interval.conf` and runs `daemon-reload` (systemd timers cannot read env variables directly). |
| TARGET_DIR | One per env file (v1). |
| Multiple TARGET_DIR (v2) | A new `TARGET_DIR` opens a new block; rules 2 and 3 apply per block. The parser will track a "current block" so v2 only lifts the restriction. |
| systemd scope | **User** unit (`~/.config/systemd/user/`), so it runs as the user and `$HOME` is correct. |

## 5. Edge cases and solutions

| # | Problem | Solution |
|---|---------|----------|
| 1 | Blank lines and comments in env | Parser skips them; rules 1 and 3 apply to significant lines |
| 2 | Spaces in filenames | Always quote; `find -print0` + `read -d ''` |
| 3 | Same name exists in destination | `mv -n` plus numeric suffix |
| 4 | Sorting descends into already-created folders | `find -maxdepth 1 -type f`; never recursive; dirs and symlinks untouched |
| 5 | `DIR_NAME` with `/` or `..` | Rejected in validation and in `tmv_valid_dirname` |
| 6 | File still downloading | Skip files modified in the last N min (`-mmin +N`) and temp extensions (`.part`, `.crdownload`, ...) |
| 7 | File matches two rules | First rule wins (env order); the file is moved once |
| 8 | Case (`.MP4`) | `find -iname` |
| 9 | Shell expands the glob before tmv sees it | Document: quote globs. Detect odd argument count and warn |
| 10 | Odd number of CLI arguments | Error + usage before any move |
| 11 | Hidden files | Untouched unless the glob explicitly starts with `.` |
| 12 | Permissions on TARGET_DIR | User unit; writability checked in validation |
| 13 | Timer missed (machine was off) | `Persistent=true` |
| 14 | Two runs at once | `flock` on a lock file |
| 15 | Cross-partition move (copy+delete) | Check exit code per file, continue with the next |
| 16 | Dry run | `--dry-run` / `-n` prints what would happen |
| 17 | Unknown preset | Rejected with a clear message |
| 18 | Logging | stdout/stderr -> `journalctl --user -u tmv` |

## 6. Conventions

- Messages go to **stderr**; **stdout** of `tmv_move_matching` is reserved for
  the number of moved files.
- Exit code 0 = ok, non-zero = at least one error.
- Env: `TMV_DRY_RUN` (0/1), `TMV_MIN_AGE` (minutes, default 1).

## 7. Status / Next steps

- [x] Design + edge cases
- [x] `lib/presets.sh`
- [x] `lib/sorter.sh`
- [ ] `bin/tmv`: CLI pair parsing, `shift 2`, `--dry-run`, odd-argument check
- [x] `lib/validate.sh`: env parser, `tmv -t`
- [ ] `tmv --env <file>` using the same `tmv_move_matching`
- [ ] `systemd/` units + `install.sh`
- [ ] `tests/run.sh`
- [ ] README
- [ ] v2: multiple TARGET_DIR blocks, `--apply-interval`
