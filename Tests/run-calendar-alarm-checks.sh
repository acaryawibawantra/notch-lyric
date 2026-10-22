#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import Foundation'
    awk '/^struct CalendarAgendaAlert:/{printing=1} printing && /^@MainActor/{exit} printing' boringNotch/managers/CalendarManager.swift
    cat Tests/CalendarAlarmChecks.swift
} | swift -
