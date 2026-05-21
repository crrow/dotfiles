#!/usr/bin/env bun
/**
 * Dotfiles installer.
 *
 * Bootstraps a fresh machine end-to-end:
 *   1. Install Homebrew (macOS / Linuxbrew)
 *   2. Install brew formulae + macOS casks
 *   3. Install oh-my-zsh + plugins
 *   4. Switch login shell to brew zsh
 *   5. Symlink every file under ./home/ into $HOME
 *
 * Prereqs (handled outside this script):
 *   - mise installed (`curl https://mise.run | sh`)
 *   - `mise install` ran (so bun is on PATH)
 *
 * Usage:
 *   bun run setup            # apply
 *   bun run setup -- --dry-run
 */

import { $ } from "bun";
import { existsSync, mkdirSync, readdirSync, statSync, lstatSync, symlinkSync, unlinkSync, readlinkSync, renameSync } from "node:fs";
import { homedir, platform } from "node:os";
import { dirname, join, relative, resolve } from "node:path";

const DRY = process.argv.includes("--dry-run");
const HOME = homedir();
const REPO = resolve(import.meta.dir, "..");
const HOME_SRC = join(REPO, "home");
const OS = platform(); // "darwin" | "linux" | ...

const C = {
  reset: "\x1b[0m", dim: "\x1b[2m",
  blue: "\x1b[34m", green: "\x1b[32m", yellow: "\x1b[33m", red: "\x1b[31m",
};

const log = {
  step: (msg: string) => console.log(`${C.blue}==>${C.reset} ${msg}`),
  ok:   (msg: string) => console.log(`  ${C.green}✓${C.reset} ${msg}`),
  skip: (msg: string) => console.log(`  ${C.dim}-${C.reset} ${C.dim}${msg}${C.reset}`),
  warn: (msg: string) => console.log(`  ${C.yellow}!${C.reset} ${msg}`),
  err:  (msg: string) => console.error(`${C.red}!!${C.reset} ${msg}`),
};

// --- helpers -------------------------------------------------------------------

async function has(cmd: string): Promise<boolean> {
  return (await $`command -v ${cmd}`.nothrow().quiet()).exitCode === 0;
}

async function sh(cmd: string): Promise<void> {
  if (DRY) { log.skip(`[dry] ${cmd}`); return; }
  // Single argv passed to bash -c — safe because we never interpolate user input.
  await $`bash -c ${cmd}`;
}

// --- 1. Homebrew ---------------------------------------------------------------

async function installHomebrew() {
  log.step("Homebrew");
  if (await has("brew")) { log.ok("already installed"); return; }
  if (DRY) { log.skip("would install Homebrew"); return; }
  await $`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`;
  log.ok("installed");
}

// --- 2. Brew packages ----------------------------------------------------------

const FORMULAE = ["starship", "zellij", "zsh", "git", "fzf"];
const CASKS_DARWIN = ["ghostty"];

async function installPackages() {
  log.step("brew formulae");
  for (const f of FORMULAE) await sh(`brew install ${f}`);

  if (OS === "darwin") {
    log.step("brew casks (macOS)");
    for (const c of CASKS_DARWIN) await sh(`brew install --cask ${c}`);
  }
}

// --- 3. oh-my-zsh + plugins ----------------------------------------------------

const OMZ_DIR = join(HOME, ".oh-my-zsh");
const OMZ_PLUGINS_DIR = join(OMZ_DIR, "custom", "plugins");

const PLUGINS: Array<{ name: string; repo: string }> = [
  { name: "zsh-autosuggestions",     repo: "https://github.com/zsh-users/zsh-autosuggestions" },
  { name: "zsh-syntax-highlighting", repo: "https://github.com/zsh-users/zsh-syntax-highlighting" },
  { name: "zsh-completions",         repo: "https://github.com/zsh-users/zsh-completions" },
];

async function installOhMyZsh() {
  log.step("oh-my-zsh");
  if (existsSync(OMZ_DIR)) {
    log.ok("already installed");
  } else if (DRY) {
    log.skip("would install oh-my-zsh");
  } else {
    await $`sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`.env({
      ...process.env, RUNZSH: "no", CHSH: "no", KEEP_ZSHRC: "yes",
    });
    log.ok("installed");
  }

  log.step("oh-my-zsh plugins");
  if (!DRY) mkdirSync(OMZ_PLUGINS_DIR, { recursive: true });
  for (const { name, repo } of PLUGINS) {
    const dest = join(OMZ_PLUGINS_DIR, name);
    if (existsSync(dest)) { log.ok(name); continue; }
    await sh(`git clone --depth=1 ${repo} ${dest}`);
  }
}

// --- 4. Login shell ------------------------------------------------------------

async function switchLoginShell() {
  log.step("login shell");
  if (DRY) { log.skip("would switch to brew zsh"); return; }
  const brewPrefix = (await $`brew --prefix`.text()).trim();
  const brewZsh = `${brewPrefix}/bin/zsh`;
  if (!existsSync(brewZsh)) { log.warn(`${brewZsh} not found, skipping chsh`); return; }
  if (process.env.SHELL === brewZsh) { log.ok(`already ${brewZsh}`); return; }

  const shells = await Bun.file("/etc/shells").text();
  if (!shells.split("\n").includes(brewZsh)) {
    log.warn(`adding ${brewZsh} to /etc/shells (sudo)`);
    await $`echo ${brewZsh} | sudo tee -a /etc/shells`;
  }
  await $`chsh -s ${brewZsh}`.nothrow();
  log.ok(`switched to ${brewZsh}`);
}

// --- 5. Symlink home/* -> $HOME ------------------------------------------------

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

function backup(target: string) {
  const bak = `${target}.bak-${Date.now()}`;
  log.warn(`backing up ${target} -> ${bak}`);
  renameSync(target, bak);
}

function linkOne(src: string, target: string) {
  if (lstatSync(target, { throwIfNoEntry: false })) {
    // Already a symlink to src? No-op.
    try {
      if (lstatSync(target).isSymbolicLink() && readlinkSync(target) === src) {
        log.ok(relative(HOME, target));
        return;
      }
    } catch { /* fallthrough to backup */ }
    if (DRY) { log.skip(`would backup ${target}`); }
    else { backup(target); }
  }
  if (DRY) { log.skip(`would link ${relative(HOME, target)} -> ${src}`); return; }
  mkdirSync(dirname(target), { recursive: true });
  symlinkSync(src, target);
  log.ok(relative(HOME, target));
}

function symlinkHome() {
  log.step(`symlink ${relative(REPO, HOME_SRC)} → $HOME`);
  if (!existsSync(HOME_SRC)) { log.warn("home/ directory missing, skipping"); return; }
  for (const src of walk(HOME_SRC)) {
    const rel = relative(HOME_SRC, src);
    linkOne(src, join(HOME, rel));
  }
}

// --- main ----------------------------------------------------------------------

async function main() {
  if (DRY) log.warn("dry-run mode: no changes will be made");
  log.step(`os=${OS}  home=${HOME}  repo=${REPO}`);

  await installHomebrew();
  await installPackages();
  await installOhMyZsh();
  symlinkHome();
  await switchLoginShell();

  log.step("done — open a new shell to pick up changes");
}

main().catch((e) => { log.err(String(e)); process.exit(1); });
