#!/usr/bin/env python3
# PROTOTYPE (throwaway) — question 1c (hybrid): a tmux session as the shared stream.
# The panel would read it push-based through tmux control mode (`tmux -C`, %output events);
# "open in kitty" = `kitty @ launch --type=tab tmux -L tcproto attach -t <id>` — the SAME live session.
# Uses a private tmux server (-L tcproto), never Sasha's default one. Run: python3 spike-tmux-control.py
import subprocess, time, re, os

L = ["tmux", "-L", "tcproto", "-f", "/dev/null"]
subprocess.run(L + ["kill-server"], stderr=subprocess.DEVNULL)
t0 = time.perf_counter()
subprocess.run(L + ["new-session", "-d", "-s", "inst1", "-x", "100", "-y", "24", "-c", os.path.expanduser("~"), "zsh -i"], check=True)
print(f"tmux new-session: {(time.perf_counter()-t0)*1000:.1f} ms")

ctl = subprocess.Popen(L + ["-C", "attach", "-t", "inst1"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
os.set_blocking(ctl.stdout.fileno(), False)
buf = b""

def drain(until, timeout=8.0):
    global buf
    start = time.perf_counter()
    while time.perf_counter() - start < timeout:
        try:
            chunk = ctl.stdout.read(65536)
        except BlockingIOError:
            chunk = None
        if chunk:
            buf += chunk
            # %output %<pane> <octal-escaped bytes>
            text = b"".join(re.findall(rb"^%output %\d+ (.*)$", buf, re.M)).decode("unicode_escape", "replace")
            if until in text:
                return (time.perf_counter() - start) * 1000, text
        time.sleep(0.001)
    return None, ""

time.sleep(1.0)  # let .zshrc settle
buf = b""
t = time.perf_counter()
subprocess.run(L + ["send-keys", "-t", "inst1", "-l", "pwd; for i in 1 2 3; do echo tick$i; sleep 0.3; done"])
subprocess.run(L + ["send-keys", "-t", "inst1", "Enter"])
ms_home, _ = drain(os.path.expanduser("~") + "\r\n")
print(f"send-keys -> pwd output pushed via %output: {ms_home:.1f} ms (incl. send-keys process spawn)")
ms_tick, text = drain("tick3")
print(f"tick3 pushed after +{ms_tick:.1f} ms (expected ~600 ms of sleeps)")
cwd = subprocess.run(L + ["display", "-p", "-t", "inst1", "#{pane_current_path}"], capture_output=True, text=True).stdout.strip()
print(f"pane_current_path = {cwd}  -> handoff: kitty @ launch --type=tab tmux -L tcproto attach -t inst1")
print("control-mode stream sample:", repr(text[-120:]))
ctl.stdin.write(b"detach\n"); ctl.wait(timeout=3)
subprocess.run(L + ["kill-server"])
