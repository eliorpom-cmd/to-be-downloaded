#!/usr/bin/env python3
"""
Times yt-dlp's EJS challenge solver on several JavaScript runtimes.

Research tool, not part of the build. It answers one question: how much slower
is a small runtime (QuickJS-NG) than Deno/Node/Bun at the work yt-dlp hands it?

What it runs is the exact script yt-dlp builds (lib.min.js, then
`Object.assign(globalThis, lib)`, then core.min.js, then `jsc({...})`), taken
from the `yt-dlp-ejs` wheel on PyPI. The player it feeds is whatever JS file
you pass. With a real YouTube player (base.js, ~2.7 MB) this is the real
first-run cost; with any other large minified file (e.g. @babel/standalone's
babel.min.js, 3.1 MB) the solver parses it with meriyah then stops at
"unexpected structure", so the number is a lower bound dominated by parsing.

Usage:
  scripts/research/js-runtime-bench.py PLAYER.js name=/path/to/runtime ...
  e.g. deno=/opt/homebrew/bin/deno qjs=./qjs node=/usr/local/bin/node

Runtime names: deno, node, bun, qjs (QuickJS or QuickJS-NG).
Needs `pip` on PATH to fetch the yt-dlp-ejs wheel (no install, download only).
"""
import glob
import json
import os
import subprocess
import sys
import tempfile
import time
import zipfile

RUNS = 3


def ejs_scripts(workdir):
    # Download only: nothing is installed into the running Python.
    subprocess.run(
        [sys.executable, '-m', 'pip', 'download', '--no-deps', '-q', '-d', workdir, 'yt-dlp-ejs'],
        check=True)
    wheel = glob.glob(os.path.join(workdir, 'yt_dlp_ejs-*.whl'))[0]
    with zipfile.ZipFile(wheel) as z:
        lib = z.read('yt_dlp_ejs/yt/solver/lib.min.js').decode()
        core = z.read('yt_dlp_ejs/yt/solver/core.min.js').decode()
    return os.path.basename(wheel), lib, core


def build_script(lib, core, player):
    # Same assembly as yt_dlp/extractor/youtube/jsc/_builtin/ejs.py, plus a timer
    # around the jsc() call so process start-up is reported separately.
    return (
        lib + '\nObject.assign(globalThis, lib);\n' + core + '\n'
        + 'const __log = typeof console !== "undefined" ? console.log : print;\n'
        + f'const __player = {json.dumps(player)};\n'
        + 'const __t0 = Date.now(); let __r;\n'
        + 'try { __r = jsc({type: "player", player: __player, output_preprocessed: true,'
        + ' requests: [{type: "n", challenges: ["abc"]}, {type: "sig", challenges: ["abc"]}]}); }'
        + ' catch (e) { __r = {type: "throw", error: String(e)}; }\n'
        + '__log(JSON.stringify({solver_ms: Date.now() - __t0,'
        + ' result: JSON.stringify(__r).slice(0, 120)}));\n')


def command(name, path, script):
    if name == 'deno':
        # yt-dlp runs deno with no permissions at all; --no-prompt keeps it silent.
        return [path, 'run', '--no-prompt', script]
    if name == 'qjs':
        # yt-dlp passes --script too (QuickJS cannot run a file from stdin).
        return [path, '--script', script]
    return [path, script]


def run(cmd):
    start = time.time()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = proc.stdout.read()
    _, _, usage = os.wait4(proc.pid, 0)
    # ru_maxrss is bytes on macOS, kilobytes on Linux.
    rss = usage.ru_maxrss / (1 << 20 if sys.platform == 'darwin' else 1 << 10)
    return time.time() - start, rss, out.decode(errors='replace').strip()[-200:]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    player = open(sys.argv[1], encoding='utf-8').read()
    runtimes = [arg.split('=', 1) for arg in sys.argv[2:]]
    with tempfile.TemporaryDirectory() as tmp:
        wheel, lib, core = ejs_scripts(tmp)
        script = os.path.join(tmp, 'bench.js')
        with open(script, 'w', encoding='utf-8') as f:
            f.write(build_script(lib, core, player))
        print(f'{wheel}, player {len(player) / 1e6:.2f} MB, platform {sys.platform}')
        for name, path in runtimes:
            for i in range(RUNS):
                wall, rss, out = run(command(name, path, script))
                print(f'{name:5} run{i + 1}  wall={wall:5.2f}s  maxrss={rss:4.0f}MB  {out}')


if __name__ == '__main__':
    main()
