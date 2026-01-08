#!/bin/bash

######## ######## ######## ######## DATA COLLECTION ######## ######## ######## ########
# SERVERS="afx@10.9.8.254 afx@10.9.10.141"
SERVERS="nguyenvn@192.168.50.143 nguyenvn@192.168.50.142"
LOG_PATH=/var/log/syslog
TMP_DIR=/tmp/data
KEYWORD_ERROR=ErRoR
KEYWORD_FIRST=2026-01-08
COUNT=1

for SERVER in $SERVERS; do
    # CHECK SSH STATUS
    if ssh "$SERVER" true 2>/dev/null; then
        echo "SSH $SERVER successfully"
        
        # USE grep COMMAND
        ssh $SERVER "grep '$KEYWORD_FIRST' $LOG_PATH" > $TMP_DIR/syslog-$COUNT.txt
        # ssh $SERVER "grep '$KEYWORD_FIRST' $LOG_PATH | gzip -c" > $TMP_DIR/syslog-$COUNT.gz

        # USE awk COMMAND
        # ssh $SERVER "awk '\$0 >= \"$KEYWORD_FIRST\"' $LOG_PATH" > $TMP_DIR/syslog-$COUNT.txt
        # ssh $SERVER "awk '\$0 >= \"$KEYWORD_FIRST\"' $LOG_PATH | gzip -c" > $TMP_DIR/syslog-$COUNT.gzip

        # ssh $SERVER "awk '\$0 >= \"$KEYWORD_FIRST\"' $LOG_PATH | grep -i $KEYWORD_ERROR" > $TMP_DIR/syslog-$COUNT.txt
        # ssh $SERVER "awk '\$0 >= \"$KEYWORD_FIRST\"' $LOG_PATH | grep -i $KEYWORD_ERROR | gzip -c" > $TMP_DIR/syslog-$COUNT.txt.gz
    else
        echo "SSH $SERVER failed"
    fi

    COUNT=$((COUNT + 1))
done

######## ######## ######## ######## AUTHEN ######## ######## ######## ########
SERVICE_ACCOUNT_JSON=/opt/gdrive/service-account.json
AUTH_SCOPE=https://www.googleapis.com/auth/drive.file # HOW TO GET THIS INFO

CLIENT_EMAIL=$(grep '"client_email"' "$SERVICE_ACCOUNT_JSON" \
    | sed -E 's/.*"client_email": *"([^"]+)".*/\1/')

PRIVATE_KEY=$(sed -n '/"private_key"/,/END PRIVATE KEY/p' "$SERVICE_ACCOUNT_JSON" \
    | sed 's/\\n/\n/g' \
    | sed 's/.*"private_key": "//;s/".*//')

# BUILD TIMESTAMPS
NOW=$(date +%s)
EXP=$((NOW + 3600))

# CREATE JWT HEADER AND PAYLOAD
HEADER='{"alg":"RS256","typ":"JWT"}'

PAYLOAD='{
    "iss":"'"$CLIENT_EMAIL"'",
    "scope":"'"$OAUTH_SCOPE"'",
    "aud":"https://oauth2.googleapis.com/token",
    "iat":'"$NOW"',
    "exp":'"$EXP"'
}'

# BASE64URL FUNCTION (JWT REQUIREMENT)
base64url() {
    openssl base64 -e -A | tr '+/' '-_' | tr -d '='
}

# ENCODE HEADER + PAYLOAD
HEADER_B64=$(echo -n "$HEADER" | base64url)
PAYLOAD_B64=$(echo -n "$PAYLOAD" | base64url)
SIGN_INPUT="${HEADER_B64}.${PAYLOAD_B64}"

# SIGN JWT WITH PRIVATE KEY
TMP_KEY=$(mktemp)
echo "$PRIVATE_KEY" > "$TMP_KEY"

SIGNATURE=$(echo -n "$SIGN_INPUT" \
    | openssl dgst -sha256 -sign "$TMP_KEY" \
    | base64url)

rm -f "$TMP_KEY"
JWT="${SIGN_INPUT}.${SIGNATURE}"

# EXCHANGE JWT FOR ACCESS TOKEN | FROM AnhTT
TOKEN_RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$JWT")

# FROM ChatGPT
TOKEN_RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
  -d "assertion=$JWT")

# EXTRACT THE ACCESS TOKEN
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" \
    | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

# NOT YET VERIFY
if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "❌ Failed to get access token"
    echo "$TOKEN_RESPONSE"
    exit 1
fi

######## ######## ######## ######## UPLOAD ######## ######## ######## ########
FOLDER_ID=0AJEIQBrRjSp7Uk9PVAO

curl -s -X POST \
    "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -F "metadata={name:'${FILE_DATE}-mypage2.log', parents:['$FOLDER_ID']};type=application/json" \
    -F "file=@$FINAL_LOG"