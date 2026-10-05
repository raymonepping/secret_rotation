#!/usr/bin/env bash
# scripts/clock-sync.sh — bring the Podman VM's clock back to the host's.
# macOS pauses the VM when the Mac sleeps; chrony then needs several samples
# before it steps the clock. Leases, tokens and certificates all
# fail in confusing ways while the VM is behind. This forces the samples and
# the step now. No-op on Linux.
set -euo pipefail
[ "$(uname -s)" = Darwin ] || { echo "clock-sync: not a Podman VM host; nothing to do"; exit 0; }
skew() { echo $(( $(date +%s) - $(podman machine ssh date +%s | tr -d '\r' | tail -1) )); }
before=$(skew)
if [ "${before#-}" -le 2 ]; then echo "clock-sync: VM clock is within ${before#-}s of the host"; exit 0; fi
podman machine ssh 'sudo chronyc burst 4/4 >/dev/null; sleep 12; sudo chronyc makestep >/dev/null' 
sleep 2
after=$(skew)
# After a long pause chrony can mark every source "too variable" (^~ / ^?):
# it sees the offset but has no selected source, so makestep does nothing.
# Set the clock from the host instead; chrony keeps it from there.
if [ "${after#-}" -gt 5 ]; then
  podman machine ssh "sudo date -u -s @$(date +%s)" >/dev/null
  podman machine ssh 'sudo chronyc reselect >/dev/null 2>&1 || true'
  sleep 1
  after=$(skew)
fi
echo "clock-sync: VM was ${before}s behind the host, now ${after}s"
[ "${after#-}" -le 5 ]
