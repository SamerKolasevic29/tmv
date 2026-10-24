#!/usr/bin/env bash
# tests/run.sh - ručni test tmv-a u /tmp/t

TMV=~/Projects/githab/tmv/bin/tmv
T=/tmp/t

chmod +x "$TMV"

# svaki test kreće od čistog stanja
reset_dir() {
  rm -rf "$T"; mkdir -p "$T"; cd "$T" || exit 1
  touch a.mp4 b.MKV "my song.mp3" notes.docx photo.jpg c.part novi.mp4 .skriveni.mp4
  # sve osim "novi.mp4" (tek napravljen) i dotfajla pravimo starim 5 min
  touch -d '5 min ago' a.mp4 b.MKV "my song.mp3" notes.docx photo.jpg c.part .skriveni.mp4
}

section() { printf '\n===== %s =====\n' "$1"; }

# ---------------------------------------------------------------
section "1. dry-run (ne smije ništa premjestiti)"
reset_dir
"$TMV" -n --video-files Videos "*.mp3" Music
ls -A "$T"

# ---------------------------------------------------------------
section "2. pravo premještanje preko CLI parova"
reset_dir
"$TMV" --video-files Videos --music-files Music "*.docx" Word_documents
ls -R "$T"
# očekivano: Videos/{a.mp4,b.MKV}, Music/"my song.mp3", Word_documents/notes.docx
# ostaje: photo.jpg, c.part (temp), novi.mp4 (premlad), .skriveni.mp4 (dotfajl)

# ---------------------------------------------------------------
section "3. kolizija imena (sufiks _1, _2)"
reset_dir
mkdir Videos && touch -d '5 min ago' Videos/a.mp4 Videos/a_1.mp4
"$TMV" --video-files Videos
ls Videos
# očekivano: a.mp4, a_1.mp4, a_2.mp4 (novi), b.MKV

# ---------------------------------------------------------------
section "4. neparan broj argumenata (mora greška, exit 2)"
reset_dir
"$TMV" "*.mp3"
echo "exit code: $?"

# ---------------------------------------------------------------
section "5. nepoznat preset (mora greška)"
reset_dir
"$TMV" --nepoznato-files X
echo "exit code: $?"

# ---------------------------------------------------------------
section "6. opasan naziv foldera (mora greška)"
reset_dir
"$TMV" --video-files "../bijeg"
echo "exit code: $?"
ls /tmp | grep -c '^bijeg$'   # mora biti 0

# ---------------------------------------------------------------
section "7. env: ispravan fajl"
reset_dir
cat > /tmp/test_ok.env <<'EOF'
# komentar
TARGET_DIR="/tmp/t"

TARGET_FILES="--music-files"
DIR_NAME="Music"
TARGET_FILES="*.jpg"
DIR_NAME="Images"
EOF
"$TMV" -t /tmp/test_ok.env; echo "exit code: $?"
"$TMV" --env /tmp/test_ok.env
ls -R "$T"

# ---------------------------------------------------------------
section "8. env: pravilo 1 prekršeno (prvi red nije TARGET_DIR)"
cat > /tmp/test_bad1.env <<'EOF'
TARGET_FILES="--music-files"
DIR_NAME="Music"
TARGET_DIR="/tmp/t"
EOF
"$TMV" -t /tmp/test_bad1.env; echo "exit code: $?"

section "9. env: pravilo 2 prekršeno (dva TARGET_FILES zaredom)"
cat > /tmp/test_bad2.env <<'EOF'
TARGET_DIR="/tmp/t"
TARGET_FILES="--music-files"
TARGET_FILES="*.jpg"
DIR_NAME="Images"
EOF
"$TMV" -t /tmp/test_bad2.env; echo "exit code: $?"

section "10. env: pravilo 3 prekršeno (završava na TARGET_FILES)"
cat > /tmp/test_bad3.env <<'EOF'
TARGET_DIR="/tmp/t"
TARGET_FILES="--music-files"
DIR_NAME="Music"
TARGET_FILES="*.jpg"
EOF
"$TMV" -t /tmp/test_bad3.env; echo "exit code: $?"

section "11. env: DIR_NAME sa '..' (mora biti odbijen)"
cat > /tmp/test_bad4.env <<'EOF'
TARGET_DIR="/tmp/t"
TARGET_FILES="*.jpg"
DIR_NAME="../x"
EOF
"$TMV" -t /tmp/test_bad4.env; echo "exit code: $?"

section "12. env: --env sa neispravnim fajlom ne smije ništa pomjeriti"
reset_dir
"$TMV" --env /tmp/test_bad3.env; echo "exit code: $?"
ls -A "$T"

echo; echo "===== gotovo ====="
