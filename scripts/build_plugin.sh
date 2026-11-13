#!/bin/bash
# Generic build script for Checkmk MKP packages
# Usage: ./build_plugin.sh [options]
#
# Options:
#   --plugin-name NAME  Name of the plugin directory (required)
#   --title TITLE       Title of the plugin (required)
#   --description DESC  Description of the plugin (required)
#   --version VERSION   Version of the plugin (required)
#   --author NAME       Set author name (default: $USER)
#   --git-url URL       Set download URL (default: auto-detect from git)
#   --usable-until VER  Checkmk version from which the package is disabled (default: no limit)
#   --strip-comments    Remove comments from Python files
#   --ci                CI mode: enables --strip-comments, disables colors

set -e  # Exit on error

# Default values
PLUGIN_NAME=""
PLUGIN_TITLE=""
PLUGIN_DESCRIPTION=""
PLUGIN_VERSION=""
AUTHOR="${USER}"
GIT_URL=""
USABLE_UNTIL=""
STRIP_COMMENTS=false
CI_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --plugin-name)
            PLUGIN_NAME="$2"
            shift 2
            ;;
        --title)
            PLUGIN_TITLE="$2"
            shift 2
            ;;
        --description)
            PLUGIN_DESCRIPTION="$2"
            shift 2
            ;;
        --version)
            PLUGIN_VERSION="$2"
            shift 2
            ;;
        --author)
            AUTHOR="$2"
            shift 2
            ;;
        --git-url)
            GIT_URL="$2"
            shift 2
            ;;
        --usable-until)
            USABLE_UNTIL="$2"
            shift 2
            ;;
        --strip-comments)
            STRIP_COMMENTS=true
            shift
            ;;
        --ci)
            CI_MODE=true
            STRIP_COMMENTS=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$PLUGIN_NAME" ] || [ -z "$PLUGIN_TITLE" ] || [ -z "$PLUGIN_DESCRIPTION" ] || [ -z "$PLUGIN_VERSION" ]; then
    echo "Error: Missing required arguments."
    echo "Usage: $0 --plugin-name NAME --title TITLE --description DESC --version VERSION [options]"
    exit 1
fi

PLUGIN_DIR="${PLUGIN_NAME}"

# Colors for output (disabled in CI mode)
if [ "$CI_MODE" = true ]; then
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'

    # Append ~dev suffix for local builds (unless already present)
    if [[ "$PLUGIN_VERSION" != *~dev* ]]; then
        PLUGIN_VERSION="${PLUGIN_VERSION}~dev"
    fi
fi

echo -e "${GREEN}=== Building MKP Package ===${NC}"
echo -e "Plugin Name:    ${YELLOW}${PLUGIN_NAME}${NC}"
echo -e "Title:          ${YELLOW}${PLUGIN_TITLE}${NC}"
echo -e "Version:        ${YELLOW}${PLUGIN_VERSION}${NC}"
echo -e "Strip Comments: ${YELLOW}${STRIP_COMMENTS}${NC}"
echo ""

# Check if plugin directory exists
if [ ! -d "${PLUGIN_DIR}" ]; then
    echo -e "${RED}ERROR: ${PLUGIN_DIR} directory not found!${NC}"
    echo "Please run this script from the repository root directory."
    exit 1
fi

# Clean up old build directory
echo -e "${GREEN}[1/7]${NC} Cleaning up old build directory..."
rm -rf mkp_build
mkdir -p mkp_build/plugin_content

# Copy plugin files
echo -e "${GREEN}[2/7]${NC} Copying plugin files..."
cp -R "${PLUGIN_DIR}" mkp_build/plugin_content/
find mkp_build/plugin_content -type d -name __pycache__ -prune -exec rm -rf {} +

# Checkmk 2.4 does not load these from cmk_addons/plugins/<family>/, so they get
# their own MKP parts:
#   <plugin>/bakery/*  -> part "lib"    (~/local/lib/python3/cmk/base/cee/plugins/bakery/)
#   <plugin>/agents/*  -> part "agents" (~/local/share/check_mk/agents/)
CONTENT_DIR="mkp_build/plugin_content/${PLUGIN_DIR}"
if [ -d "${CONTENT_DIR}/bakery" ]; then
    mkdir -p mkp_build/lib_content/python3/cmk/base/cee/plugins/bakery
    mv "${CONTENT_DIR}/bakery/"* mkp_build/lib_content/python3/cmk/base/cee/plugins/bakery/
    rm -rf "${CONTENT_DIR}/bakery"
    echo "      bakery/ -> MKP part 'lib'"
fi
if [ -d "${CONTENT_DIR}/agents" ]; then
    mkdir -p mkp_build/agents_content
    mv "${CONTENT_DIR}/agents/"* mkp_build/agents_content/
    rm -rf "${CONTENT_DIR}/agents"
    echo "      agents/ -> MKP part 'agents'"
fi

# Strip comments (optional)
if [ "$STRIP_COMMENTS" = true ]; then
    echo -e "${GREEN}[3/7]${NC} Stripping comments from Python files..."
    STRIP_DIRS=(mkp_build/plugin_content)
    if [ -d mkp_build/lib_content ]; then
        STRIP_DIRS+=(mkp_build/lib_content)
    fi
    # Tokenizer based, so '#' lines inside strings are kept
    find "${STRIP_DIRS[@]}" -type f -name "*.py" -exec python3 "$(dirname "$0")/strip_comments.py" {} +
    echo "      Comments removed."
