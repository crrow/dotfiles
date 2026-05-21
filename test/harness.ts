#!/usr/bin/env bun
/**
 * End-to-end test harness.
 *
 * Spins up a fresh macOS VM via lume, clones this repo from GitHub inside
 * the VM, runs `bun run setup`, and asserts the resulting filesystem state.
 *
 * Baseline VM `dotfiles-test` is treated as a read-only golden image: each
 * run clones it into `dotfiles-run`, exercises bootstrap there, then deletes
 * the clone. The baseline is only re-pulled when explicitly asked.
 *
 * Usage:
 *   bun run test/harness.ts                   # full test, deletes clone on exit
 *   bun run test/harness.ts --branch=my-pr    # test a different branch
 *   bun run test/harness.ts --keep            # leave the clone running for poking
 *   bun run test/harness.ts --reset-baseline  # re-pull baseline before cloning
 */

import { $ } from "bun";

const args = new Set(process.argv.slice(2));
const arg = (k: string) =>
  process.argv.slice(2).find((a) => a.startsWith(`--${k}=`))?.split("=", 2)[1];

const BASELINE = "dotfiles-test";
const CLONE = arg("clone") ?? "dotfiles-run";
const REPO = arg("repo") ?? "https://github.com/crrow/dotfiles.git";
const BRANCH = arg("branch") ?? "main";
const KEEP = args.has("--keep");
const RESET = args.has("--reset-baseline");

const C = {
  reset: "\x1b[0m", dim: "\x1b[2m",
  blue: "\x1b[34m", green: "\x1b[32m", yellow: "\x1b[33m", red: "\x1b[31m",
};
const log = {
  step: (m: string) => console.log(`${C.blue}==>${C.reset} ${m}`),
  ok:   (m: string) => console.log(`  ${C.green}✓${C.reset} ${m}`),
  warn: (m: string) => console.log(`  ${C.yellow}!${C.reset} ${m}`),
  err:  (m: string) => console.error(`${C.red}!!${C.reset} ${m}`),
};

// --- lume helpers --------------------------------------------------------------

async function lumeJson(): Promise<Array<{ name: string; status: string }>> {
  // `lume ls` is text-only; parse the rows.
  const out = await $`lume ls`.text();
  const lines = out.split("\n").filter((l) => l.trim() && !l.startsWith("NAME"));
  return lines.map((l) => {
    const [name = "", , , , , status = ""] = l.trim().split(/\s+/);
    return { name, status };
  });
}

async function vmExists(name: string): Promise<boolean> {
  return (await lumeJson()).some((v) => v.name === name);
}

async function vmStatus(name: string): Promise<string | null> {
  return (await lumeJson()).find((v) => v.name === name)?.status ?? null;
}

async function ensureBaseline() {
  log.step(`baseline VM: ${BASELINE}`);
  if (RESET && (await vmExists(BASELINE))) {
    log.warn(`--reset-baseline: deleting ${BASELINE}`);
    await $`lume delete ${BASELINE} --force`.nothrow();
  }
  if (!(await vmExists(BASELINE))) {
    log.step(`pulling macos-sequoia-vanilla-sparse:latest → ${BASELINE}`);
    await $`lume pull macos-sequoia-vanilla-sparse:latest ${BASELINE}`;
  }
  log.ok(`baseline ready`);
}

async function cloneFromBaseline() {
  log.step(`clone ${BASELINE} → ${CLONE}`);
  if (await vmExists(CLONE)) {
    log.warn(`${CLONE} already exists, deleting`);
    await $`lume stop ${CLONE}`.nothrow();
    await $`lume delete ${CLONE} --force`;
  }
  await $`lume clone ${BASELINE} ${CLONE}`;
  log.ok(`cloned`);
}

async function startVm() {
  log.step(`start ${CLONE}`);
  // `lume run` is foreground/blocking; spawn detached.
  Bun.spawn(["lume", "run", CLONE, "--no-display"], {
    stdout: "ignore", stderr: "ignore", stdin: "ignore",
  });
  // Wait until SSH responds.
  const deadline = Date.now() + 5 * 60_000;
  while (Date.now() < deadline) {
    const r = await $`lume ssh ${CLONE} --timeout 10 -- echo ready`.nothrow().quiet();
    if (r.exitCode === 0 && r.text().includes("ready")) { log.ok("ssh up"); return; }
    await Bun.sleep(5000);
    process.stdout.write(".");
  }
  throw new Error(`VM ${CLONE} did not become ssh-able within 5 min`);
}

