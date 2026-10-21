#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    awk '/^struct FocusTask:/{printing=1} /^struct FocusTaskList:/{printing=0} printing' boringNotch/EverydayTools.swift
    awk '/^enum EverydayReminder:/{printing=1} /^struct EverydayToolsView:/{printing=0} printing' boringNotch/EverydayTools.swift
    awk '/^struct ClipboardEntry:/{printing=1} printing; printing && /^}/{exit}' boringNotch/EverydayTools.swift
    awk '/^final class ClipboardPanelSelection:/{print "@MainActor";printing=1} /^private final class ClipboardFloatingPanel:/{printing=0} printing' boringNotch/EverydayTools.swift
    cat Tests/EverydayToolChecks.swift
} | swift -
