#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
surface_test_dir=$(mktemp -d /private/tmp/moris-surface-test.XXXXXX)
trap 'rm -f "$surface_test_dir/checks"; rmdir "$surface_test_dir"' EXIT
{
    awk '/^class AudioSpectrum:/{exit} {print}' boringNotch/components/Music/MusicVisualizer.swift
    cat Tests/MediaSurfaceChecks.swift
} | swiftc - -o "$surface_test_dir/checks"
"$surface_test_dir/checks"
