#!/usr/bin/env bash
# install.sh - install tmv for the current user (no root needed)
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SHARE_DIR=$HOME/.local/share/tmv
BIN_DIR=$HOME/.local/bin
CONF_DIR=$HOME/.config/tmv
UNIT_DIR=$HOME/.config/systemd/user

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  (no options)   copy tmv to ~/.local/share/tmv, symlink ~/.local/bin/tmv,
                 install systemd units and an example env. Timer is NOT started.
  --enable       also validate the env and enable + start tmv.timer
  --link         development mode: symlink ~/.local/bin/tmv to this repo
  --uninstall    remove tmv and the units (keeps ~/.config/tmv)
  -h, --help     this help
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "install: missing dependency: $1" >&2; exit 1; }
}

do_uninstall() {
  systemctl --user disable --now tmv.timer 2>/dev/null || true
  rm -f "$UNIT_DIR/tmv.service" "$UNIT_DIR/tmv.timer"
  rm -f "$BIN_DIR/tmv"
  rm -rf "$SHARE_DIR"
  systemctl --user daemon-reload 2>/dev/null || true
  echo "install: removed. Config kept in $CONF_DIR"
}

link=0; enable=0; uninstall=0
for arg in "$@"; do
  case $arg in
    --enable)    enable=1 ;;
    --link)      link=1 ;;
    --uninstall) uninstall=1 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "install: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if ((uninstall)); then do_uninstall; exit 0; fi

for dep in bash find flock readlink systemctl; do need "$dep"; done

# sanity check: run from the repo root
for f in bin/tmv lib/presets.sh lib/sorter.sh lib/validate.sh \
         systemd/tmv.service systemd/tmv.timer examples/tmv.env; do
  [[ -f $SRC/$f ]] || { echo "install: missing $f in $SRC" >&2; exit 1; }
done

mkdir -p "$BIN_DIR" "$CONF_DIR" "$UNIT_DIR"

# --- program files ---
if ((link)); then
  chmod +x "$SRC/bin/tmv"
  ln -sfn "$SRC/bin/tmv" "$BIN_DIR/tmv"
  echo "install: linked $BIN_DIR/tmv -> $SRC/bin/tmv"
else
  rm -rf "$SHARE_DIR"
  mkdir -p "$SHARE_DIR"
  cp -r "$SRC/bin" "$SRC/lib" "$SHARE_DIR/"
  chmod +x "$SHARE_DIR/bin/tmv"
  # bin/tmv resolves lib/ via readlink -f, so a symlink works
  ln -sfn "$SHARE_DIR/bin/tmv" "$BIN_DIR/tmv"
  echo "install: copied program to $SHARE_DIR"
fi

# --- systemd units ---
install -m 644 "$SRC/systemd/tmv.service" "$SRC/systemd/tmv.timer" "$UNIT_DIR/"
systemctl --user daemon-reload
echo "install: units installed in $UNIT_DIR"

# --- example env (never overwrite the user's own) ---
if [[ -e $CONF_DIR/tmv.env ]]; then
  echo "install: $CONF_DIR/tmv.env already exists, left untouched"
else
  install -m 644 "$SRC/examples/tmv.env" "$CONF_DIR/tmv.env"
  echo "install: example env written to $CONF_DIR/tmv.env"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "install: WARNING: $BIN_DIR is not in PATH" >&2 ;;
esac

# --- optionally enable the timer ---
if ((enable)); then
  if "$BIN_DIR/tmv" -t "$CONF_DIR/tmv.env"; then
    systemctl --user enable --now tmv.timer
    echo "install: tmv.timer enabled"
  else
    echo "install: env is invalid, timer NOT enabled. Fix $CONF_DIR/tmv.env and run: systemctl --user enable --now tmv.timer" >&2
    exit 1
  fi
else
  cat <<EOF

Next steps:
  1. Edit $CONF_DIR/tmv.env
  2. tmv -t                                  # validate
  3. tmv -n --env                            # dry run
  4. systemctl --user enable --now tmv.timer
EOF
fi
