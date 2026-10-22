#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    awk '/^enum MediaCompanion:/{printing=1} /^struct NotchHomeView:/{printing=0} printing' boringNotch/components/Notch/NotchHomeView.swift
    cat Tests/MediaCompanionChecks.swift
} | swift -
