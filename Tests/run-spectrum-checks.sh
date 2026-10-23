#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
spectrum_test_dir=$(mktemp -d /private/tmp/moris-spectrum-test.XXXXXX)
trap 'rm -f "$spectrum_test_dir/checks"; rmdir "$spectrum_test_dir"' EXIT
{
    awk '/^#Preview/{exit} {print}' boringNotch/components/Music/MusicVisualizer.swift
    cat Tests/SpectrumChecks.swift
} | swiftc - -o "$spectrum_test_dir/checks"
"$spectrum_test_dir/checks"
