// Strategy illustration only: this component does not calculate viability.
export const steps = [
  [
    "Diagnose needs",
    "Find the work worth improving.",
    "Map repetitive tasks, bottlenecks, and inefficient processes before deciding where AI belongs.",
    "Process map & opportunity shortlist"
  ],
  [
    "Set SMART goals",
    "Give every improvement a purpose.",
    "Define specific, measurable, achievable, relevant, and time-bound objectives for the selected processes.",
    "Clear objectives & delivery milestones"
  ],
  [
    "Define KPIs",
    "Decide what success looks like.",
    "Establish baseline performance and track indicators such as time per task, error rate, and service quality.",
    "Baseline metrics & success criteria"
  ],
  [
    "Select tools",
    "Match the tools to the work.",
    "Choose accessible AI and automation tools that fit the process, available data, team capabilities, and integrations.",
    "Tool shortlist & integration plan"
  ],
  [
    "Estimate economic impact",
    "Build the business case.",
    "Compare setup and ongoing costs with expected benefits. Make assumptions explicit and assess the expected return.",
    "Cost estimates & expected ROI"
  ],
  [
    "Run a pilot",
    "Start small. Learn in practice.",
    "Launch a controlled trial in one area, assign an owner, and measure results against the agreed success criteria.",
    "Pilot scope & measurement plan"
  ],
  [
    "Review & adjust",
    "Turn evidence into the next move.",
    "Analyze pilot results, refine the process, and decide what to improve, expand, or stop.",
    "Improvement plan & scale decision"
  ],
]

const styles = `
  :host { display: block; color: var(--ink); font-family: 'Inter', sans-serif; }
  * { box-sizing: border-box; }
  button { font: inherit; cursor: pointer; color: var(--ink); }
  button:focus-visible { outline: 2px solid var(--terracotta); outline-offset: 4px; }
  .intro { display: flex; align-items: end; justify-content: space-between; gap: 32px; margin-bottom: 28px; }
  .intro-heading, h3 { font-family: 'Fraunces', Georgia, serif; font-weight: 500; letter-spacing: -.01em; }
  .intro-heading { font-size: clamp(1.8rem, 3vw, 2.6rem); line-height: 1.15; margin: 0; }
  .intro-heading span { color: var(--forest-deep); }
  .intro p:last-child { max-width: 34ch; font-size: .88rem; line-height: 1.7; color: var(--ink-soft); margin: 0; }
  .journey { display: grid; grid-template-columns: repeat(3, 1fr); list-style: none; padding: 0; margin: 0 0 24px; border-block: 1px solid var(--sage-line); }
  .journey li { padding: 18px; border-right: 1px solid var(--sage-line); }
  .journey li:last-child { border: 0; background: var(--paper-card); }
  .journey strong { font-size: .82rem; font-weight: 600; }
  .journey small { display: block; margin-top: 6px; font-size: .72rem; color: var(--ink-soft); line-height: 1.5; }
  .panel { background: var(--white); border: 1px solid var(--sage-line); border-radius: 12px; overflow: hidden; }
  .panel-head { display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap; padding: 24px 28px 0; }
  .label, .step-caption, .output small { text-transform: uppercase; font-size: .65rem; letter-spacing: .1em; }
  .label, .pill { color: var(--ink-soft); }
  .pill { font-size: .7rem; }
  .main { display: grid; grid-template-columns: minmax(260px, .85fr) minmax(0, 1.5fr); align-items: center; min-height: 385px; }
  .detail { padding: 32px 0 32px 28px; }
  .step-caption { display: flex; align-items: center; gap: 12px; color: var(--forest-deep); }
  .number { font-size: 2rem; font-variant-numeric: tabular-nums; }
  h3 { font-size: 1.65rem; line-height: 1.2; margin: 16px 0 12px; }
  .description { font-size: .82rem; line-height: 1.8; color: var(--ink-soft); min-height: 94px; margin: 0; }
  .output { background: var(--paper-card); border-left: 2px solid var(--forest); border-radius: 0 6px 6px 0; padding: 14px 16px; margin-top: 22px; }
  .output small { display: block; color: var(--ink-soft); margin-bottom: 8px; }
  .output strong { font-size: .8rem; font-weight: 500; }
  .visual { padding: 0 16px; min-width: 0; }
  svg { display: block; width: 100%; height: auto; }
  .orbit { fill: none; stroke: var(--sage-line); stroke-dasharray: 4 7; }
  .step { transition: transform .6s ease; }
  .step .top { fill: var(--paper-card); stroke: var(--sage-line); stroke-width: 1.2; transition: fill .6s ease; }
  .step .front { fill: var(--sage-line); }
  .step .side { fill: var(--sage); }
  .step text { fill: var(--ink-soft); font-size: 13px; text-anchor: middle; font-weight: 600; }
  .step.done .top { fill: color-mix(in srgb, var(--forest) 18%, var(--paper)); }
  .step.current { transform: translateY(-7px); }
  .step.current .top, .step.current .front { fill: var(--forest-deep); stroke: var(--forest-deep); }
  .step.current .side { fill: var(--forest); }
  .step.current text { fill: var(--paper); }
  .marker { fill: var(--white); stroke: var(--terracotta); stroke-width: 2; transition: cx .65s ease, cy .65s ease; }
  .visual-note { fill: var(--ink-soft); font-size: 9px; text-transform: uppercase; letter-spacing: 1.5px; }
  .nav { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 8px; padding: 0 24px 24px; }
  .tab { border: 0; border-top: 2px solid var(--sage-line); background: transparent; text-align: left; padding: 12px 4px; min-height: 64px; color: var(--ink-soft); }
  .tab b { display: block; font-size: .7rem; font-weight: 400; margin-bottom: 8px; }
  .tab span { font-size: .7rem; line-height: 1.5; display: block; overflow-wrap: break-word; }
  .tab[aria-pressed=true] { color: var(--forest-deep); border-color: var(--forest); }
  .controls { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; padding: 16px 24px; border-top: 1px solid var(--sage-line); background: var(--paper-card); }
  .status { font-size: .72rem; color: var(--ink-soft); }
  .control-set { display: flex; align-items: center; gap: 8px; }
  .counter { font-size: .72rem; font-variant-numeric: tabular-nums; color: var(--ink-soft); margin-right: 6px; }
  .prev, .next, .pause { border: 1px solid var(--sage-line); background: var(--white); border-radius: 50%; min-width: 44px; min-height: 44px; }
  .pause { border-radius: 24px; padding: 0 14px; font-size: .75rem; }
  .pause:disabled { opacity: .6; cursor: default; }
  .footer { color: var(--ink-soft); font-size: .75rem; line-height: 1.7; margin: 20px 0 0; max-width: 85ch; }
  @media (max-width: 800px) {
    .intro { display: block; }
    .intro p:last-child { max-width: 60ch; margin-top: 16px; }
    .main { display: flex; flex-direction: column-reverse; min-height: 0; }
    .visual { width: 100%; max-width: 550px; margin: 12px 0; }
    .detail { width: 100%; padding: 0 24px 28px; }
    .description { min-height: 0; }
  }
  @media (max-width: 520px) {
    .journey li { padding: 12px 8px; }
    .journey strong { font-size: .72rem; }
    .journey small { font-size: .65rem; }
    .panel-head, .controls { padding: 18px; }
    .detail { padding-inline: 18px; }
    .nav { padding: 0 16px 16px; gap: 4px; }
    .tab { text-align: center; min-height: 44px; }
    .tab b { margin: 0; }
    .tab span { display: none; }
    .controls { justify-content: center; }
  }
  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { animation: none !important; transition: none !important; }
  }
`

