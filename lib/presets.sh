#!/usr/bin/env bash
# presets.sh - preset name -> extension list, and evolving selectors into globe 

declare -A TMV_PRESETS=(
  [video]="mp4 mkv avi mov wmv flv webm m4v mpg mpeg"
  [music]="mp3 flac wav ogg m4a aac opus wma"
  [images]="jpg jpeg png gif bmp webp svg tiff heic"
  [docs]="pdf doc docx odt txt rtf xls xlsx ods ppt pptx odp csv"
  [archives]="zip tar gz bz2 xz 7z rar"
)

# normalizes "--video-files" / "video-files" / "video" -> "video"
tmv_preset_name() {
  local n=${1#--}
  n=${n%-files}
  printf '%s\n' "$n"
}

tmv_is_preset() {
  local n; n=$(tmv_preset_name "$1")
  [[ -n ${TMV_PRESETS[$n]+x} ]]
}

# Writes globes, one each line. returns 1 if its invalid globe.
tmv_resolve_selector() {
  local sel=$1 ext n

  if tmv_is_preset "$sel"; then
    n=$(tmv_preset_name "$sel")
    for ext in ${TMV_PRESETS[$n]}; do
      printf '*.%s\n' "$ext"
    done
    return 0
  fi

  # Begins with "--" but unkwown preset -> error
  if [[ $sel == --* ]]; then
    echo "tmv: Inavlid preset: $sel" >&2
    return 1
  fi

  # No paths in globes
  if [[ $sel == */* ]]; then
    echo "tmv: selector can't contain:' '/': $sel" >&2
    return 1
  fi

  printf '%s\n' "$sel"
}
