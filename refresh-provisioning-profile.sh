APP_NAME="sanemp3.app"
BUNDLE_ID="stopsopa.sanemp3"
DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"

PROFILE_DIRS=(
    "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
    "${HOME}/Library/MobileDevice/Provisioning Profiles"
)

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
   APP_NAME=>${APP_NAME}<

EEE

REMOVED_CACHE=0

for DIR in "${PROFILE_DIRS[@]}"; do
    if [[ -d "${DIR}" ]]; then
        echo "📂 Searching cache dir: ${DIR}"

        while IFS= read -r -d '' PROFILE; do
            APPLICATION_IDENTIFIER=$(security cms -D -i "${PROFILE}" 2>/dev/null \
                | plutil -extract Entitlements.application-identifier raw - 2>/dev/null)

            if [[ "${APPLICATION_IDENTIFIER}" == *"${BUNDLE_ID}" ]]; then
                cat <<EEE

🗑️ Removing cached provisioning profile:
   ${PROFILE}
   Application Identifier: ${APPLICATION_IDENTIFIER}

EEE
                if ! rm "${PROFILE}"; then
                    echo "${0} error: Could not remove provisioning profile"
                    echo "${0} error: PROFILE=>${PROFILE}<"
                    exit 1
                fi

                ((REMOVED_CACHE++))
            fi
        done < <(find "${DIR}" -type f -name "*.mobileprovision" -print0 2>/dev/null)
    fi
done

REMOVED_DERIVED=0

echo "📂 Searching DerivedData: ${DERIVED_DATA}"

while IFS= read -r -d '' DERIVED_PROFILE; do
    cat <<EEE

🗑️ Removing embedded provisioning profile:
   ${DERIVED_PROFILE}

EEE
    if ! rm "${DERIVED_PROFILE}"; then
        echo "${0} error: Could not remove embedded profile"
        echo "${0} error: DERIVED_PROFILE=>${DERIVED_PROFILE}<"
        exit 1
    fi

    ((REMOVED_DERIVED++))
done < <(find "${DERIVED_DATA}" -path "*/Build/Products/Debug-iphoneos/${APP_NAME}/embedded.mobileprovision" -type f -print0 2>/dev/null)

TOTAL_REMOVED=$((REMOVED_CACHE + REMOVED_DERIVED))

if [[ ${TOTAL_REMOVED} -eq 0 ]]; then
    cat <<EEE

⚠️  No provisioning profiles found to remove.
   - Checked cache directories in Provisioning Profiles
   - Checked DerivedData for ${APP_NAME}/embedded.mobileprovision

Start Xcode and build/run ${BUNDLE_ID} on your iPhone.

EEE
    exit 0
fi

cat <<EEE

✅ Done.

Removed:
   ${REMOVED_CACHE} cached provisioning profile(s)
   ${REMOVED_DERIVED} embedded profile(s) from DerivedData

Xcode can now request and embed a fresh provisioning profile.

Start Xcode and build/run ${BUNDLE_ID} on your iPhone.

EEE