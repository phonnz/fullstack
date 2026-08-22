// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/*_web.ex",
    "../lib/*_web/**/*.*ex",
    "../deps/live_toast/lib/**/*.*ex",
    "../storybook/**/*.*exs"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#FD4F00",
        // Theme-aware muted text. Backed by --muted in the daisyui themes
        // below; use `text-muted` instead of `text-base-content/60`, which
        // fails WCAG AA in both themes.
        muted: "var(--muted)",
        // Brand orange as TEXT. The raw brand #FD4F00 measures 3.34:1 on the
        // light base and 4.75:1 on the dark one — no single shade clears AA
        // in both, so this is theme-aware. Use `brand` for fills, this for text.
        "brand-content": "var(--brand-content)",
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    require("daisyui"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({ addVariant }) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({ addVariant }) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "./vendor/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).map(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) }
        })
      })
      matchComponents({
        "hero": ({ name, fullPath }) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": theme("spacing.5"),
            "height": theme("spacing.5")
          }
        }
      }, { values })
    })
  ],
  daisyui: {
    // Stock daisyUI light/dark, with the minimum overrides needed to reach
    // WCAG 2.1 AA. Every value below is measured, not estimated.
    themes: [
      {
        light: {
          ...require("daisyui/src/theming/themes")["light"],
          // Muted text token. Replaces `text-base-content/60`, which measures
          // 4.06:1 here and fails AA. Solid colour so it is theme-aware
          // rather than an opacity that only works in one theme.
          // 7.56:1 on base-100, 6.75:1 on base-200.
          "--muted": "#4B5563",
          // 5.23:1 on base-100, 4.67:1 on base-200
          "--brand-content": "#C43D00"
        }
      },
      {
        dark: {
          ...require("daisyui/src/theming/themes")["dark"],
          // Stock dark defines no primary-content, so it computes white:
          // 3.36:1 on primary, which fails AA. This gives 5.72:1.
          "primary-content": "#0F0B24",
          // 7.03:1 on base-100, 7.44:1 on base-200.
          "--muted": "#A6ADBB",
          // 6.12:1 on base-100, 6.48:1 on base-200
          "--brand-content": "#FF7A45"
        }
      }
    ],
    logs: false
  }
}
