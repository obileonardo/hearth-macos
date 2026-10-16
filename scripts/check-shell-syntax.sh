#!/bin/zsh
# zsh -n accepts one script; a glob passed directly checks only its first match.
set -uo pipefail
cd "$(dirname "$0")/.."
if (( $# == 0 )); then
  set -- scripts/*.sh
fi
result=0
for script in "$@"; do
  if [[ ! -f "$script" ]]; then
    print -u2 -- "Shell syntax input is not a file: $script"
    result=1
  elif ! zsh -n "$script"; then
    print -u2 -- "Shell syntax failed: $script"
    result=1
  fi
done
exit "$result"
