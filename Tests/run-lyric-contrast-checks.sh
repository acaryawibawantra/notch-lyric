#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import AppKit' 'import Combine' 'import ScreenCaptureKit'
    awk '/^enum LyricContrastRules/{printing=1} /^struct LyricContrastPreferences:/{printing=0} printing' boringNotch/LyricContrast.swift
    cat Tests/LyricContrastChecks.swift
} | swift -
