#!/usr/bin/env bash
# validate.sh - env parser (never `source` the env file) and rule checks

TMV_ENV_DIR=
TMV_ENV_SEL=()
TMV_ENV_DEST=()

# Strip one pair of matching quotes, expand leading ~ or $HOME (no eval)
tmv_clean_value() {
  local v=$1
  if [[ $v =~ ^\"(.*)\"$ ]] || [[ $v =~ ^\'(.*)\'$ ]]; then
    v=${BASH_REMATCH[1]}
  fi
  case $v in
    "~"|"~/"*)       v=$HOME${v#\~} ;;
    '$HOME'|'$HOME/'*) v=$HOME${v#\$HOME} ;;
  esac
  printf '%s\n' "$v"
}

# tmv_parse_env <file>
# Fills TMV_ENV_DIR, TMV_ENV_SEL[], TMV_ENV_DEST[]. Prints all errors to stderr.
# Returns 0 if the env file follows the rules, 1 otherwise.
tmv_parse_env() {
  local file=$1 line key val prev= lineno=0 errors=0 pending=

  TMV_ENV_DIR=; TMV_ENV_SEL=(); TMV_ENV_DEST=()

  [[ -r $file ]] || { echo "tmv: cannot read env file: $file" >&2; return 1; }

  local err=; err() { echo "tmv: $file:$lineno: $*" >&2; errors=$((errors+1)); }

  while IFS= read -r line || [[ -n $line ]]; do
    lineno=$((lineno+1))
    # trim whitespace
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    [[ -z $line || $line == \#* ]] && continue

    if [[ $line =~ ^(TARGET_DIR|TARGET_FILES|DIR_NAME)=(.*)$ ]]; then
      key=${BASH_REMATCH[1]}
      val=$(tmv_clean_value "${BASH_REMATCH[2]}")
    else
      err "unknown or malformed line: $line"
      continue
    fi

    case $key in
	TARGET_DIR)
  	if [[ -n $TMV_ENV_DIR ]]; then
    	err "multiple TARGET_DIR blocks are not supported in v1"
  	else
    	[[ -z $prev ]] || err "rule 1: TARGET_DIR must be the first line"
    	TMV_ENV_DIR=$val
  	fi
  	;;
           TARGET_FILES)
        if [[ -z $prev ]]; then
          err "rule 1: first line must be TARGET_DIR"
        elif [[ $prev == TARGET_FILES ]]; then
          err "rule 2: TARGET_FILES must be followed by DIR_NAME"
        fi
        if [[ -z $val ]]; then
          err "TARGET_FILES is empty"
        else
          tmv_resolve_selector "$val" >/dev/null 2>&1 \
            || err "invalid selector or unknown preset: $val"
        fi
        pending=$val
        ;;
      DIR_NAME)
        if [[ $prev != TARGET_FILES ]]; then
          err "rule 2: DIR_NAME must directly follow a TARGET_FILES"
        else
          tmv_valid_dirname "$val" \
            || err "invalid DIR_NAME (no '/', not '.' or '..', not empty): '$val'"
          TMV_ENV_SEL+=("$pending")
          TMV_ENV_DEST+=("$val")
          pending=
        fi
        ;;
    esac
    prev=$key
  done < "$file"

  # end-of-file checks
  lineno=$(wc -l < "$file")
 case $prev in
  "")           err "env file has no content" ;;
  TARGET_FILES) err "rule 3: file must end with DIR_NAME" ;;
  *)            ((${#TMV_ENV_SEL[@]} > 0)) || err "no TARGET_FILES/DIR_NAME pair found" ;;
esac
  ((${#TMV_ENV_SEL[@]} > 0)) || [[ $prev == "" ]] || err "no TARGET_FILES/DIR_NAME pair found"

  if [[ -n $TMV_ENV_DIR ]]; then
    [[ -d $TMV_ENV_DIR && -w $TMV_ENV_DIR ]] \
      || err "TARGET_DIR does not exist or is not writable: $TMV_ENV_DIR"
  fi

  ((errors == 0))
}

# tmv -t [file]
tmv_test_env() {
  if tmv_parse_env "$1"; then
    echo "tmv: env OK ($1): ${#TMV_ENV_SEL[@]} rule(s) for $TMV_ENV_DIR" >&2
    return 0
  fi
  echo "tmv: env INVALID ($1)" >&2
  return 1
}
