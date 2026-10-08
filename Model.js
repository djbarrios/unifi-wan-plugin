function rate(mbps) {
  if (mbps === null || mbps === undefined) return "–"
  if (mbps === 0) return "0"
  if (mbps >= 1000) return (mbps / 1000).toFixed(2) + "G"
  if (mbps >= 100) return Math.round(mbps) + "M"
  if (mbps >= 1) return mbps.toFixed(1) + "M"
  return Math.round(mbps * 1000) + "k"
}

function linkSpeed(speed) {
  if (!speed) return "?"
  return speed >= 1000 ? (speed / 1000) + " Gbps" : speed + " Mbps"
}

function duration(seconds) {
  if (!seconds) return "?"
  var d = Math.floor(seconds / 86400)
  var h = Math.floor(seconds % 86400 / 3600)
  var m = Math.floor(seconds % 3600 / 60)
  return d > 0 ? d + "d " + h + "h" : (h > 0 ? h + "h " + m + "m" : m + "m")
}

function ago(epoch) {
  if (!epoch) return "never"
  return duration(Math.floor(Date.now() / 1000) - epoch) + " ago"
}

function icon(s) {
  return s && s.state === "down" ? "󰖪" : "󰖟"
}

function label(s) {
  if (!s) return "…"
  if (s.state === "error") return "?"
  if (s.state === "down") return "WAN down"
  return "↓" + rate(s.down) + " ↑" + rate(s.up)
}

// Green while any ISP link is carrying traffic, red when all are down.
function iconRole(s) {
  if (!s || s.state === "error") return "neutral"
  return s.state === "up" ? "ok" : "bad"
}

function themeColor(toml, name) {
  var m = new RegExp("^" + name + "\\s*=\\s*\"(#[0-9a-fA-F]{6,8})\"", "m").exec(toml || "")
  return m ? m[1] : ""
}

function portState(p) {
  return p.up ? "up, " + linkSpeed(p.speed) : "down"
}

function tooltip(s) {
  if (!s) return "UniFi WAN: loading…"
  if (s.state === "error") return "UniFi WAN: " + s.error
  var lines = [
    "ISP: " + (s.isp || "unknown") + " — " + s.state,
    "WAN IP: " + (s.wan_ip || "?"),
    "Now: ↓ " + rate(s.down) + "b/s  ↑ " + rate(s.up) + "b/s"
  ]
  var wans = s.wans || []
  for (var i = 0; i < wans.length; i++) lines.push(wans[i].port + ": " + portState(wans[i]))
  if (s.test_down || s.test_up) {
    lines.push("Speed test: ↓ " + Math.round(s.test_down || 0) + " / ↑ " + Math.round(s.test_up || 0) + " Mbps" +
               (s.test_ping ? ", " + s.test_ping + " ms" : "") + " (" + ago(s.test_at) + ")")
  }
  if (s.latency) lines.push("Latency: " + s.latency + " ms")
  if (s.uptime) lines.push("Internet uptime: " + duration(s.uptime))
  lines.push("", "Left: details · Middle: refresh · Right: open UniFi")
  return lines.join("\n")
}


// History of {t, down, up} samples (ms, Mbps). The router refreshes its
// counters every 5-10s, so repeated readings are dropped rather than plotted
// as fake flat segments; one sample older than the window is kept so the line
// enters from the left edge.
function pushSample(history, s, now, windowMs) {
  var next = (history || []).slice()
  if (s && s.state !== "error" && s.down !== null && s.down !== undefined) {
    var last = next.length ? next[next.length - 1] : null
    if (!last || last.down !== s.down || last.up !== s.up)
      next.push({ t: now, down: s.down, up: s.up || 0 })
  }
  while (next.length > 1 && next[1].t < now - windowMs) next.shift()
  return next
}

// Rounded-up axis maximum (Mbps) so the top gridline reads cleanly.
function axisMax(history) {
  var peak = 0
  for (var i = 0; i < (history || []).length; i++)
    peak = Math.max(peak, history[i].down, history[i].up)
  peak = Math.max(peak * 1.15, 0.1)
  var mag = Math.pow(10, Math.floor(Math.log(peak) / Math.LN10))
  var steps = [1, 2, 2.5, 5, 10]
  for (var j = 0; j < steps.length; j++)
    if (steps[j] * mag >= peak) return steps[j] * mag
  return 10 * mag
}

function details(s) {
  if (!s || s.state === "error") return []
  var rows = [
    ["ISP", (s.isp || "unknown") + " — " + s.state],
    ["WAN IP", s.wan_ip || "?"]
  ]
  var wans = s.wans || []
  for (var i = 0; i < wans.length; i++) rows.push([wans[i].port, portState(wans[i])])
  rows.push(["Rates", s.source === "snmp" ? "live via SNMP" : "router stats (can lag)"])
  if (s.test_down || s.test_up)
    rows.push(["Speed test", "↓ " + Math.round(s.test_down || 0) + " / ↑ " + Math.round(s.test_up || 0) + " Mbps (" + ago(s.test_at) + ")"])
  if (s.latency) rows.push(["Latency", s.latency + " ms"])
  if (s.uptime) rows.push(["Uptime", duration(s.uptime)])
  return rows
}

if (typeof module !== "undefined") {
  module.exports = { pushSample: pushSample, axisMax: axisMax, details: details, rate: rate, icon: icon, label: label, iconRole: iconRole, themeColor: themeColor, tooltip: tooltip }
}
