import test, { beforeEach } from "node:test"
import assert from "node:assert/strict"

// This bounded fixture exercises events, timers and lifecycle, not browser layout.
class NodeFixture extends EventTarget {
  constructor() {
    super()
    this.attributes = new Map()
    this.classes = new Set()
    this.classList = { toggle: (name, on) => on ? this.classes.add(name) : this.classes.delete(name) }
  }
  setAttribute(name, value) { this.attributes.set(name, String(value)) }
  getAttribute(name) { return this.attributes.get(name) ?? null }
  closest(selector) { return selector === "button" && this.isButton ? this : null }
}

class ShadowFixture extends EventTarget {
  set innerHTML(html) {
    this.nodes = new Map()
    for (const selector of [".number", ".step-name", "h3", ".description", ".output strong", ".counter", ".marker", ".status"]) {
      this.nodes.set(selector, new NodeFixture())
    }
    this.buttons = [...html.matchAll(/<button([^>]*)>/g)].map(([, attrs]) => {
      const button = new NodeFixture()
      button.isButton = true
      for (const [, name, value] of attrs.matchAll(/([\w-]+)="([^"]*)"/g)) button.setAttribute(name, value)
      button.click = () => {
        if (button.disabled) return
        const event = new Event("click")
        Object.defineProperty(event, "target", { value: button })
        this.dispatchEvent(event)
      }
      return button
    })
    this.steps = Array.from({ length: 7 }, () => new NodeFixture())
  }
  querySelector(selector) {
    return this.nodes.get(selector) || this.buttons.find(button =>
      selector === `.${button.getAttribute("class")}` ||
      selector === `[data-step="${button.getAttribute("data-step")}"]`
    )
  }
  querySelectorAll(selector) {
    return selector === ".step" ? this.steps : this.buttons.filter(button => button.getAttribute("data-step") !== null)
  }
}

globalThis.HTMLElement = class extends NodeFixture {
  attachShadow() { this.shadowRoot = new ShadowFixture(); return this.shadowRoot }
}
globalThis.customElements = { registry: new Map(), get(tag) { return this.registry.get(tag) }, define(tag, ctor) { this.registry.set(tag, ctor) } }
let timers, observers, motion
beforeEach(() => {
  timers = new Map()
  observers = []
  globalThis.document = new EventTarget()
  document.hidden = false
  motion = new EventTarget()
  motion.matches = false
  globalThis.matchMedia = () => motion
  globalThis.setInterval = callback => { const id = Symbol(); timers.set(id, callback); return id }
  globalThis.clearInterval = id => timers.delete(id)
  globalThis.IntersectionObserver = class {
    constructor(callback) { this.callback = callback; observers.push(this) }
    observe(node) { this.node = node }
    disconnect() { this.node = null }
    show(visible) { this.callback([{ isIntersecting: visible }]) }
  }
})

const { StrategyAnimation, steps } = await import("./strategy_animation.mjs")
const connect = () => { const element = new StrategyAnimation(); element.connectedCallback(); return element }
const node = (element, selector) => element.shadowRoot.querySelector(selector)
const tick = () => [...timers.values()].forEach(callback => callback())
const visibility = hidden => { document.hidden = hidden; document.dispatchEvent(new Event("visibilitychange")) }
const reduceMotion = reduced => { motion.matches = reduced; motion.dispatchEvent(new Event("change")) }

test("registration and autoplay render all seven stages and wrap", () => {
  assert.equal(customElements.get("ai-strategy-animation"), StrategyAnimation)
  assert.equal(steps.length, 7)
  const element = connect()
  assert.equal(timers.size, 0, "wait for visibility before autoplay")
  observers[0].show(true)
  for (let index = 0; index < 7; index++) {
    assert.equal(node(element, ".step-name").textContent, steps[index][0])
    assert.equal(node(element, "h3").textContent, steps[index][1])
    assert.equal(node(element, ".description").textContent, steps[index][2])
    assert.equal(node(element, ".output strong").textContent, steps[index][3])
    assert.equal(node(element, ".marker").getAttribute("cx"), String(75 + index * 76))
    assert.equal(element.shadowRoot.steps[index].classes.has("current"), true)
    tick()
  }
  assert.equal(element.index, 0)
  element.disconnectedCallback()
})

