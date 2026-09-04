APP_NAME="sanemp3.app"
DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"

echo "🔍 Looking for ${APP_NAME}/embedded.mobileprovision..."
echo

PROFILE=$(find "${DERIVED_DATA}" \
  -path "*/Build/Products/Debug-iphoneos/${APP_NAME}/embedded.mobileprovision" \
  -type f \
  -print -quit)

if [[ -z "${PROFILE}" ]]; then
    cat <<EEE
${0} error: Could not find embedded.mobileprovision
Searched in DERIVED_DATA=>${DERIVED_DATA}<
APP_NAME=>${APP_NAME}<
EEE
    exit 1
fi

cat <<EEE
✅ Found provisioning profile:
  ${PROFILE}

EEE

echo "🔐 Reading expiration date..."

if ! EXPIRATION=$(security cms -D -i "${PROFILE}" 2>/dev/null \
    | plutil -extract ExpirationDate raw - 2>/dev/null); then

    cat <<EEE
${0} error: Could not read provisioning profile
PROFILE=>${PROFILE}<
EEE
    exit 1
fi

EXPIRATION_TIMESTAMP=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${EXPIRATION}" "+%s")
NOW_TIMESTAMP=$(date "+%s")

DIFF=$((EXPIRATION_TIMESTAMP - NOW_TIMESTAMP))
ABS_DIFF=${DIFF#-}

DAYS=$((ABS_DIFF / 86400))
HOURS=$(((ABS_DIFF % 86400) / 3600))

if [[ ${DIFF} -lt 0 ]]; then
    cat <<EEE

❌ EXPIRED

📅 Expired:
   ${EXPIRATION}

⏱️  Time since expiration:
   -${DAYS} days ${HOURS} hours

   WARNING: see also provision.gif to see where to inspect the provisioning file
   WARNING: see also provision.gif to see where to inspect the provisioning file
   WARNING: see also provision.gif to see where to inspect the provisioning file
   WARNING: see also provision.gif to see where to inspect the provisioning file

EEE
else
    cat <<EEE

✅ ACTIVE
📅 Expires:
   ${EXPIRATION}

⏳ Time remaining:

   ${DAYS} days ${HOURS} hours

   WARNING: see also provision.gif to see where to inspect the provisioning file
   WARNING: see also provision.gif to see where to inspect the provisioning file
   WARNING: see also provision.gif to see where to inspect the provisioning file
   WARNING: see also provision.gif to see where to inspect the provisioning file
   
EEE
fi