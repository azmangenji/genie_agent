#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                           filebridge.sh                                ║
# ║              Linux ↔ Windows Two-Way File Transfer Tool                ║
# ╠══════════════════════════════════════════════════════════════════════════╣
# ║  PURPOSE                                                                ║
# ║    Transfer files between Linux and Windows in both directions.         ║
# ║    Run this script on Linux. Run filebridge_server.py on Windows.       ║
# ║                                                                         ║
# ╠══════════════════════════════════════════════════════════════════════════╣
# ║  SETUP                                                                  ║
# ║                                                                         ║
# ║  1) On Windows — start the server:                                      ║
# ║       python filebridge_server.py                                       ║
# ║       python filebridge_server.py 9000              (custom port)       ║
# ║       python filebridge_server.py 9000 C:\myshared  (custom dir)       ║
# ║                                                                         ║
# ║  2) On Linux — make this script executable (one-time):                  ║
# ║       chmod +x filebridge.sh                                            ║
# ║                                                                         ║
# ╠══════════════════════════════════════════════════════════════════════════╣
# ║  USAGE                                                                  ║
# ║                                                                         ║
# ║  List files on Windows:                                                 ║
# ║    ./filebridge.sh list                                                 ║
# ║                                                                         ║
# ║  Download  (Windows → Linux):                                           ║
# ║    ./filebridge.sh download <filename>                                  ║
# ║    ./filebridge.sh download <filename> <dest_dir>                       ║
# ║                                                                         ║
# ║    Examples:                                                            ║
# ║      ./filebridge.sh download "report.pptx"                            ║
# ║      ./filebridge.sh download "data.csv" /proj/mydir                   ║
# ║      ./filebridge.sh download "Genie AI Agent.pptx" ~/Desktop          ║
# ║                                                                         ║
# ║  Upload  (Linux → Windows):                                             ║
# ║    ./filebridge.sh upload <filepath>                                    ║
# ║    ./filebridge.sh upload <filepath> <remote_filename>                  ║
# ║                                                                         ║
# ║    Examples:                                                            ║
# ║      ./filebridge.sh upload /tmp/results.pptx                          ║
# ║      ./filebridge.sh upload /tmp/results.pptx renamed.pptx             ║
# ║      ./filebridge.sh upload ~/analysis/report.csv                      ║
# ║                                                                         ║
# ╠══════════════════════════════════════════════════════════════════════════╣
# ║  CONFIGURATION  (edit defaults below or export before running)          ║
# ║                                                                         ║
# ║    WINDOWS_IP    IP of Windows machine       default: 172.31.24.95     ║
# ║    WINDOWS_PORT  Port of filebridge_server   default: 8888             ║
# ║    DOWNLOAD_DIR  Where downloads are saved   default: ~/Downloads       ║
# ║                                                                         ║
# ║  Override on the fly:                                                   ║
# ║    WINDOWS_IP=10.0.0.5 ./filebridge.sh download file.pptx              ║
# ║    WINDOWS_PORT=9000   ./filebridge.sh list                             ║
# ║                                                                         ║
# ╠══════════════════════════════════════════════════════════════════════════╣
# ║  REQUIREMENTS                                                           ║
# ║    • curl  (available on most Linux systems)                            ║
# ║    • python3 (for URL encoding/decoding)                                ║
# ║    • filebridge_server.py running on Windows                            ║
# ║      (for upload — download works with plain python -m http.server)     ║
# ╚══════════════════════════════════════════════════════════════════════════╝

# ── Configuration (edit these defaults) ───────────────────────────────────
WINDOWS_IP="${WINDOWS_IP:-172.31.24.95}"
WINDOWS_PORT="${WINDOWS_PORT:-8888}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-${HOME}/Downloads}"
BASE_URL="http://${WINDOWS_IP}:${WINDOWS_PORT}"

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
error()   { echo -e "${RED}[ERR]${RESET}   $*"; exit 1; }

# ── Check server is reachable ──────────────────────────────────────────────
check_server() {
    if ! curl -s --connect-timeout 5 "${BASE_URL}/" -o /dev/null; then
        error "Cannot reach ${BASE_URL}\n       Is filebridge_server.py running on Windows?"
    fi
}

