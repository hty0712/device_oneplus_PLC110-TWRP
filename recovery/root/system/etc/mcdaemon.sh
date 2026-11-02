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
echo "== mcdaemon.sh $(date) id=$(id | tr ' ' '_')" >> "$LOG"

i=0
while [ $i -lt 120 ]; do
  [ -x /vendor/bin/mcDriverDaemon ] && break
  i=$((i + 1))
  sleep 1
done
echo "== /vendor/bin/mcDriverDaemon visible after ${i}s" >> "$LOG"

attempt=0
while true; do
  attempt=$((attempt + 1))
  echo "== attempt $attempt $(date)" >> "$LOG"
  /vendor/bin/mcDriverDaemon "$@" >> "$LOG" 2>&1
  rc=$?
  echo "== daemon exited rc=$rc (attempt $attempt) $(date)" >> "$LOG"
  sleep 5
done
