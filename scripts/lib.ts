// Shared constants and lume helpers for the scripts/ entry points.

import { $ } from "bun";

export const BASELINE = "dotfiles-test";
export const VM = "dotfiles-run";
export const IMAGE = "macos-sequoia-vanilla-sparse:latest";

export const C = {
  reset: "\x1b[0m", dim: "\x1b[2m",
  blue:  "\x1b[34m", green: "\x1b[32m", yellow: "\x1b[33m", red: "\x1b[31m",
};
export const log = {
  step: (m: string) => console.log(`${C.blue}==>${C.reset} ${m}`),
  ok:   (m: string) => console.log(`  ${C.green}✓${C.reset} ${m}`),
  warn: (m: string) => console.log(`  ${C.yellow}!${C.reset} ${m}`),
  err:  (m: string) => console.error(`${C.red}!!${C.reset} ${m}`),
};

/** True if a VM with this exact name is registered in lume. */
export async function vmExists(name: string): Promise<boolean> {
  const out = await $`lume ls`.text();
  return out
    .split("\n")
    .some((line) => line.split(/\s+/)[0] === name);
}