test("previous, next and step buttons pause and update pressed state", () => {
  const element = connect()
  observers[0].show(true)
  node(element, ".prev").click()
  assert.equal(element.index, 6)
  assert.equal(node(element, ".counter").textContent, "07 / 07")
  node(element, ".next").click()
  assert.equal(element.index, 0)
  node(element, '[data-step="3"]').click()
  assert.equal(element.index, 3)
  assert.equal(node(element, '[data-step="3"]').getAttribute("aria-pressed"), "true")
  assert.equal(node(element, '[data-step="0"]').getAttribute("aria-pressed"), "false")
  assert.equal(timers.size, 0)
  assert.equal(node(element, ".pause").getAttribute("aria-label"), "Play animation")
  element.disconnectedCallback()
})

test("hidden and offscreen content suspends autoplay without losing position", () => {
  const element = connect()
  observers[0].show(true)
  tick()
  visibility(true)
  assert.equal(timers.size, 0)
  assert.equal(element.index, 1)
  visibility(false)
  assert.equal(timers.size, 1)
  observers[0].show(false)
  assert.equal(timers.size, 0)
  observers[0].show(true)
  assert.equal(timers.size, 1)
  element.disconnectedCallback()
})

test("manual pause survives visibility changes and Play resumes once", () => {
  const element = connect()
  observers[0].show(true)
  node(element, ".pause").click()
  visibility(true)
  visibility(false)
  observers[0].show(true)
  assert.equal(timers.size, 0)
  node(element, ".pause").click()
  assert.equal(timers.size, 1)
  assert.equal(node(element, ".pause").getAttribute("aria-label"), "Pause animation")
  tick()
  assert.equal(element.index, 1)
  element.disconnectedCallback()
})

test("reduced motion disables autoplay but allows manual exploration", () => {
  motion.matches = true
  const element = connect()
  observers[0].show(true)
  assert.equal(timers.size, 0)
  assert.equal(node(element, ".pause").disabled, true)
  node(element, ".next").click()
  assert.equal(element.index, 1)
  reduceMotion(false)
  assert.equal(node(element, ".pause").disabled, false)
  assert.equal(timers.size, 0, "keep the manual paused choice")
  node(element, ".pause").click()
  assert.equal(timers.size, 1)
  reduceMotion(true)
  assert.equal(timers.size, 0)
  element.disconnectedCallback()
})

test("disconnect releases resources and reconnect reattaches listeners only once", () => {
  const element = connect()
  const root = element.shadowRoot
  observers[0].show(true)
  node(element, ".next").click()
  element.disconnectedCallback()
  assert.equal(observers[0].node, null)
  assert.equal(timers.size, 0)
  node(element, ".next").click()
  assert.equal(element.index, 1, "detached listeners must not respond")
  visibility(true)
  element.connectedCallback()
  element.connectedCallback()
  assert.equal(element.shadowRoot, root, "do not rebuild the shadow tree")
  assert.equal(observers.length, 2, "one observer per connection")
  observers[1].show(true)
  visibility(false)
  assert.equal(timers.size, 0, "manual pause persists across reconnect")
  node(element, ".next").click()
  assert.equal(element.index, 2, "one click must produce one update")
  node(element, ".pause").click()
  assert.equal(timers.size, 1)
  visibility(true)
  assert.equal(timers.size, 0, "document listener reattaches")
  visibility(false)
  reduceMotion(true)
  assert.equal(timers.size, 0, "motion listener reattaches")
  element.disconnectedCallback()
})
