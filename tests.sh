#!/bin/bash

#
# Builds the PlayLogic library and runs its unit tests.
#
# Usage:
#   /bin/bash tests.sh
#       run all tests
#
#   /bin/bash tests.sh --filter testExampleTimeline
#       run one test (any extra arguments are passed straight to "swift test")
#
#   /bin/bash tests.sh --filter PlayLogicTests
#       run one test class
#
# Can be called from any directory, paths are resolved relative to this script.
# Exit code: 0 when all tests pass, non-zero otherwise.
#

set -e
set -o pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

PACKAGE_DIR="${_DIR}/PlayLogic"

if [ ! -f "${PACKAGE_DIR}/Package.swift" ]; then
    echo "${0} error: ${PACKAGE_DIR}/Package.swift not found" >&2
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "${0} error: 'swift' not found, install Xcode or the Xcode command line tools" >&2
    exit 1
fi

cd "${PACKAGE_DIR}"

# "swift test" builds the library and the tests first, then runs them
swift test "${@}"

echo ""
echo "${0}: all PlayLogic tests passed"
