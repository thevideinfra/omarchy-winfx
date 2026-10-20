// The highlight colour: the picked accent, or the neutral foreground when
// accents are switched off.
function accentFor(enabled, picked, neutral) {
  return enabled ? picked : neutral
}

var ACCENT_NAMES = ["blue", "cyan", "green", "magenta", "yellow", "red", "orange"]

// name -> "#rrggbb" for every quoted hex colour in a theme's colors.toml.
function parsePalette(text) {
  var palette = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
    if (m) palette[m[1]] = m[2]
  }
  return palette
}

// "theme" followed by whichever accent colours the palette has.
function accentChoices(palette) {
  var list = ["theme"]
  for (var i = 0; i < ACCENT_NAMES.length; i++)
    if (palette && palette[ACCENT_NAMES[i]] !== undefined) list.push(ACCENT_NAMES[i])
  return list
}

// The palette colour for a choice, or null when the theme's own accent applies
// ("theme", or a colour this theme does not define).
function accentColor(choice, palette) {
  if (choice && choice !== "theme" && palette && palette[choice] !== undefined) return palette[choice]
  return null
}

// The "version" field of a manifest.json text; empty if it cannot be read.
function manifestVersion(text) {
  try {
    var v = JSON.parse(String(text)).version
    return v ? String(v) : ""
  } catch (e) {
    return ""
  }
}

// Size multiplier for the panel's own spacing, fonts and width, relative
// to the stock panel. All three are smaller than stock; normal is the default.
function densityScale(name) {
  if (name === "compact") return 0.52
  // "comfortable" is the old name of roomy.
  if (name === "roomy" || name === "comfortable") return 0.71
  return 0.61
}

// Text size multiplier chosen in settings, applied on top of the density's
// own text scaling.
function fontSizeScale(name) {
  if (name === "small") return 0.75
  if (name === "large") return 0.95
  return 0.85
}

// shell.json values may arrive as real booleans or as "true"/"false" strings
// (omarchy bar set without --json).
function settingBool(value, fallback) {
  if (value === true || value === "true") return true
  if (value === false || value === "false") return false
  return fallback
}
