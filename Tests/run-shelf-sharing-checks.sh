#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    cat Tests/ShelfDropAdapters.swift
    cat boringNotch/components/Shelf/Services/TemporaryFileStorageService.swift
    cat boringNotch/extensions/URL+SecurityScoped.swift
    cat boringNotch/extensions/NSItemProvider+LoadHelpers.swift
    cat boringNotch/components/Shelf/Services/ShelfDropService.swift
    awk '/^@MainActor/{printing=1} /^class QuickShareService:/{printing=0} printing' boringNotch/components/Shelf/Services/QuickShareService.swift
    cat boringNotch/models/SharingStateManager.swift
    cat Tests/ShelfSharingChecks.swift
} | swift -
