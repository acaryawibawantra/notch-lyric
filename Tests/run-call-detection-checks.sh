#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import Foundation'
    awk '/^enum CallDetectionRules/{printing=1} /^enum CallAccessibilityScanner/{exit} printing' BoringNotchXPCHelper/CallAccessibilityScanner.swift
    cat Tests/CallDetectionChecks.swift
} | swift -
