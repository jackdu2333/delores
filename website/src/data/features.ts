import type { IconName } from "../components/ui/feature-icons";

export type FeaturePreview =
  | "launcher"
  | "clipboard"
  | "calculator"
  | "aiChat"
  | "quickActions"
  | "windows";

export type Feature = {
  icon: IconName;
  title: string;
  body: string;
  /** Deep link into the docs page that covers this feature. */
  href: string;
  preview: FeaturePreview;
  /** Spans two columns of the bento on wide screens. */
  isWide: boolean;
};

export type MinorFeature = Pick<Feature, "icon" | "title" | "href">;

// Everything the app does, in plain language. Kept true to what the app
// actually ships — each maps to a real feature in the source, and each links
// to the docs page that covers it. Order sets the bento: every row adds up to
// four columns, with wide cards counting as two.
export const coreFeatures: Feature[] = [
  {
    icon: "launch",
    title: "App launcher",
    body: "Fuzzy-search every app and open it with a keystroke. Pin favorites, see what's running, restart or quit without the mouse.",
    href: "/docs/launcher",
    preview: "launcher",
    isWide: true,
  },
  {
    icon: "calculator",
    title: "Inline calculator",
    body: "Math, units, live currency, time zones and dates like “days till 9 Apr”.",
    href: "/docs/features/calculator",
    preview: "calculator",
    isWide: false,
  },
  {
    icon: "clipboard",
    title: "Clipboard history",
    body: "Text, images, files and colors, searchable and pasted straight back.",
    href: "/docs/features/clipboard",
    preview: "clipboard",
    isWide: false,
  },
  {
    icon: "aiChat",
    title: "AI Chat",
    body: "Apple Intelligence, Codex, Claude, OpenCode or any API you bring.",
    href: "/docs/ai",
    preview: "aiChat",
    isWide: false,
  },
  {
    icon: "quickActions",
    title: "Quick Actions",
    body: "Select text in any app and fix, rewrite, translate or summarize it.",
    href: "/docs/ai/quick-actions",
    preview: "quickActions",
    isWide: false,
  },
  {
    icon: "windows",
    title: "Window management",
    body: "Halves, thirds, nudges, display moves and saved layouts, all from the keyboard. 34 commands.",
    href: "/docs/features/window-management",
    preview: "windows",
    isWide: true,
  },
];

// The long tail: named, linked, and kept out of the way of the six above.
export const moreFeatures: MinorFeature[] = [
  { icon: "notes", title: "Floating notes", href: "/docs/features/notes" },
  {
    icon: "fileSearch",
    title: "File search",
    href: "/docs/features/file-search",
  },
  {
    icon: "navigation",
    title: "Window & menu search",
    href: "/docs/features/navigation",
  },
  {
    icon: "quicklinks",
    title: "Quicklinks",
    href: "/docs/launcher/quicklinks",
  },
  {
    icon: "bolt",
    title: "31 system actions",
    href: "/docs/launcher/system-actions",
  },
  { icon: "globe", title: "Per-app hotkeys", href: "/docs/reference/hotkeys" },
  { icon: "hyper", title: "Hyper key", href: "/docs/reference/hotkeys" },
  { icon: "alias", title: "Aliases", href: "/docs/launcher/aliases" },
  {
    icon: "uninstall",
    title: "App uninstaller",
    href: "/docs/launcher/uninstall",
  },
  {
    icon: "inputSource",
    title: "Input source switching",
    href: "/docs/palette#input-source",
  },
  {
    icon: "appearance",
    title: "Light, Dark and glass",
    href: "/docs/palette#appearance",
  },
  { icon: "backup", title: "Backup & restore", href: "/docs/reference/backup" },
];
