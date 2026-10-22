#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import AppKit' 'import SwiftUI' 'import Combine' '@MainActor'
    awk '/^final class PrompterModel:/{printing=1} /^\/\/ MARK: - Presentation/{printing=0} printing' boringNotch/Prompter.swift
    awk '/^private struct PrompterTextViewport:/{printing=1} printing' boringNotch/Prompter.swift
    cat Tests/PrompterViewportChecks.swift
} | swift -
