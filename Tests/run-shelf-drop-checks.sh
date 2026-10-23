#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    cat Tests/ShelfDropAdapters.swift
    cat boringNotch/components/Shelf/Services/TemporaryFileStorageService.swift
    cat boringNotch/extensions/URL+SecurityScoped.swift
    cat boringNotch/extensions/NSItemProvider+LoadHelpers.swift
    cat boringNotch/components/Shelf/Services/ShelfDropService.swift
    cat Tests/ShelfDropChecks.swift
} | swift -