else
    echo -e "${GREEN}[3/7]${NC} Skipping comment removal (use --strip-comments to enable)."
fi

# Generate file list
echo -e "${GREEN}[4/7]${NC} Generating file list..."
# file_list <dir> <path>: quoted, comma separated file paths relative to <dir>
file_list() {
    (cd "$1" && find "$2" -type f | sed 's|^\./||;s/^/"/;s/$/"/' | paste -sd,)
}
PLUGIN_FILES=$(file_list mkp_build/plugin_content "${PLUGIN_DIR}/")
FILES_DICT="\"cmk_addons_plugins\": [ ${PLUGIN_FILES} ]"
PART_TARS="cmk_addons_plugins.tar"
if [ -d mkp_build/lib_content ]; then
    FILES_DICT="${FILES_DICT}, \"lib\": [ $(file_list mkp_build/lib_content .) ]"
    PART_TARS="${PART_TARS} lib.tar"
fi
if [ -d mkp_build/agents_content ]; then
    FILES_DICT="${FILES_DICT}, \"agents\": [ $(file_list mkp_build/agents_content .) ]"
    PART_TARS="${PART_TARS} agents.tar"
fi

# Get git commit hash (if available)
if git rev-parse --git-dir > /dev/null 2>&1; then
    COMMIT_SHORT_SHA=$(git rev-parse --short HEAD)
    # Use provided GIT_URL or auto-detect
    if [ -z "$GIT_URL" ]; then
        GIT_URL=$(git config --get remote.origin.url || echo "local")
    fi
else
    COMMIT_SHORT_SHA="local"
    if [ -z "$GIT_URL" ]; then
        GIT_URL="local"
    fi
fi

# Set version.packaged text based on CI mode
if [ "$CI_MODE" = true ]; then
    VERSION_PACKAGED="Github Actions at ref ${COMMIT_SHORT_SHA}"
else
    VERSION_PACKAGED="Built locally at ref ${COMMIT_SHORT_SHA}"
fi

# py_str <text>: <text> as a Python string literal (quotes, newlines etc. escaped)
py_str() {
    python3 -I -c 'import sys; print(repr(sys.argv[1]), end="")' "$1"
}
# json_str <text>: <text> as a JSON string (quotes, newlines etc. escaped)
json_str() {
    python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1]), end="")' "$1"
}

# Empty --usable-until means no upper limit
if [ -n "$USABLE_UNTIL" ]; then
    USABLE_UNTIL_PY=$(py_str "$USABLE_UNTIL")
    USABLE_UNTIL_JSON=$(json_str "$USABLE_UNTIL")
else
    USABLE_UNTIL_PY="None"
    USABLE_UNTIL_JSON="null"
fi

# Create info file (Python-style)
echo -e "${GREEN}[5/7]${NC} Creating info and info.json files..."
cat <<EOF > mkp_build/info
{
  'author': $(py_str "${AUTHOR}"),
  'description': $(py_str "${PLUGIN_DESCRIPTION}"),
  'download_url': $(py_str "${GIT_URL}"),
  'files': { ${FILES_DICT} },
  'name': $(py_str "${PLUGIN_NAME}"),
  'title': $(py_str "${PLUGIN_TITLE}"),
  'version': $(py_str "${PLUGIN_VERSION}"),
  'version.min_required': '2.4.0',
  'version.packaged': $(py_str "${VERSION_PACKAGED}"),
  'version.usable_until': ${USABLE_UNTIL_PY}
}
EOF

# Create info.json file (JSON-style)
cat <<EOF > mkp_build/info.json
{
  "author": $(json_str "${AUTHOR}"),
  "description": $(json_str "${PLUGIN_DESCRIPTION}"),
  "download_url": $(json_str "${GIT_URL}"),
  "files": { ${FILES_DICT} },
  "name": $(json_str "${PLUGIN_NAME}"),
  "title": $(json_str "${PLUGIN_TITLE}"),
  "version": $(json_str "${PLUGIN_VERSION}"),
  "version.min_required": "2.4.0",
  "version.packaged": $(json_str "${VERSION_PACKAGED}"),
  "version.usable_until": ${USABLE_UNTIL_JSON}
}
EOF

# Create internal tar
echo -e "${GREEN}[6/7]${NC} Creating internal tar archive..."
tar -cf mkp_build/cmk_addons_plugins.tar -C mkp_build/plugin_content "${PLUGIN_DIR}"
if [ -d mkp_build/lib_content ]; then
    (cd mkp_build/lib_content && tar -cf ../lib.tar -- *)
fi
if [ -d mkp_build/agents_content ]; then
    (cd mkp_build/agents_content && tar -cf ../agents.tar -- *)
fi

# Create final MKP package
MKP_FILENAME="${PLUGIN_NAME}-${PLUGIN_VERSION}.mkp"
echo -e "${GREEN}[7/7]${NC} Creating final MKP package..."
# shellcheck disable=SC2086 # PART_TARS is a space separated list of fixed names
tar -czf "$MKP_FILENAME" -C mkp_build/ info info.json ${PART_TARS}

# Get file size
FILE_SIZE=$(du -h "$MKP_FILENAME" | cut -f1)

echo ""
echo -e "${GREEN}=== Build Complete! ===${NC}"
echo -e "Package: ${YELLOW}${MKP_FILENAME}${NC}"
echo -e "Size:    ${YELLOW}${FILE_SIZE}${NC}"
echo ""

# Clean up build directory
rm -rf mkp_build
echo -e "${GREEN}Build directory cleaned.${NC}"
