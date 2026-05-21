#!/usr/bin/env bun
// Stop and delete the working VM. Kills any leftover `lume run` host process
// belt-and-braces — lume occasionally reports a VM as `stopped` while the
// underlying VZ XPC service is still running and still counts against
// Apple's 2-active-VM cap.

import { $ } from "bun";
import { BASELINE, VM, log } from "./lib.ts";

async function main() {
  log.step(`teardown ${VM}`);
  await $`lume stop ${VM}`.nothrow().quiet();
  await $`pkill -f ${`lume run ${VM}`}`.nothrow().quiet();
  await Bun.sleep(1000);
  await $`lume delete ${VM} --force`.nothrow().quiet();
  log.ok(`${VM} removed (baseline ${BASELINE} kept)`);
}

main().catch((e) => { log.err(String(e)); process.exit(1); });