async function ssh(cmd: string): Promise<string> {
  // Stream output as it arrives so a hung step is visible, and surface stdout
  // on failure (bun's $ would otherwise swallow it).
  const proc = Bun.spawn(["lume", "ssh", CLONE, "--timeout", "1800", "--", "bash", "-lc", cmd], {
    stdout: "pipe", stderr: "pipe",
  });
  const out: string[] = [];
  const decoder = new TextDecoder();
  const pipe = async (stream: ReadableStream<Uint8Array>, prefix: string) => {
    for await (const chunk of stream) {
      const text = decoder.decode(chunk);
      out.push(text);
      process.stdout.write(text.split("\n").map((l) => l ? `${prefix}${l}` : l).join("\n"));
    }
  };
  await Promise.all([
    pipe(proc.stdout, `  ${C.dim}|${C.reset} `),
    pipe(proc.stderr, `  ${C.dim}|${C.reset} `),
  ]);
  const code = await proc.exited;
  if (code !== 0) throw new Error(`ssh command exited ${code}`);
  return out.join("");
}

async function sshCheck(label: string, cmd: string) {
  const r = await $`lume ssh ${CLONE} --timeout 30 -- bash -lc ${cmd}`.nothrow().quiet();
  if (r.exitCode === 0) log.ok(label);
  else { log.err(`${label} — exit ${r.exitCode}`); throw new Error(`check failed: ${label}`); }
}

// --- bootstrap script (runs inside the VM) -------------------------------------

// The vanilla macOS VM has no Xcode CLT, no brew, no git, no mise. Homebrew's
// installer (with NONINTERACTIVE=1) installs CLT for us, but requires
// passwordless sudo — so we configure it up-front. This is fine in a throwaway
// test VM; real users hit the usual interactive sudo prompt.
const BOOTSTRAP = String.raw`
set -euo pipefail

echo "==> enable passwordless sudo for lume (test-only)"
echo lume | sudo -S sh -c 'echo "lume ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/lume-test && chmod 440 /etc/sudoers.d/lume-test'

echo "==> install Homebrew (this also installs Xcode CLT)"
if ! command -v brew >/dev/null; then
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if   [ -x /opt/homebrew/bin/brew ];               then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ];                  then eval "$(/usr/local/bin/brew shellenv)"
fi

echo "==> brew install mise git"
brew install mise git

echo "==> clone dotfiles (${BRANCH})"
rm -rf "$HOME/dotfiles"
git clone -b ${BRANCH} ${REPO} "$HOME/dotfiles"
cd "$HOME/dotfiles"

echo "==> mise install (bun)"
mise trust
mise install
eval "$(mise activate bash)"

echo "==> bun install"
bun install

echo "==> bun run setup"
bun run setup
`;

// --- verification --------------------------------------------------------------

async function verify() {
  log.step("verify");
  await sshCheck("~/.zshrc is symlink",        "test -L $HOME/.zshrc");
  await sshCheck("~/.zshrc points into dotfiles",
                                                "readlink $HOME/.zshrc | grep -q dotfiles/home/.zshrc");
  await sshCheck("starship installed",         "command -v starship");
  await sshCheck("zellij installed",           "command -v zellij");
  await sshCheck("mise installed",             "command -v mise");
  await sshCheck("bun on PATH",                "command -v bun");
  await sshCheck("oh-my-zsh installed",        "test -d $HOME/.oh-my-zsh");
  await sshCheck("zsh-autosuggestions plugin", "test -d $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions");
  await sshCheck("ghostty config symlinked",   "test -L $HOME/.config/ghostty/config");
  await sshCheck("starship.toml symlinked",    "test -L $HOME/.config/starship.toml");
}

// --- main ----------------------------------------------------------------------

async function teardown() {
  if (KEEP) { log.warn(`--keep set; VM ${CLONE} left running`); return; }
  log.step(`teardown ${CLONE}`);
  await $`lume stop ${CLONE}`.nothrow();
  await $`lume delete ${CLONE} --force`.nothrow();
  log.ok("clone removed");
}

async function main() {
  const start = Date.now();
  try {
    await ensureBaseline();
    await cloneFromBaseline();
    await startVm();

    log.step("bootstrap (inside VM)");
    await ssh(BOOTSTRAP);

    await verify();

    const dur = ((Date.now() - start) / 1000).toFixed(1);
    log.ok(`PASS — ${dur}s`);
  } catch (e) {
    log.err(String(e));
    log.warn(`VM ${CLONE} left running for inspection: \`lume ssh ${CLONE}\``);
    process.exitCode = 1;
    return; // skip teardown so user can debug
  }
  await teardown();
}

main();
