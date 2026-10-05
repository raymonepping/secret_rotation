#!/bin/sh
# scripts/network.sh — create the shared network if it does not exist.
set -eu
podman network exists srot-internal || podman network create srot-internal >/dev/null
