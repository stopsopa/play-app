
# Script to check installed Xcode versions, identify the active version,
# and verify whether the required version (26.5) is installed.

TARGET_VERSION="${TARGET_VERSION:-26.5}"

# ANSI color codes
# CLR_RESET="$(printf '\033[0m')"
# CLR_RED="$(printf '\033[1;31m')"
# CLR_GREEN="$(printf '\033[1;32m')"
# CLR_YELLOW="$(printf '\033[1;33m')"
# CLR_BLUE="$(printf '\033[1;34m')"
# CLR_BOLD="$(printf '\033[1m')"
# CLR_CYAN="$(printf '\033[1;36m')"

GRAY=$'\033[38;5;244m'
BLACK=$'\033[30m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
WHITE=$'\033[37m'
BOLD=$'\033[1m'
REVERSE=$'\033[7m'
RESET=$'\033[0m'

cat <<EEE
${BOLD}Checking installed Xcode versions...${RESET}
Required version: ${YELLOW}${TARGET_VERSION}${RESET}

EEE

# Determine current active Xcode developer path
CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
CURRENT_APP_PATH=""
if [[ -n "${CURRENT_DEV_DIR}" ]]; then
    CURRENT_APP_PATH="$(echo "${CURRENT_DEV_DIR}" | sed -E 's|(/Xcode[^/]*\.app).*|\1|')"
fi

# Find all Xcode applications in standard directories
FOUND_PATHS=()

while IFS= read -r app_path; do
    if [[ -n "${app_path}" && -d "${app_path}" ]]; then
        FOUND_PATHS+=("${app_path}")
    fi
done < <(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null || true)

# If Spotlight/mdfind returned nothing, fall back to scanning standard Application directories
if [[ "${#FOUND_PATHS[@]}" -eq 0 ]]; then
    for cand in /Applications/Xcode*.app /Users/*/Applications/Xcode*.app; do
        if [[ -d "${cand}" ]]; then
            FOUND_PATHS+=("${cand}")
        fi
    done
fi

FOUND_TARGET=0
INSTALLED_COUNT=0

echo "${BOLD}Installed Xcode installations:${RESET}"

for app_path in "${FOUND_PATHS[@]}"; do
    plist_path="${app_path}/Contents/Info.plist"
    if [[ -f "${plist_path}" ]]; then
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
        
        # Read marketing version and build number
        version=$(defaults read "${plist_path}" CFBundleShortVersionString 2>/dev/null || echo "Unknown")
        build=$(defaults read "${plist_path}" DTXcodeBuild 2>/dev/null || defaults read "${plist_path}" CFBundleVersion 2>/dev/null || echo "Unknown")
        
        # Check active status
        ACTIVE_MARK=""
        if [[ "${app_path}" == "${CURRENT_APP_PATH}" ]]; then
            ACTIVE_MARK="${BLUE}(ACTIVE via xcode-select)${RESET}"
        fi
        
        # Check if matches target version
        if [[ "${version}" == "${TARGET_VERSION}" ]]; then
            FOUND_TARGET=1
            echo "  ${GREEN}✔ [MATCH] Xcode ${version} (Build ${build})${RESET} - ${app_path} ${ACTIVE_MARK}"
        else
            echo "  - Xcode ${version} (Build ${build}) - ${app_path} ${ACTIVE_MARK}"
        fi
    fi
done

if [[ "${INSTALLED_COUNT}" -eq 0 ]]; then
    echo "  ${RED}No Xcode installations found on this system.${RESET}"
fi

echo ""

if [[ "${FOUND_TARGET}" -eq 1 ]]; then
    echo "${GREEN}${BOLD}SUCCESS:${RESET} Required Xcode version ${YELLOW}${TARGET_VERSION}${RESET} is installed."
    exit 0
else
    echo "${0} error: Required Xcode version TARGET_VERSION=>${TARGET_VERSION}< is NOT INSTALLED."
    cat <<EEE

${YELLOW}${BOLD}  WARNING:${RESET}
${YELLOW}    for releasing to iphone 8 with iOS 16.7.16${RESET}
${YELLOW}    we need Xcode version ${TARGET_VERSION}${RESET}
${CYAN}
    go to https://developer.apple.com/download/all/${RESET}
    search "Xcode ${TARGET_VERSION}"${RESET}
    download file: "Xcode ${TARGET_VERSION} Apple silicon.xip"
    unzip that file - normaly just by executing it
    sudo ditto ~/Downloads/Xcode.app /Applications/Xcode-26.5.app
${RESET}

    List all installed version of xcode:
      ${BOLD}ls -d /Applications/Xcode*.app 2>/dev/null${RESET}

EEE
    exit 1
fi
