#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    printf '%s\n' 'import Foundation' 'import Combine' '@MainActor'
    awk '/^final class PrompterModel:/{printing=1} /^\/\/ MARK: - Presentation/{printing=0} printing' boringNotch/Prompter.swift
    cat Tests/PrompterChecks.swift
} | swift -
