#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Test the production metadata, filters, and selection with memory-only adapters.
{
    cat Tests/ShelfCheckAdapters.swift
    cat boringNotch/components/Shelf/Models/ShelfItem.swift
    cat boringNotch/components/Shelf/ViewModels/ShelfSelectionModel.swift
    awk '/^enum ShelfFilter:/{printing=1} /^struct ShelfView:/{printing=0} printing' boringNotch/components/Shelf/Views/ShelfView.swift
    cat Tests/ShelfChecks.swift
} | swift -
