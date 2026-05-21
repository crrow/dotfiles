#!/usr/bin/env bun
// Pull the read-only baseline macOS image into lume if it isn't already
// present. Run by `just baseline`, and as the first step of `vm-up`.

import { $ } from "bun";
import { BASELINE, IMAGE, log, vmExists } from "./lib.ts";

async function main() {
  log.step(`baseline ${BASELINE}`);
  if (await vmExists(BASELINE)) {
    log.ok("already present");
    return;
  }
  log.step(`pulling ${IMAGE} → ${BASELINE} (~22 GB, one-off)`);
  await $`lume pull ${IMAGE} ${BASELINE}`;
  log.ok("pulled");
}

main().catch((e) => { log.err(String(e)); process.exit(1); });
