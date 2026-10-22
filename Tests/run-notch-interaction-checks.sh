#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import Foundation'
    awk '/^struct NotchInteractionLocks/{printing=1} /^class BoringViewModel:/{printing=0} printing' boringNotch/models/BoringViewModel.swift
    cat Tests/NotchInteractionChecks.swift
} | swift -
