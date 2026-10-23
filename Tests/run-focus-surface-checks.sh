#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
focus_surface_dir=$(mktemp -d /private/tmp/moris-focus-surface.XXXXXX)
trap 'rm -f "$focus_surface_dir/checks"; rmdir "$focus_surface_dir"' EXIT
{
    cat Tests/FocusSurfaceAdapters.swift
    awk '/^private struct MediaStopwatchCompanion:/{printing=1} /^\/\/\/ Full lyrics are opt-in/{printing=0} printing' boringNotch/components/Notch/NotchHomeView.swift
    cat Tests/FocusSurfaceChecks.swift
} | swiftc - -o "$focus_surface_dir/checks"
"$focus_surface_dir/checks"
