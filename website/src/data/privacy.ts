import type { IconName } from "../components/ui/feature-icons";

// Every claim here is stated in the docs: Getting started, Settings → Features,
// Permissions, AI and Clipboard. Don't add one that isn't.

export const privacyStats = [
  { value: "0", label: "accounts" },
  { value: "0", label: "telemetry" },
  { value: "0", label: "dependencies" },
  { value: "<100 MB", label: "of memory" },
] as const;

export type DefaultSwitch = {
  icon: IconName;
  name: string;
  note: string;
  isOn: boolean;
};

// Mirrors the Features table in docs/reference/settings: everything ships off
// except Clipboard.
export const defaultSwitches: DefaultSwitch[] = [
  {
    icon: "aiChat",
    name: "AI",
    note: "No chat command and no history file until you turn it on.",
    isOn: false,
  },
  {
    icon: "clipboard",
    name: "Clipboard history",
    note: "Kept on your Mac for 3 months. Skips Keychain Access and Passwords.",
    isOn: true,
  },
];

export const permissionNote =
  "Permissions are asked for the moment a feature needs one, never at launch. A settings backup can never switch on a permission-gated feature.";
