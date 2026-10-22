#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    awk '/^#Preview/{exit} {print}' boringNotch/components/Music/MusicVisualizer.swift
    cat Tests/SpectrumChecks.swift
} | swift -
