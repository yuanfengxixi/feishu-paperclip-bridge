#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

fake_bin="$tmp_root/bin"
missing_home="$tmp_root/missing-home"
valid_home="$tmp_root/valid-home"
mkdir -p "$fake_bin" "$missing_home/.local/bin" "$valid_home/.local/bin"

cat > "$fake_bin/tmux" <<'TMUX_STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_ARGS_LOG"
printf '%s\n' "${PAPERCLIP_AGENT_JWT_SECRET-<unset>}" >> "$TMUX_ENV_LOG"
case "$1" in
  has-session) exit 1 ;;
  new-session|ls) exit 0 ;;
  *) exit 0 ;;
esac
TMUX_STUB
chmod +x "$fake_bin/tmux"

export TMUX_ARGS_LOG="$tmp_root/tmux-args.log"
export TMUX_ENV_LOG="$tmp_root/tmux-env.log"

if HOME="$missing_home" PATH="$fake_bin:$PATH" bash "$repo_root/wsl/start-all.sh" >"$tmp_root/missing.out" 2>&1; then
  printf 'Expected start-all.sh to reject a missing JWT env file.\n' >&2
  exit 1
fi
if [ -e "$TMUX_ARGS_LOG" ]; then
  printf 'start-all.sh started tmux before validating the JWT env file.\n' >&2
  exit 1
fi

secret='TEST_ONLY_JWT_SECRET_MUST_NOT_ENTER_PROCESS_ARGS'
printf "export PAPERCLIP_AGENT_JWT_SECRET='%s'\n" "$secret" > "$valid_home/.paperclip.env"
chmod 600 "$valid_home/.paperclip.env"
: > "$TMUX_ARGS_LOG"
: > "$TMUX_ENV_LOG"

if ! HOME="$valid_home" \
  PATH="$fake_bin:$PATH" \
  PAPERCLIP_AGENT_JWT_SECRET="$secret" \
  bash "$repo_root/wsl/start-all.sh" >"$tmp_root/start.out" 2>&1; then
  cat "$tmp_root/start.out" >&2
  exit 1
fi

if grep -Fq "$secret" "$TMUX_ARGS_LOG"; then
  printf 'JWT secret leaked into a tmux command argument.\n' >&2
  exit 1
fi
if grep -Fq "$secret" "$TMUX_ENV_LOG"; then
  printf 'JWT secret leaked into the tmux client environment.\n' >&2
  exit 1
fi
grep -Fq '.paperclip.env' "$TMUX_ARGS_LOG"
grep -Fq 'PAPERCLIP_AGENT_JWT_SECRET' "$TMUX_ARGS_LOG"
grep -Fq 'set-environment -gu PAPERCLIP_AGENT_JWT_SECRET' "$TMUX_ARGS_LOG"

printf '✓ rejects a missing JWT env file before starting tmux\n'
printf '✓ keeps JWT values out of tmux arguments and client environment\n'
