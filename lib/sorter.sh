#!/usr/bin/env bash
# sorter.sh - Single logic of moving,  CLI & timer mode

: "${TMV_DRY_RUN:=0}"
: "${TMV_MIN_AGE:=1}"   # skip files modified in last N minutes

# extensions of temp files (during download)
TMV_SKIP_EXT=(part crdownload tmp download partial)

tmv_is_temp() {
  local ext=${1##*.} e
  ext=${ext,,}
  for e in "${TMV_SKIP_EXT[@]}"; do
    [[ $ext == "$e" ]] && return 0
  done
  return 1
}

# Free names: a.mp4 -> a_1.mp4 -> a_2.mp4
tmv_unique_path() {
  local dest_dir=$1 name=$2 base ext candidate i=1
  if [[ $name == *.* && $name != .* ]]; then
    base=${name%.*}; ext=.${name##*.}
  else
    base=$name; ext=
  fi
  candidate=$dest_dir/$name
  while [[ -e $candidate || -L $candidate ]]; do
    candidate=$dest_dir/${base}_${i}${ext}
    ((i++))
  done
  printf '%s\n' "$candidate"
}

# permission is only dir name with no path
tmv_valid_dirname() {
  local d=$1
  [[ -n $d && $d != */* && $d != . && $d != .. ]]
}

# tmv_move_matching <dir> <selector> <dest_name>
# returns 0 everything is alright (and if thers no files), 1 for error.
# On stdout writes number of moved files.
tmv_move_matching() {
  local dir=$1 selector=$2 dest_name=$3
  local globs_out g f name target moved=0 rc=0
  local -a globs find_args

  tmv_valid_dirname "$dest_name" || {
    echo "tmv: invlaid directory name: '$dest_name'" >&2; return 1; }
  [[ -d $dir && -w $dir ]] || {
    echo "tmv: '$dir' no such directory or its not writeable" >&2; return 1; }

  globs_out=$(tmv_resolve_selector "$selector") || return 1
  mapfile -t globs <<<"$globs_out"

  local dest_dir=$dir/$dest_name

  for g in "${globs[@]}"; do
    find_args=(-maxdepth 1 -type f -iname "$g" -mmin "+$TMV_MIN_AGE")
    # dotfiles touches when there are excplicitly want them (npr. ".*rc")
    [[ $g == .* ]] || find_args+=(-not -name '.*')

    while IFS= read -r -d '' f; do
      name=${f##*/}
      tmv_is_temp "$name" && continue

      target=$(tmv_unique_path "$dest_dir" "$name")

      if ((TMV_DRY_RUN)); then
        echo "[dry-run] $f -> $target" >&2
        ((moved++))
        continue
      fi

      mkdir -p -- "$dest_dir" || { rc=1; continue; }
      if mv -n -- "$f" "$target"; then
        echo "tmv: $name -> $dest_name/${target##*/}" >&2
        ((moved++))
      else
        echo "tmv: Error while moving: '$f'" >&2
        rc=1
      fi
    done < <(find "$dir" "${find_args[@]}" -print0)
  done

  echo "$moved"
  return $rc
}
