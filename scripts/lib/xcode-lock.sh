XCODE_LOCK_DIR="$HOME/Library/Caches/com.joaoalves.mocha/xcodebuild.lock"

xcode_lock_release() {
  if [[ "$(cat "$XCODE_LOCK_DIR/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "$XCODE_LOCK_DIR"
  fi
}

xcode_lock_acquire() {
  local holder
  mkdir -p "$(dirname "$XCODE_LOCK_DIR")"
  until mkdir "$XCODE_LOCK_DIR" 2>/dev/null; do
    holder="$(cat "$XCODE_LOCK_DIR/pid" 2>/dev/null || true)"
    if [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; then
      if [[ "$(cat "$XCODE_LOCK_DIR/pid" 2>/dev/null || true)" == "$holder" ]]; then
        rm -rf "$XCODE_LOCK_DIR"
      fi
      continue
    fi
    [[ -d "$XCODE_LOCK_DIR" ]] || continue
    echo "xcodebuild em uso pelo processo ${holder:-?} ($XCODE_LOCK_DIR); nova tentativa em 5 s." >&2
    sleep 5
  done
  trap xcode_lock_release EXIT
  echo "$$" > "$XCODE_LOCK_DIR/pid"
}