# ── DOWNLOAD: Windows → Linux ──────────────────────────────────────────────
cmd_download() {
    local filename="$1"
    local dest_dir="${2:-$DOWNLOAD_DIR}"
    [[ -z "$filename" ]] && error "Usage: ./filebridge.sh download <filename> [dest_dir]"

    check_server
    mkdir -p "$dest_dir"

    local encoded dest url
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${filename}'))")
    dest="${dest_dir}/${filename}"
    url="${BASE_URL}/${encoded}"

    info "Downloading : ${filename}"
    info "From        : ${url}"
    info "Saving to   : ${dest}"
    echo ""

    if curl -f --progress-bar -o "${dest}" "${url}"; then
        echo ""
        success "Saved: ${dest}  ($(du -sh "${dest}" | cut -f1))"
    else
        echo ""
        error "Download failed — '${filename}' not found on server."
    fi
}

# ── UPLOAD: Linux → Windows ────────────────────────────────────────────────
cmd_upload() {
    local filepath="$1"
    local remote_name="${2:-$(basename "$filepath")}"
    [[ -z "$filepath" ]]   && error "Usage: ./filebridge.sh upload <filepath> [remote_filename]"
    [[ ! -f "$filepath" ]] && error "File not found: ${filepath}"

    check_server

    local size url response
    size=$(du -sh "$filepath" | cut -f1)
    url="${BASE_URL}/upload"

    info "Uploading   : ${filepath}  (${size})"
    info "To          : ${WINDOWS_IP}:${WINDOWS_PORT}"
    info "Remote name : ${remote_name}"
    echo ""

    response=$(curl -f --progress-bar \
        -X POST \
        -H "X-Filename: ${remote_name}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${filepath}" \
        "${url}" 2>&1)

    local rc=$?
    echo ""
    if [[ $rc -eq 0 ]]; then
        success "Upload complete  →  ${remote_name}  on  ${WINDOWS_IP}"
    else
        error "Upload failed (exit ${rc})\n       ${response}\n       Make sure filebridge_server.py is running (not python -m http.server)"
    fi
}

# ── LIST: show files on Windows ────────────────────────────────────────────
cmd_list() {
    check_server
    info "Files on Windows  (${BASE_URL}/):"
    echo ""
    curl -s "${BASE_URL}/" \
        | grep -oP 'href="[^"]*"' \
        | sed 's/href="//;s/"//' \
        | grep -v '^[/]$' \
        | while read -r f; do
            decoded=$(python3 -c "import urllib.parse; print(urllib.parse.unquote('${f}'))")
            echo -e "    ${CYAN}${decoded}${RESET}"
          done
    echo ""
}

# ── HELP ───────────────────────────────────────────────────────────────────
cmd_help() {
    echo -e "${BOLD}filebridge.sh${RESET}  —  Linux ↔ Windows file transfer"
    echo ""
    echo -e "  ${BOLD}list${RESET}                              List files on Windows"
    echo -e "  ${BOLD}download${RESET} <file> [dest_dir]       Windows → Linux"
    echo -e "  ${BOLD}upload${RESET}   <file> [remote_name]    Linux → Windows"
    echo ""
    echo -e "  ${BOLD}Config${RESET}:"
    echo -e "    WINDOWS_IP=${WINDOWS_IP}   WINDOWS_PORT=${WINDOWS_PORT}"
    echo -e "    DOWNLOAD_DIR=${DOWNLOAD_DIR}"
    echo ""
    echo -e "  ${BOLD}Examples${RESET}:"
    echo -e "    ./filebridge.sh list"
    echo -e "    ./filebridge.sh download \"report.pptx\""
    echo -e "    ./filebridge.sh download \"data.csv\" /proj/mydir"
    echo -e "    ./filebridge.sh upload /tmp/results.pptx"
    echo -e "    ./filebridge.sh upload /tmp/results.pptx renamed.pptx"
    echo -e "    WINDOWS_IP=10.0.0.5 ./filebridge.sh download file.csv"
}

# ── Main ───────────────────────────────────────────────────────────────────
case "${1:-}" in
    download|dl|get)   cmd_download "${@:2}" ;;
    upload|ul|put)     cmd_upload   "${@:2}" ;;
    list|ls)           cmd_list              ;;
    help|--help|-h|"") cmd_help             ;;
    *) echo -e "${RED}Unknown command: $1${RESET}\n"; cmd_help; exit 1 ;;
esac
