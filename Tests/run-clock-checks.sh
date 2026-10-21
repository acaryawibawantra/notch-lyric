#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Exercise the actual models without launching the app or using its preferences.
{
    awk '/^struct FocusTask:/{printing=1} /^struct FocusTaskList:/{printing=0} printing' boringNotch/EverydayTools.swift
    awk '/^enum FocusPhase:/{printing=1} /^private struct ToolButtonAppearance:/{printing=0} printing' boringNotch/ContentView.swift
    cat Tests/FocusClockChecks.swift
} | swift -
