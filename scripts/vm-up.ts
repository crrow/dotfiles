#!/usr/bin/env bun
// Bring up a clean working VM. Pulls the baseline if needed, deletes any
// leftover `dotfiles-run` clone, clones a fresh one, starts it (with the
// VNC client opening automatically), and polls SSH until ready.

import { $ } from "bun";
import { BASELINE, C, IMAGE, VM, log, vmExists } from "./lib.ts";

async function ensureBaseline() {
  log.step(`baseline ${BASELINE}`);
  if (await vmExists(BASELINE)) { log.ok("present"); return; }
  log.step(`pulling ${IMAGE} → ${BASELINE} (~22 GB, one-off)`);
  await $`lume pull ${IMAGE} ${BASELINE}`;
}

async function resetClone() {
  log.step(`reset ${VM}`);
  await $`pkill -f ${`lume run ${VM}`}`.nothrow().quiet();
  await Bun.sleep(1000);
  await $`lume stop ${VM}`.nothrow().quiet();
  await $`lume delete ${VM} --force`.nothrow().quiet();
  await $`lume clone ${BASELINE} ${VM}`;
  log.ok("cloned");
}

async function startVm() {
  log.step(`start ${VM} (VNC opens automatically)`);
  const logFile = `/tmp/lume-${VM}.log`;
  // Don't pass --no-display: we WANT the macOS Screen Sharing client to pop.
  // lume's `run` blocks the foreground; detach it and route output to a file.
  Bun.spawn(["lume", "run", VM], {
    stdout: Bun.file(logFile),
    stderr: Bun.file(logFile),
    stdin: "ignore",
  });
  log.ok(`background pid; log → ${logFile}`);
}

async function waitForSsh() {
  log.step("wait for ssh");
  const deadline = Date.now() + 5 * 60_000;
  while (Date.now() < deadline) {
    const r = await $`lume ssh ${VM} --timeout 5 -- echo ready`.nothrow().quiet();
    if (r.exitCode === 0 && r.text().includes("ready")) {
      log.ok("ssh up");
      return;
    }
    await Bun.sleep(5000);
    process.stdout.write(".");
  }
  throw new Error(`VM ${VM} did not become ssh-able within 5 min`);
}

async function main() {
  await ensureBaseline();
  await resetClone();
  await startVm();
  await waitForSsh();

  console.log();
  console.log(`${C.green}VM ready${C.reset}. Default creds: ${C.dim}lume / lume${C.reset}`);
  console.log("  just vm-ssh    # interactive shell");
  console.log("  just vm-vnc    # re-open VNC if you closed it");
  console.log("  just vm-down   # stop + delete");
}

main().catch((e) => { log.err(String(e)); process.exit(1); });
