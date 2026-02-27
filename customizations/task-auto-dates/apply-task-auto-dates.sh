#!/usr/bin/env bash

set -euo pipefail

BASE_URL="http://localhost:8080"
USERNAME="Administrator"
PASSWORD=""
NAME_PREFIX=""
CLIENT_SCRIPT_NAME=""
SERVER_SCRIPT_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url)
            BASE_URL="$2"
            shift 2
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --name-prefix)
            NAME_PREFIX="$2"
            shift 2
            ;;
        --client-script-name)
            CLIENT_SCRIPT_NAME="$2"
            shift 2
            ;;
        --server-script-name)
            SERVER_SCRIPT_NAME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--base-url URL] [--username USER] [--password PASS] [--name-prefix PREFIX] [--client-script-name NAME] [--server-script-name NAME]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

BASE_URL="${BASE_URL%/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_SCRIPT_PATH="$SCRIPT_DIR/client_script.task_auto_dates.js"
SERVER_SCRIPT_PATH="$SCRIPT_DIR/server_script.task_auto_dates.py"

if [[ ! -f "$CLIENT_SCRIPT_PATH" ]]; then
    echo "File not found: $CLIENT_SCRIPT_PATH" >&2
    exit 1
fi

if [[ ! -f "$SERVER_SCRIPT_PATH" ]]; then
    echo "File not found: $SERVER_SCRIPT_PATH" >&2
    exit 1
fi

if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
else
    echo "python3/python is required to build JSON payloads." >&2
    exit 1
fi

url_encode() {
    "$PYTHON_BIN" - "$1" <<'PY'
import sys
from urllib.parse import quote

print(quote(sys.argv[1], safe=""))
PY
}

if [[ -z "$CLIENT_SCRIPT_NAME" ]]; then
    if [[ -z "$NAME_PREFIX" ]]; then
        CLIENT_SCRIPT_NAME="Task Auto Dates Client"
    else
        CLIENT_SCRIPT_NAME="${NAME_PREFIX} Task Auto Dates Client"
    fi
fi

if [[ -z "$SERVER_SCRIPT_NAME" ]]; then
    if [[ -z "$NAME_PREFIX" ]]; then
        SERVER_SCRIPT_NAME="Task Auto Dates Server"
    else
        SERVER_SCRIPT_NAME="${NAME_PREFIX} Task Auto Dates Server"
    fi
fi

CLIENT_SCRIPT_NAME_ENCODED="$(url_encode "$CLIENT_SCRIPT_NAME")"
SERVER_SCRIPT_NAME_ENCODED="$(url_encode "$SERVER_SCRIPT_NAME")"

if [[ -z "$PASSWORD" ]]; then
    read -rsp "ERPNext password for $USERNAME: " PASSWORD
    echo
fi

COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

login() {
    curl -sS -f \
        -c "$COOKIE_JAR" \
        -X POST "$BASE_URL/api/method/login" \
        --data-urlencode "usr=$USERNAME" \
        --data-urlencode "pwd=$PASSWORD" \
        >/dev/null
}

build_payload() {
    local script_path="$1"
    local script_kind="$2"
    local document_name="${3:-}"

    "$PYTHON_BIN" - "$script_path" "$script_kind" "$document_name" <<'PY'
import json
import pathlib
import sys

script_path = pathlib.Path(sys.argv[1])
script_kind = sys.argv[2]
document_name = sys.argv[3]
script = script_path.read_text(encoding="utf-8")

if script_kind == "client":
    data = {
        "dt": "Task",
        "view": "Form",
        "enabled": 1,
        "script": script,
    }
elif script_kind == "server":
    data = {
        "script_type": "DocType Event",
        "reference_doctype": "Task",
        "doctype_event": "Before Save",
        "disabled": 0,
        "script": script,
    }
else:
    raise SystemExit("Unknown script kind")

if document_name:
    data["name"] = document_name

print(json.dumps(data, ensure_ascii=False))
PY
}

upsert_resource() {
    local doctype="$1"
    local doctype_encoded="$2"
    local name="$3"
    local name_encoded="$4"
    local update_payload="$5"
    local create_payload="$6"

    local status_code
    status_code="$(curl -sS -o /dev/null -w "%{http_code}" \
        -b "$COOKIE_JAR" \
        "$BASE_URL/api/resource/$doctype_encoded/$name_encoded")"

    if [[ "$status_code" == "200" ]]; then
        curl -sS -f \
            -b "$COOKIE_JAR" \
            -H "Content-Type: application/json" \
            -X PUT "$BASE_URL/api/resource/$doctype_encoded/$name_encoded" \
            --data "$update_payload" \
            >/dev/null
        echo "[updated] $doctype -> $name"
        return
    fi

    if [[ "$status_code" == "404" ]]; then
        curl -sS -f \
            -b "$COOKIE_JAR" \
            -H "Content-Type: application/json" \
            -X POST "$BASE_URL/api/resource/$doctype_encoded" \
            --data "$create_payload" \
            >/dev/null
        echo "[created] $doctype -> $name"
        return
    fi

    echo "Failed to check resource '$doctype/$name' (HTTP $status_code)." >&2
    exit 1
}

print_check() {
    local response_json="$1"
    local mode="$2"

    "$PYTHON_BIN" - "$response_json" "$mode" <<'PY'
import json
import sys

response = json.loads(sys.argv[1])
mode = sys.argv[2]
data = response["data"]

if mode == "client":
    print(
        "Client Script check: "
        f"name={data.get('name')}, dt={data.get('dt')}, enabled={data.get('enabled')}"
    )
elif mode == "server":
    print(
        "Server Script check: "
        f"name={data.get('name')}, doctype={data.get('reference_doctype')}, "
        f"event={data.get('doctype_event')}, disabled={data.get('disabled')}"
    )
else:
    raise SystemExit("Unknown mode")
PY
}

login
echo "Logged in to ERPNext: $BASE_URL"

client_update_payload="$(build_payload "$CLIENT_SCRIPT_PATH" "client")"
client_create_payload="$(build_payload "$CLIENT_SCRIPT_PATH" "client" "$CLIENT_SCRIPT_NAME")"
server_update_payload="$(build_payload "$SERVER_SCRIPT_PATH" "server")"
server_create_payload="$(build_payload "$SERVER_SCRIPT_PATH" "server" "$SERVER_SCRIPT_NAME")"

upsert_resource \
    "Client Script" \
    "Client%20Script" \
    "$CLIENT_SCRIPT_NAME" \
    "$CLIENT_SCRIPT_NAME_ENCODED" \
    "$client_update_payload" \
    "$client_create_payload"

upsert_resource \
    "Server Script" \
    "Server%20Script" \
    "$SERVER_SCRIPT_NAME" \
    "$SERVER_SCRIPT_NAME_ENCODED" \
    "$server_update_payload" \
    "$server_create_payload"

client_response="$(
    curl -sS -f \
        -b "$COOKIE_JAR" \
        "$BASE_URL/api/resource/Client%20Script/$CLIENT_SCRIPT_NAME_ENCODED"
)"
server_response="$(
    curl -sS -f \
        -b "$COOKIE_JAR" \
        "$BASE_URL/api/resource/Server%20Script/$SERVER_SCRIPT_NAME_ENCODED"
)"

print_check "$client_response" "client"
print_check "$server_response" "server"

echo "Done."
echo "If you get 'Server Scripts are disabled', enable them with:"
echo "docker compose -f pwd.yml exec backend bench --site frontend set-config server_script_enabled true"
echo "docker compose -f pwd.yml exec backend bench set-config -g server_script_enabled 1"
