#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Test production codecs with tiny generated fixtures and isolated temporary storage.
{
    cat boringNotch/components/Shelf/Services/ImageProcessingService.swift
    cat Tests/ShelfImageChecks.swift
} | swift -
