#!/bin/zsh
# PROTOTYPE (throwaway) — question 1a: can a kitty session be the "stream" behind a Tinycast terminal instance?
# Starts a PRIVATE, minimized kitty instance on its own socket (never touches Sasha's running kitty),
# opens an interactive zsh tab in it, sends "pwd" + a ticking command, and mirrors output by polling
# `kitty @ get-text`. Prints per-call latency and time-to-first-output. Run: zsh spike-kitty-remote.zsh
zmodload zsh/datetime
SOCK=/private/tmp/claude-507/tc-kitty-proto.sock
rm -f $SOCK
ms() { printf '%.1f' $(( (EPOCHREALTIME - $1) * 1000 )) }

T=$EPOCHREALTIME
kitty -o allow_remote_control=yes -o confirm_os_window_close=0 --listen-on unix:$SOCK \
  --start-as=minimized --title tc-proto -- zsh -f >/dev/null 2>&1 &
KPID=$!
until [[ -S $SOCK ]]; do sleep 0.02; done
echo "kitty instance cold start (socket ready): $(ms $T) ms"

K=(kitty @ --to unix:$SOCK)

# 1. interactive session in a new tab of the private instance
T=$EPOCHREALTIME
WID=$($K launch --type=tab --keep-focus --title job --cwd=$HOME zsh -i)
echo "kitty @ launch: $(ms $T) ms  -> window id $WID"

# 2. per-call cost of the mirror primitive
T=$EPOCHREALTIME; for i in {1..20}; do $K get-text --match id:$WID >/dev/null; done
echo "kitty @ get-text (CLI, avg of 20): $(( (EPOCHREALTIME - T) * 1000 / 20 )) ms"

# 3. send a command and poll until its output shows
sleep 1   # let .zshrc finish so the prompt is up
T=$EPOCHREALTIME
$K send-text --match id:$WID $'pwd; for i in 1 2 3; do echo tick $i; sleep 0.3; done\r'
polls=0; first=""
while true; do
  polls=$((polls+1))
  out=$($K get-text --match id:$WID --extent all)
  [[ -z $first && $out == *"$HOME"$'\n'* ]] && first=$(ms $T)
  [[ $out == *"tick 3"* ]] && break
  sleep 0.05
done
echo "send-text -> 'pwd' visible via polling: ${first} ms; 'tick 3' seen after $(ms $T) ms, $polls polls"

# 4. same session keeps state: cd then pwd
$K send-text --match id:$WID $'cd /tmp && echo CWD=$PWD\r'
sleep 0.4
echo "--- last lines of mirrored screen (plain text; --ansi gives SGR escapes) ---"
$K get-text --match id:$WID | grep -v '^\s*$' | tail -6
echo "--- ls (what an 'open in kitty' handoff would focus) ---"
$K ls | python3 -c 'import json,sys; [print(" tab", t["title"], [w["id"] for w in t["windows"]], "cwd", t["windows"][0]["cwd"]) for o in json.load(sys.stdin) for t in o["tabs"]]'

$K close-window --match id:$WID >/dev/null 2>&1
kill $KPID 2>/dev/null; wait $KPID 2>/dev/null; rm -f $SOCK
