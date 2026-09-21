// Single source of truth for links, install commands, and metadata used across
// the site. Update these in one place rather than hunting through components.

export const site = {
  name: "Delores",
  tagline: "The essentials, without the bloat.",
  repo: "https://github.com/jackdu2333/delores",
  // Only true once Pages is enabled for this repository, which it is not yet: the site is not
  // served from anywhere today, and the `deploy` job in website.yml still fails on that setting.
  url: "https://jackdu2333.github.io/delores",
  // Shown only until the build-time release lookup resolves, and if it fails.
  fallbackVersion: "v0.2.0",
  platform: "macOS 26+",
  license: "AGPL-3.0",
  licenseUrl: "https://github.com/jackdu2333/delores/blob/main/LICENSE",
  // Still upstream's values, and deliberately untouched here: a support button and a community
  // link are claims about this project, and inventing them would be worse than leaving them.
  // Every consumer is gone (footer, nav, docs sidebar, the closing section), so nothing renders
  // these — they are kept only so the originals are on record. Recorded as a release blocker in
  // docs/delores-release.md.
  community: {
    discord: "https://discord.gg/v2Eeb4QQy3",
  },
  support:
    "https://buy.polar.sh/polar_cl_NDVFC20DKQpLcNawsh97QzbARBXD3WNn8v35R0mbJmT",
} as const;

// The hero, in as few words as possible — headline plus one punchy line.
export const hero = {
  // One entry per line: the break falls between the two sentences at every
  // width. The last line ends bare, because the hero draws a caret after it.
  headlineLines: ["Everything on your Mac.", "One keystroke away"],
  sub: "A tiny, native launcher. No Electron. No account. No telemetry. No bullshit.",
  // The mono line under the buttons. Each fact is stated in the docs.
  facts: ["Under 100 MB of memory", "Zero dependencies", "Free & open source"],
} as const;

export const nav = [
  { label: "Features", href: "/#features" },
  { label: "Privacy", href: "/#privacy" },
  { label: "Docs", href: "/docs" },
] as const;

// The hero used to show two Homebrew commands here. They named upstream's tap and cask, so the
// command a visitor copied installed a different application — the same defect the download button
// had. Delores has no cask yet (docs/delores-release.md lists one under the release gate), so the
// honest hero shows the download and nothing else rather than someone else's install path.

// The logo wall under the hero, in render order. The track starts at the first
// entry with the left edge under the mask, so the two least-known names lead
// and the ones worth reading land mid-viewport on load.
export const companies = [
  "voidzero",
  "bytedance",
  "apple",
  "google",
  "microsoft",
  "openai",
  "anthropic",
  "stripe",
  "cloudflare",
  "github",
  "samsung",
  "alibaba",
  "oracle",
  "redhat",
] as const;

export type Company = (typeof companies)[number];
