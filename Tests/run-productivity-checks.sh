#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    awk '/^struct KeepAwakeControls:/{exit} {print}' boringNotch/Productivity.swift
    cat Tests/ProductivityChecks.swift
} | swift -
