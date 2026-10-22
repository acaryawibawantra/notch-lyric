#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import AppKit' 'import SwiftUI' 'import Combine' '@MainActor'
    awk '/^final class PrompterModel:/{printing=1} /^\/\/ MARK: - Presentation/{printing=0} printing' boringNotch/Prompter.swift
    printf '%s\n' '@MainActor'
    awk '/^final class PrompterPanelController:/{printing=1} /^\/\/\/ Binds presentation/{printing=0} printing' boringNotch/Prompter.swift
    cat Tests/PrompterDockChecks.swift
} | swift -
