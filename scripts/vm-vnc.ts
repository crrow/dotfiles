#!/usr/bin/env bun
// Find the VNC URL for the running VM and hand it to macOS `open` (which
// uses Screen Sharing as the default vnc:// handler).
//
// Two sources, in order of preference:
//   1. `lume get <vm> -f json` → vncUrl field (set while the VM is running)
//   2. /tmp/lume-<vm>.log → the line lume prints on startup

import { $ } from "bun";
import { VM, log } from "./lib.ts";

async function fromLumeJson(): Promise<string | undefined> {
  const r = await $`lume get ${VM} -f json`.nothrow().quiet();
  if (r.exitCode !== 0) return;
  try {
    const data = JSON.parse(r.text()) as { vncUrl?: string | null };
    return data.vncUrl ?? undefined;
  } catch { return; }
}

async function fromLogFile(): Promise<string | undefined> {
  const path = `/tmp/lume-${VM}.log`;
  if (!(await Bun.file(path).exists())) return;
  const text = await Bun.file(path).text();
  const matches = text.match(/vnc:\/\/\S+/g);
  return matches?.at(-1);
}

async function main() {
  const url = (await fromLumeJson()) ?? (await fromLogFile());
  if (!url) {
    log.err("could not find VNC URL — is the VM running? try: just vm-ls");
    process.exit(1);
  }
  console.log(`opening ${url}`);
  await $`open ${url}`;
}

main().catch((e) => { log.err(String(e)); process.exit(1); });
