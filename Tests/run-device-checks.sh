#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import AppKit' 'import Combine' 'import IOBluetooth'
    awk '/^struct DeviceConnectionNotice:/{printing=1} /^\/\/\/ A view model/{printing=0} printing' boringNotch/models/BatteryStatusViewModel.swift
    cat Tests/DeviceConnectionChecks.swift
} | swift -
