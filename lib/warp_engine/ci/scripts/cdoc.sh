# shellcheck shell=sh
# Defines warp_cdoc, which writes the Doxygen docs of a release from C or C++
# sources. Set before it: NAME. A template calls it with the language (c or
# c++), the source folder and the file patterns, quoted:
#
#   warp_cdoc c src '*.c' '*.h'
#
# The comments are plain /* */ ones: an awk filter makes the first comment of
# a file its @file description, a comment above a declaration a /** */ one and
# one after it on the line a /**< */ one. A Doxyfile in the repository is read
# first; the README is the main page and the source browser is on. Doxygen and
# zip come from the image; where it has none, the template sets W_SETUP to the
# command that installs them, run only when there are sources. The site is
# zipped into <name>-<version>-docs.zip. Without sources there are no docs, and nothing
# fails.
warp_cdoc() {
  W_LANGUAGE=$1
  W_SOURCE=$2
  shift 2
  W_FOUND=""
  if [ -d "$W_SOURCE" ]; then
    for W_PATTERN in "$@"; do
      if [ -n "$(find "$W_SOURCE" -type f -name "$W_PATTERN" | head -n 1)" ]; then W_FOUND=yes; fi
    done
  fi
  if [ -z "$W_FOUND" ]; then
    echo "==> No sources under $W_SOURCE/: no docs"
    return 0
  fi
  if [ -n "$W_SETUP" ]; then
    eval "$W_SETUP"
  fi
  W_VERSION=$(cat .version)
  W_TITLE=$(sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json 2>/dev/null | head -n 1)
  [ -n "$W_TITLE" ] || W_TITLE=$NAME
  W_INPUT=$W_SOURCE
  [ -f README.md ] && W_INPUT="$W_SOURCE README.md"
  W_C=NO
  [ "$W_LANGUAGE" = c ] && W_C=YES
  W_FILTERS=""
  for W_PATTERN in "$@"; do
    W_FILTERS="$W_FILTERS \"$W_PATTERN=awk -f /tmp/warp-cdoc.awk\""
  done
  cat > /tmp/warp-cdoc.awk <<'AWK'
FNR == 1 { state = 0 }
state == 0 && /^[ \t]*$/ { print; next }
state == 0 && /^\/\*([^*!]|$)/ { sub(/^\/\*/, "/**"); state = 1 }
state == 0 { state = 2 }
state == 1 { if (sub(/\*\//, "@file */")) state = 2; print; next }
match($0, /^[ \t]*\/\*/) && substr($0, RLENGTH + 1, 1) ~ /^ ?$/ { $0 = substr($0, 1, RLENGTH) "*" substr($0, RLENGTH + 1) }
{ sub(/;[ \t]*\/\* /, "; /**< "); print }
AWK
  echo "==> Generating the docs of $W_TITLE $W_VERSION with Doxygen"
  rm -rf docs
  {
    [ -f Doxyfile ] && cat Doxyfile
    echo "PROJECT_NAME = \"$W_TITLE\""
    echo "PROJECT_NUMBER = \"$W_VERSION\""
    echo "INPUT = $W_INPUT"
    echo "USE_MDFILE_AS_MAINPAGE = README.md"
    echo "IMAGE_PATH = ."
    echo "FILE_PATTERNS = $*"
    echo "RECURSIVE = YES"
    echo "FILTER_PATTERNS =$W_FILTERS"
    echo "OPTIMIZE_OUTPUT_FOR_C = $W_C"
    echo "EXTRACT_ALL = YES"
    echo "EXTRACT_STATIC = YES"
    echo "SOURCE_BROWSER = YES"
    echo "FULL_PATH_NAMES = YES"
    echo "STRIP_FROM_PATH = ."
    echo "OUTPUT_DIRECTORY = docs"
    echo "HTML_OUTPUT = html"
    echo "GENERATE_LATEX = NO"
    echo "HAVE_DOT = NO"
    echo "QUIET = YES"
    echo "WARNINGS = NO"
  } | doxygen -
  W_ZIP="$NAME-$W_VERSION-docs.zip"
  rm -f "$W_ZIP"
  (cd docs/html && zip -qr "../../$W_ZIP" .)
  ls -lh "$W_ZIP"
}
