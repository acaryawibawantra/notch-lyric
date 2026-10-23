#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
{
    cat Tests/ShelfDropAdapters.swift
    cat boringNotch/components/Shelf/Services/TemporaryFileStorageService.swift
    awk '/^struct QuickShareProvider:/{printing=1} /^@MainActor/{printing=0} printing' boringNotch/components/Shelf/Services/QuickShareService.swift
    cat boringNotch/extensions/URL+SecurityScoped.swift
    cat boringNotch/extensions/NSItemProvider+LoadHelpers.swift
    cat boringNotch/components/Shelf/Services/ShelfDropService.swift
    awk '/^final class ShareDropView:/{printing=1} printing' boringNotch/components/Shelf/Views/FileShareView.swift
    cat Tests/ShareTargetChecks.swift
} | swift -
