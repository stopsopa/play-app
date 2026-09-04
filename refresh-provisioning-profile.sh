PROFILE_DIR="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
BUNDLE_ID="stopsopa.sanemp3"

while true; do
    if pgrep -x "Xcode" >/dev/null; then
        cat <<EEE

${0} error: Xcode is currently running. Quit Xcode before continuing.

EEE

        printf "\n      Press Enter to continue\n"
        read
    else
        break
    fi
done

cat <<EEE

✅ Xcode is no longer running.

🔍 Looking for provisioning profiles for:
   BUNDLE_ID=>${BUNDLE_ID}<
   PROFILE_DIR=>${PROFILE_DIR}<

EEE

if [[ ! -d "${PROFILE_DIR}" ]]; then
    echo "${0} error: Provisioning profile directory does not exist"
    echo "${0} error: PROFILE_DIR=>${PROFILE_DIR}<"
    exit 1
fi

FOUND=0
REMOVED=0

while IFS= read -r -d '' PROFILE; do
    FOUND=1

    APPLICATION_IDENTIFIER=$(security cms -D -i "${PROFILE}" 2>/dev/null \
        | plutil -extract Entitlements.application-identifier raw - 2>/dev/null)

    if [[ "${APPLICATION_IDENTIFIER}" == *"${BUNDLE_ID}" ]]; then
        cat <<EEE

🗑️ Removing provisioning profile:

   ${PROFILE}

   Application Identifier:
   ${APPLICATION_IDENTIFIER}

EEE

        if ! rm "${PROFILE}"; then
            echo "${0} error: Could not remove provisioning profile"
            echo "${0} error: PROFILE=>${PROFILE}<"
            exit 1
        fi

        ((REMOVED++))
    fi
done < <(
    find "${PROFILE_DIR}" \
        -type f \
        -name "*.mobileprovision" \
        -print0
)

if [[ ${FOUND} -eq 0 ]]; then
    echo "${0} error: No provisioning profiles found"
    echo "${0} error: PROFILE_DIR=>${PROFILE_DIR}<"
    exit 1
fi

cat <<EEE

✅ Done.

Removed:
   ${REMOVED} provisioning profile(s)

Xcode can now request a fresh provisioning profile.

Start Xcode and build/run ${BUNDLE_ID} on your iPhone.

EEE