# shellcheck shell=sh
# Defines warp_ldoc, which writes the LDoc docs of a release from the Lua
# sources of the repository (bin/, dist/ and dot folders left out). Set before
# it: NAME. A template calls it with no arguments:
#
#   warp_ldoc
#
# The comments are plain -- ones: an awk filter makes the first comment block
# of a file its module description and a comment block right above a function
# its doc comment; --- comments stay as they are. Every function is listed,
# local ones and those with no comment too. A config.ld in the repository
# takes over the settings. LDoc and zip come from the image; where it has none,
# the template sets W_SETUP to the command that installs them, run only when
# there are sources. The site is zipped into <name>-<version>-docs.zip.
# Without Lua sources there are no docs, and nothing fails.
warp_ldoc() {
  W_FILES=$(find . -type f -name '*.lua' -not -path './bin/*' -not -path './dist/*' -not -path './.*' -not -path './docs/*' | sort)
  if [ -z "$W_FILES" ]; then
    echo "==> No Lua sources: no docs"
    return 0
  fi
  if [ -n "$W_SETUP" ]; then
    eval "$W_SETUP"
  fi
  W_VERSION=$(cat .version)
  W_TITLE=$(sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json 2>/dev/null | head -n 1)
  [ -n "$W_TITLE" ] || W_TITLE=$NAME
  W_OUT="$(pwd)/docs"
  rm -rf "$W_OUT"
  echo "==> Generating the docs of $W_TITLE $W_VERSION with LDoc"
  if [ -f config.ld ]; then
    ldoc -d "$W_OUT" .
  else
    W_SRC=/tmp/warp-ldoc/src
    rm -rf /tmp/warp-ldoc
    mkdir -p "$W_SRC"
    for W_FILE in $W_FILES; do
      W_REL=$(printf '%s' "$W_FILE" | sed 's|^\./||')
      mkdir -p "$W_SRC/$(dirname "$W_REL")"
      awk -v module="$(printf '%s' "$W_REL" | sed 's/\.lua$//' | tr '/' '.')" '
        function flush(target) {
          if (n == 0) return
          if (target != "") { sub(/^[ \t]*--+[ \t]?/, "--- ", buf[1]) }
          for (i = 1; i <= n; i++) print buf[i]
          if (target == "module") print "-- @module " module
          n = 0
        }
        /^[ \t]*---/ { flush(""); print; seen = 1; doc = 1; next }
        /^[ \t]*--([^-[]|$)/ { if (doc) print; else buf[++n] = $0; next }
        /^[ \t]*$/ { if (!seen && n > 0) { flush("module"); seen = 1 } else flush(""); doc = 0; print; next }
        /^[ \t]*(local[ \t]+)?function[ \t]/ {
          if (!seen) print "--- " module "\n-- @module " module "\n"
          seen = 1
          if (n > 0) flush("fn"); else if (!doc) print "--- &nbsp;"
          doc = 0; print; next
        }
        { if (!seen) { flush("module"); seen = 1 } else flush(""); doc = 0; print }
        END { flush("") }
      ' "$W_FILE" > "$W_SRC/$W_REL"
    done
    {
      echo "project = [[$W_TITLE]]"
      echo "title = [[$W_TITLE $W_VERSION]]"
      echo "description = [[$W_TITLE $W_VERSION]]"
      echo "all = true"
      echo "format = 'markdown'"
      echo "sort = true"
      [ -f README.md ] && echo "readme = '$(pwd)/README.md'"
      echo "file = '$W_SRC'"
    } > /tmp/warp-ldoc/config.ld
    ldoc -c /tmp/warp-ldoc/config.ld -d "$W_OUT" "$W_SRC"
  fi
  W_ZIP="$NAME-$W_VERSION-docs.zip"
  rm -f "$W_ZIP"
  (cd "$W_OUT" && zip -qr "../$W_ZIP" .)
  ls -lh "$W_ZIP"
}
