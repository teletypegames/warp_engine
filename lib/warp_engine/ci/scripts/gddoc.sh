# shellcheck shell=sh
# Defines warp_gddoc, which writes the docs of a release from the GDScript of
# a Godot project. Set before it: NAME. A template calls it in the builder
# image, where godot is:
#
#   warp_gddoc
#
# Godot's own doctool (--gdscript-docs) writes the class reference of every
# script as XML, from a copy of the project in which an awk filter has made
# the plain # comment block right above a declaration (extends, class_name,
# func, var, const, signal, enum, an annotation) a ## doc comment; ## comments
# stay as they are. A GDScript run by Godot turns the XML into HTML pages: an
# index of the scripts and one page each with its members, methods, signals
# and constants. The site is zipped into <name>-<version>-docs.zip. Without a
# project.godot or GDScript there are no docs, and nothing fails.
warp_gddoc() {
  if [ ! -f project.godot ] || [ -z "$(find . -name '*.gd' -not -path './.*' | head -n 1)" ]; then
    echo "==> No GDScript in a Godot project: no docs"
    return 0
  fi
  W_VERSION=$(cat .version)
  W_TITLE=$(sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' metadata.json 2>/dev/null | head -n 1)
  [ -n "$W_TITLE" ] || W_TITLE=$NAME
  W_OUT="$(pwd)/docs"
  W_TMP=/tmp/warp-gddoc
  rm -rf "$W_OUT" "$W_TMP"
  mkdir -p "$W_TMP/project" "$W_TMP/xml"
  tar --exclude=./.git --exclude=./.godot -cf - . | tar -xf - -C "$W_TMP/project"
  find "$W_TMP/project" -name '*.gd' -not -path '*/.godot/*' | while read -r W_FILE; do
    awk '
      function flush(doc) {
        for (i = 1; i <= n; i++) { line = buf[i]; if (doc) sub(/#/, "##", line); print line }
        n = 0
      }
      /^[ \t]*##/ { flush(0); print; next }
      /^[ \t]*#/ && !/^#!/ { buf[++n] = $0; next }
      /^[ \t]*(extends|class_name|func|static[ \t]+func|var|const|signal|enum|@)/ { flush(1); print; next }
      { flush(0); print }
      END { flush(0) }
    ' "$W_FILE" > "$W_FILE.warp" && mv "$W_FILE.warp" "$W_FILE"
  done
  cat > "$W_TMP/html.gd" <<'GDSCRIPT'
extends SceneTree

const SECTIONS = ["methods", "members", "signals", "constants"]
const CSS = "body{font:15px/1.5 system-ui,sans-serif;max-width:60rem;margin:2rem auto;padding:0 1rem;color:#222}" \
	+ "h1,h2{font-weight:600}code,pre{font-family:ui-monospace,monospace;background:#f3f3f3;border-radius:3px}" \
	+ "code{padding:0 .2em}pre{padding:.6em}dt{margin-top:.8em;font-family:ui-monospace,monospace}dd{margin-left:1.5em}" \
	+ "a{color:#2a5db0}.inherits{color:#666}@media(prefers-color-scheme:dark){body{background:#1b1b1b;color:#ddd}" \
	+ "code,pre{background:#2a2a2a}a{color:#8ab4f8}.inherits{color:#999}}"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0]
	var out: String = args[1]
	var title: String = args[2]
	DirAccess.make_dir_recursive_absolute(out)
	var files := Array(DirAccess.get_files_at(src))
	files.sort()
	var classes := []
	for file in files:
		if file.ends_with(".xml"):
			classes.append(parse(src.path_join(file)))
	var items := ""
	for c in classes:
		items += "<li><a href=\"%s\">%s</a>%s</li>\n" % [page(c), esc(c.name), (" — " + bb(c.brief)) if c.brief != "" else ""]
	write(out.path_join("index.html"), title, "<h1>%s</h1>\n<ul>\n%s</ul>" % [esc(title), items])
	for c in classes:
		write(out.path_join(page(c)), c.name + " — " + title, body(c, title))
	quit()


func parse(path: String) -> Dictionary:
	var c := {"name": "", "inherits": "", "brief": "", "desc": "", "methods": [], "members": [], "signals": [], "constants": []}
	var p := XMLParser.new()
	p.open(path)
	var section := ""
	var item = null
	var target := ""
	while p.read() == OK:
		var type := p.get_node_type()
		if type == XMLParser.NODE_ELEMENT:
			var n := p.get_node_name()
			if n == "class":
				c.name = attr(p, "name").trim_prefix("\"").trim_suffix("\"")
				c.inherits = attr(p, "inherits")
			elif n in SECTIONS:
				section = n
			elif n in ["method", "signal"]:
				item = {"name": attr(p, "name"), "ret": "", "params": [], "desc": "", "qualifiers": attr(p, "qualifiers")}
				c[section].append(item)
			elif n in ["member", "constant"]:
				item = {"name": attr(p, "name"), "type": attr(p, "type"), "value": attr(p, "default") if n == "member" else attr(p, "value"), "desc": ""}
				c[section].append(item)
				target = "item"
			elif n == "return" and item != null:
				item.ret = attr(p, "type")
			elif n == "param" and item != null:
				var param := attr(p, "name") + ": " + attr(p, "type")
				if attr(p, "default") != "":
					param += " = " + attr(p, "default")
				item.params.append(param)
			elif n == "brief_description":
				target = "brief"
			elif n == "description":
				target = "item" if item != null else "desc"
		elif type == XMLParser.NODE_TEXT:
			var text := p.get_node_data().strip_edges().xml_unescape()
			if text == "":
				continue
			if target == "brief":
				c.brief += text
			elif target == "desc":
				c.desc += text
			elif target == "item" and item != null:
				item.desc += text
		elif type == XMLParser.NODE_ELEMENT_END:
			var n := p.get_node_name()
			if n in ["method", "signal", "member", "constant"]:
				item = null
				target = ""
			elif n in ["brief_description", "description"] and item == null:
				target = ""
			elif n in SECTIONS:
				section = ""
	return c


func body(c: Dictionary, title: String) -> String:
	var html := "<p><a href=\"index.html\">%s</a></p>\n<h1>%s</h1>\n" % [esc(title), esc(c.name)]
	if c.inherits != "":
		html += "<p class=\"inherits\">extends <code>%s</code></p>\n" % esc(c.inherits)
	if c.brief != "":
		html += "<p>%s</p>\n" % bb(c.brief)
	if c.desc != "":
		html += "<p>%s</p>\n" % bb(c.desc)
	html += entries("Members", c.members.map(func(m): return [m.name + ": " + m.type + ((" = " + m.value) if m.value != "" else ""), m.desc]))
	html += entries("Methods", c.methods.map(func(m): return ["func " + m.name + "(" + ", ".join(m.params) + ") -> " + m.ret + ((" " + m.qualifiers) if m.qualifiers != "" else ""), m.desc]))
	html += entries("Signals", c.signals.map(func(m): return ["signal " + m.name + "(" + ", ".join(m.params) + ")", m.desc]))
	html += entries("Constants", c.constants.map(func(m): return ["const " + m.name + " = " + m.value, m.desc]))
	return html


func entries(heading: String, rows: Array) -> String:
	if rows.is_empty():
		return ""
	var html := "<h2>%s</h2>\n<dl>\n" % heading
	for row in rows:
		html += "<dt>%s</dt>\n" % esc(row[0])
		if row[1] != "":
			html += "<dd>%s</dd>\n" % bb(row[1])
	return html + "</dl>\n"


func bb(text: String) -> String:
	var html := esc(text)
	for pair in [["[codeblock]", "<pre>"], ["[/codeblock]", "</pre>"], ["[code]", "<code>"], ["[/code]", "</code>"],
			["[b]", "<b>"], ["[/b]", "</b>"], ["[i]", "<i>"], ["[/i]", "</i>"], ["[br]", "<br>"]]:
		html = html.replace(pair[0], pair[1])
	return html.replace("\n", "<br>\n")


func page(c: Dictionary) -> String:
	return c.name.trim_suffix(".gd").replace("/", "--").replace(":", "-") + ".html"


func attr(p: XMLParser, name: String) -> String:
	return p.get_named_attribute_value_safe(name).xml_unescape()


func esc(text: String) -> String:
	return text.xml_escape()


func write(path: String, title: String, html: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("<!doctype html>\n<html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" \
		+ "<title>%s</title><style>%s</style></head><body>\n%s\n</body></html>\n" % [esc(title), CSS, html])
GDSCRIPT
  echo "==> Generating the docs of $W_TITLE $W_VERSION with the Godot doctool"
  (cd "$W_TMP/project" && godot --headless --import >/dev/null 2>&1; godot --headless --doctool "$W_TMP/xml" --gdscript-docs res:// >/dev/null 2>&1)
  (cd "$W_TMP" && godot --headless --script "$W_TMP/html.gd" -- "$W_TMP/xml" "$W_OUT" "$W_TITLE $W_VERSION" 2>&1 | grep -v -e fontconfig -e get_system_font_path)
  W_ZIP="$NAME-$W_VERSION-docs.zip"
  rm -f "$W_ZIP"
  (cd "$W_OUT" && zip -qr "../$W_ZIP" .)
  ls -lh "$W_ZIP"
}
