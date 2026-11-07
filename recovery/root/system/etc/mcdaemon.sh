#!/system/bin/sh
# Launch the stock Trustonic TEE daemon.
#
# init starts this service as soon as TWRP sets fstab.additional.  The daemon
# binary, its libraries and the KeyMint/Gatekeeper HALs all live on /vendor,
# which TWRP mounts during its own fstab pass, so wait for the binary instead of
# /mnt/vendor/persist (init mounts that earlier).  While /vendor was missing
# every attempt failed with "inaccessible or not found" (rc 127) and, while the
# TEE stayed down, other clients kept retrying open session.
LOG=/tmp/mcd.log
# Debug switches on persist, so the daemon's environment can be varied across
# reboots instead of needing a rebuild per attempt:
#   .mcd_skip  one substring per line; matching "-r" entries are dropped
#   .mcd_args  when non-empty, used as the complete argument list
#   .mcd_wait  when present, the daemon is not started until it is removed
# The daemon loads the secure drivers given with -r before it serves the
# TAFileServer store, and a driver that never answers blocks the single MCP
# channel, leaving the FileServer stuck at "Mounting partition 1...".
PERSIST=/mnt/vendor/persist
SKIP=""
for f in "$PERSIST/.mcd_skip" "$PERSIST/mcRegistry/.mcd_skip"; do
  [ -f "$f" ] && SKIP="$SKIP $(tr '\n' ' ' < "$f")"
done
ARGS_OVERRIDE=""
[ -s "$PERSIST/.mcd_args" ] && ARGS_OVERRIDE=$(tr '\n' ' ' < "$PERSIST/.mcd_args")
echo "== mcdaemon.sh $(date) id=$(id | tr ' ' '_') skip=[$SKIP] override=[$ARGS_OVERRIDE]" >> "$LOG"

i=0
while [ $i -lt 120 ]; do
  [ -x /vendor/bin/mcDriverDaemon ] && break
  i=$((i + 1))
  sleep 1
done
echo "== /vendor/bin/mcDriverDaemon visible after ${i}s" >> "$LOG"

if [ -n "$ARGS_OVERRIDE" ]; then
  filtered="$ARGS_OVERRIDE"
  echo "== using .mcd_args override" >> "$LOG"
else
  filtered=""
  while [ $# -gt 0 ]; do
    a="$1"
    shift
    if [ "$a" = "-r" ] && [ $# -gt 0 ]; then
      path="$1"
      shift
      drop=0
      for s in $SKIP; do
        case "$path" in *"$s"*) drop=1 ;; esac
      done
      if [ "$drop" = "0" ]; then
        filtered="$filtered -r $path"
      else
        echo "== skipping $path" >> "$LOG"
      fi
    else
      filtered="$filtered $a"
    fi
  done
fi

# .mcd_wait keeps the daemon from starting until it is removed, so a boot can be
# inspected (and the argument list changed) before the TEE is touched.
w=0
while [ -f "$PERSIST/.mcd_wait" ] && [ $w -lt 900 ]; do
  w=$((w + 1))
  sleep 1
done
[ $w -gt 0 ] && echo "== waited ${w}s for .mcd_wait" >> "$LOG"

attempt=0
while true; do
  attempt=$((attempt + 1))
  echo "== attempt $attempt $(date)" >> "$LOG"
  # shellcheck disable=SC2086
  /vendor/bin/mcDriverDaemon $filtered >> "$LOG" 2>&1
  rc=$?
  echo "== daemon exited rc=$rc (attempt $attempt) $(date)" >> "$LOG"
  sleep 5
done
