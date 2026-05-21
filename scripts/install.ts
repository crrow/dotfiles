#!/usr/bin/env bun
// Real installer — invoked by install.sh once brew + bun are on the system.
//
// 1. brew install git           (so the next step works on a vanilla mac)
// 2. clone / update the repo at $DOTFILES_DIR
// 3. inside the repo: bun install + bun run setup
//
// Env knobs:
//   DOTFILES_DIR  target checkout path (default: ~/code/personal/dotfiles)
//   DOTFILES_REF  branch / tag / commit             (default: main)

import { $ } from "bun";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

const REPO = "https://github.com/crrow/dotfiles.git";
const DIR  = process.env.DOTFILES_DIR ?? join(homedir(), "code/personal/dotfiles");
const REF  = process.env.DOTFILES_REF ?? "main";

const log = {
  step: (m: string) => console.log(`\x1b[34m==>\x1b[0m ${m}`),
  ok:   (m: string) => console.log(`  \x1b[32m✓\x1b[0m ${m}`),
  err:  (m: string) => console.error(`\x1b[31m!!\x1b[0m ${m}`),
};

async function ensureGit() {
  log.step("brew install git");
  await $`brew install git`;
}

async function ensureRepo() {
  if (existsSync(join(DIR, ".git"))) {
    log.step(`update ${DIR}`);
    await $`git -C ${DIR} fetch --quiet origin ${REF}`;
    await $`git -C ${DIR} checkout --quiet ${REF}`;
    await $`git -C ${DIR} pull --ff-only --quiet`;
  } else {
    log.step(`clone ${REPO} → ${DIR}`);
    mkdirSync(dirname(DIR), { recursive: true });
    await $`git clone --branch ${REF} ${REPO} ${DIR}`;
  }
}

async function runSetup() {
  process.chdir(DIR);
  log.step("bun install");
  await $`bun install`;
  log.step("bun run setup");
  await $`bun run setup`;
}

async function main() {
  await ensureGit();
  await ensureRepo();
  await runSetup();
  log.ok("done — open a new shell to pick up your new $SHELL/$PATH");
}

main().catch((e) => { log.err(String(e)); process.exit(1); });
