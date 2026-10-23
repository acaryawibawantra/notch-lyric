#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
cat_test_dir=$(mktemp -d /private/tmp/moris-cat-test.XXXXXX)
trap 'rm -f "$cat_test_dir/checks"; rmdir "$cat_test_dir"' EXIT
# Render the production shapes offscreen with isolated values, never user defaults.
{
    awk '/^struct CatEyeAppearanceSettings:/{skip=1} /^\/\/\/ The empty center/{skip=0} /^struct MinimalFaceFeatures:/{exit} !skip {print}' boringNotch/components/AnimatedFace.swift |
        sed -e '/^import Defaults$/d' \
            -e 's/Defaults.Serializable/Codable/g' \
            -e 's/@Default(.catEyePalette) private var palette/private var palette: CatEyePalette = .sky/' \
            -e 's/@Default(.catEyeStyle) private var savedStyle/private var savedStyle: CatEyeStyle = .round/'
    cat Tests/CatEyesChecks.swift
} | swiftc - -o "$cat_test_dir/checks"
"$cat_test_dir/checks" "$@"
