// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { createLiveToastHook } from 'live_toast'
import Map from "./map";
// import VegaLite from "../vendor/vegalite"


let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let hooks = {
  Map,
  LiveToast: createLiveToastHook(),
} //{ VegaLite }
let liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken }, hooks })


// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
  // enable server log streaming to client.
  // disable with reloader.disableServerLogs()
  reloader.enableServerLogs();
  //window.liveReloader = reloader;
})
// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Theme switching.
//
// The initial theme is resolved before first paint by the inline script in
// root.html.heex. This only handles the user overriding it, and keeps
// aria-pressed in sync so the control is announced correctly.
//
// Delegated from document so it survives LiveView navigation without a hook.
function currentTheme() {
  return document.documentElement.dataset.theme || "light"
}

function syncThemeButtons() {
  const active = currentTheme()
  document.querySelectorAll(".theme-option").forEach(btn => {
    const isActive = btn.dataset.setTheme === active
    btn.setAttribute("aria-pressed", String(isActive))
    btn.classList.toggle("bg-primary", isActive)
    btn.classList.toggle("text-primary-content", isActive)
    btn.classList.toggle("text-muted", !isActive)
  })
}

document.addEventListener("click", event => {
  const btn = event.target.closest(".theme-option")
  if (!btn) { return }

  const theme = btn.dataset.setTheme
  document.documentElement.dataset.theme = theme
  try { localStorage.setItem("theme", theme) } catch (_) { /* private mode */ }
  syncThemeButtons()
})

// Follow the OS setting until the user makes an explicit choice.
try {
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", event => {
    let saved = null
    try { saved = localStorage.getItem("theme") } catch (_) { /* private mode */ }
    if (saved) { return }
    document.documentElement.dataset.theme = event.matches ? "dark" : "light"
    syncThemeButtons()
  })
} catch (_) { /* matchMedia unavailable */ }

window.addEventListener("phx:page-loading-stop", syncThemeButtons)
syncThemeButtons()

