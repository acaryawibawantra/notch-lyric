#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import Foundation'
    awk '/^enum MorisTaskFeature/{printing=1} /^enum KeepAwakePower/{printing=0} printing' boringNotch/Productivity.swift
    awk '/^public enum NotchViews/{printing=1} /^enum SettingsEnum/{printing=0} printing' boringNotch/enums/generic.swift
    awk '/^struct TabModel:/{printing=1} /^struct TabSelectionView:/{printing=0} printing' boringNotch/components/Tabs/TabSelectionView.swift
    awk '/^struct TabSwipeAccumulator/{printing=1} /^\/\/\/ Local to/{printing=0} printing' boringNotch/extensions/PanGesture.swift
    cat Tests/TabSwipeChecks.swift
} | swift -