function markup() {
  return `
    <style>${styles}</style>
    <div class="intro">
      <p class="intro-heading">Understand the potential.<br><span>Build the way forward.</span></p>
      <p>A business viability report that connects the opportunity to a practical strategy—including a clear path to AI adoption.</p>
    </div>
    <ol class="journey" aria-label="From insight to action">
      <li><strong>01 · Assess viability</strong><small>Opportunity · costs · risks</small></li>
      <li><strong>02 · Shape the strategy</strong><small>Priorities · actions · milestones</small></li>
      <li><strong>03 · Plan AI adoption</strong><small>A seven-step automation framework</small></li>
    </ol>
    <div class="panel">
      <div class="panel-head"><span class="label">Inside your strategy / AI & automation</span><span class="pill">7 steps. One practical roadmap.</span></div>
      <div class="main">
        <div class="detail">
          <div class="step-caption"><span class="number"></span><span class="step-name"></span></div>
          <h3></h3><p class="description"></p>
          <div class="output"><small>Strategy deliverable</small><strong></strong></div>
        </div>
        <div class="visual">
          <svg viewBox="0 0 650 370" role="img" aria-labelledby="strategy-visual-title strategy-visual-description">
            <title id="strategy-visual-title">A measured path to automation</title>
            <desc id="strategy-visual-description">Seven ascending steps, from diagnosing needs to reviewing and adjusting an automation pilot. Explore each step using the buttons below.</desc>
            <ellipse class="orbit" cx="338" cy="286" rx="274" ry="59"/>
            ${steps.map((_, index) => {
              const x = 75 + index * 76, y = 295 - index * 34
              return `<g class="step"><path class="front" d="M${x-54} ${y}l54 25v23l-54-25z"/><path class="side" d="M${x} ${y+25}l54-25v23l-54 25z"/><path class="top" d="M${x} ${y-25}l54 25-54 25-54-25z"/><text x="${x}" y="${y+5}">0${index+1}</text></g>`
            }).join("")}
            <circle class="marker" cx="75" cy="249" r="5"/>
            <text class="visual-note" x="280" y="353">A measured path to automation</text>
          </svg>
        </div>
      </div>
      <div class="nav" role="group" aria-label="Explore framework steps">
        ${steps.map(([name], index) => `<button type="button" class="tab" data-step="${index}" aria-pressed="${index === 0}" aria-label="Step ${index+1}: ${name}" title="${name}"><b>0${index+1}</b><span>${name}</span></button>`).join("")}
      </div>
      <div class="controls">
        <span class="status" role="status"></span>
        <div class="control-set"><span class="counter"></span><button type="button" class="prev" aria-label="Previous step">←</button><button type="button" class="pause" aria-label="Pause animation">Pause</button><button type="button" class="next" aria-label="Next step">→</button></div>
      </div>
    </div>
    <p class="footer">AI adoption is one part of the business strategy. Each step connects process improvements to measurable business outcomes.</p>
  `
}

export class StrategyAnimation extends HTMLElement {
  constructor() {
    super()
    this.index = 0
    this.userPaused = false
    this.connected = false
    this.onChange = () => this.sync()
    this.onClick = event => {
      const button = event.target.closest("button")
      if (!button || button.disabled) return
      const step = button.getAttribute("data-step")
      if (step !== null) this.select(Number(step))
      else if (button === this.q(".prev")) this.select(this.index - 1)
      else if (button === this.q(".next")) this.select(this.index + 1)
      else if (button === this.q(".pause")) {
        this.userPaused = !this.userPaused
        this.sync()
      }
    }
  }

  connectedCallback() {
    if (this.connected) return
    if (!this.shadowRoot) this.attachShadow({ mode: "open" }).innerHTML = markup()
    this.connected = true
    this.motion = matchMedia("(prefers-reduced-motion: reduce)")
    this.listeners = new AbortController()
    const options = { signal: this.listeners.signal }
    this.shadowRoot.addEventListener("click", this.onClick, options)
    this.motion.addEventListener("change", this.onChange, options)
    document.addEventListener("visibilitychange", this.onChange, options)
    this.visible = !globalThis.IntersectionObserver
    if (globalThis.IntersectionObserver) {
      this.observer = new IntersectionObserver(entries => {
        if (!this.connected) return
        this.visible = entries[0].isIntersecting
        this.sync()
      })
      this.observer.observe(this)
    }
    this.render()
    this.sync()
  }

  q(selector) { return this.shadowRoot.querySelector(selector) }

  select(index) {
    this.index = (index + steps.length) % steps.length
    this.userPaused = true
    this.render()
    this.sync()
    // Announce manual exploration, not every automatic transition.
    this.q(".status").textContent = `Step ${this.index + 1}: ${steps[this.index][0]}`
  }

  render() {
    const [name, heading, description, output] = steps[this.index]
    this.q(".number").textContent = String(this.index + 1).padStart(2, "0")
    this.q(".step-name").textContent = name
    this.q("h3").textContent = heading
    this.q(".description").textContent = description
    this.q(".output strong").textContent = output
    this.q(".counter").textContent = `0${this.index + 1} / 07`
    this.shadowRoot.querySelectorAll(".tab").forEach((button, index) => button.setAttribute("aria-pressed", String(index === this.index)))
    this.shadowRoot.querySelectorAll(".step").forEach((step, index) => {
      step.classList.toggle("current", index === this.index)
      step.classList.toggle("done", index < this.index)
    })
    this.q(".marker").setAttribute("cx", 75 + this.index * 76)
    this.q(".marker").setAttribute("cy", 249 - this.index * 34)
  }

  sync() {
    clearInterval(this.timer)
    this.timer = null
    if (!this.connected) return
    const stopped = this.userPaused || this.motion.matches
    const button = this.q(".pause")
    button.textContent = stopped ? "Play" : "Pause"
    button.setAttribute("aria-label", stopped ? "Play animation" : "Pause animation")
    button.disabled = this.motion.matches
    button.title = this.motion.matches ? "Automatic animation is disabled by your reduced-motion preference" : ""
    this.q(".status").textContent = this.motion.matches ? "Reduced motion · explore each step" : "Explore the method behind the roadmap"
    if (!stopped && !document.hidden && this.visible) {
      this.timer = setInterval(() => {
        this.index = (this.index + 1) % steps.length
        this.render()
      }, 5500)
    }
  }

  disconnectedCallback() {
    this.connected = false
    clearInterval(this.timer)
    this.timer = null
    this.observer?.disconnect()
    this.listeners?.abort()
  }
}

if (!customElements.get("ai-strategy-animation")) customElements.define("ai-strategy-animation", StrategyAnimation)
