"""Private, local autocomplete service. Protocol errors never include source text."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import socket
import sqlite3
import stat
import subprocess
import sys
import time

import corpus
from index import WordIndex
from scorer import BOS, Scorer, WORD, sentences

DEFAULT_BUNDLE = "com.tinycast.app.dev"
MAX_REQUEST = 32768


def support(bundle):
    if bundle not in ("com.tinycast.app", "com.tinycast.app.dev"):
        raise ValueError("Invalid channel")
    return Path.home() / "Library/Application Support" / bundle


def socket_path(bundle):
    return str(support(bundle) / "ac.sock")


def training():
    for path in corpus.note_paths():
        yield from sentences(path.read_text(encoding="utf-8", errors="replace"))
    try:
        with corpus.HISTORY.open(encoding="utf-8", errors="replace") as source:
            for line in source:
                match = corpus.EXTENDED.match(line)
                if match:
                    yield from sentences(match[2])
    except FileNotFoundError:
        pass
    for name, field in ((".claude/history.jsonl", "display"), (".codex/history.jsonl", "text")):
        try:
            with (Path.home() / name).open(encoding="utf-8", errors="replace") as source:
                for line in source:
                    try:
                        text = json.loads(line).get(field, "")
                        if isinstance(text, str):
                            yield from sentences(text)
                    except (ValueError, AttributeError):
                        continue
        except FileNotFoundError:
            pass


class LearningStore:
    def __init__(self, bundle):
        directory = support(bundle) / "Autocomplete"
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(directory, 0o700)
        path = directory / "learned.sqlite3"
        descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        os.fchmod(descriptor, 0o600)
        os.close(descriptor)
        self.db = sqlite3.connect(path)
        self.db.execute("CREATE TABLE IF NOT EXISTS learned "
                        "(id INTEGER PRIMARY KEY, client TEXT, event TEXT, u TEXT, v TEXT, word TEXT, "
                        "UNIQUE(client, event))")
        self.db.commit()

    def load(self, model):
        for u, v, word in self.db.execute("SELECT u, v, word FROM learned ORDER BY id"):
            model.update((u, v), word)

    def learn(self, model, context, word, client, event):
        cursor = self.db.execute("INSERT OR IGNORE INTO learned(client,event,u,v,word) VALUES(?,?,?,?,?)",
                                 (client, event, *context, word))
        self.db.commit()
        if cursor.rowcount:
            model.update(context, word)


def validated(request):
    context = request.get("context", [BOS, BOS])
    if (not isinstance(context, list) or len(context) != 2
            or any(not isinstance(word, str) or (word != BOS and not WORD.fullmatch(word))
                   for word in context)):
        raise ValueError("Invalid context")
    prefix = request.get("prefix", "")
    if not isinstance(prefix, str) or len(prefix) > 30 or (prefix and not WORD.fullmatch(prefix.lower())):
        raise ValueError("Invalid prefix")
    return context, prefix


class Engine:
    def __init__(self, model, dictionary, store):
        self.model, self.dictionary, self.store = model, dictionary, store

    def handle(self, request):
        operation = request.get("op")
        if operation == "health":
            response = {"ok": True, "protocol": 1}
        else:
            context, prefix = validated(request)
            if operation == "learn":
                word = request.get("word")
                client, event = request.get("client"), request.get("event")
                if (not isinstance(word, str) or not WORD.fullmatch(word)
                        or not isinstance(client, str) or not 1 <= len(client) <= 64
                        or not isinstance(event, str) or not 1 <= len(event) <= 64):
                    raise ValueError("Invalid learning event")
                self.store.learn(self.model, context, word, client, event)
                response = {"ok": True}
            elif operation == "predict":
                start = time.perf_counter_ns()
                words, confidence = self.model.predict(context, prefix.lower())
                known = set(words)
                words += [word for word in self.dictionary.complete(prefix)
                          if word.lower() not in known][:5 - len(words)]
                if prefix[:1].isupper():
                    words = [word[:1].upper() + word[1:] for word in words]
                response = {"ok": True, "words": words, "confidence": confidence,
                            "lookup_ms": (time.perf_counter_ns() - start) / 1e6}
            else:
                raise ValueError("Invalid operation")
        return response


def serve(bundle):
    os.umask(0o077)
    root = support(bundle)
    root.mkdir(parents=True, exist_ok=True)
    lock = os.open(root / "ac.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(lock)
        return 0
    path = socket_path(bundle)
    if os.path.lexists(path):
        info = os.lstat(path)
        if info.st_uid != os.getuid() or not stat.S_ISSOCK(info.st_mode):
            raise ValueError("Unsafe endpoint")
        os.unlink(path)
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(path)
    os.chmod(path, 0o600)
    listener.listen(8)
    listener.settimeout(1)
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    store = None
    try:
        model = Scorer(training())
        dictionary = WordIndex((), dictionary=corpus.dictionary_words())
        store = LearningStore(bundle)
        store.load(model)
        engine = Engine(model, dictionary, store)
        while running:
            try:
                connection, _ = listener.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(1)
                try:
                    with connection.makefile("rb") as stream:
                        line = stream.readline(MAX_REQUEST + 1)
                    if len(line) > MAX_REQUEST or not line.endswith(b"\n"):
                        raise ValueError("Invalid frame")
                    request = json.loads(line)
                    if not isinstance(request, dict):
                        raise ValueError("Invalid request")
                    response = engine.handle(request)
                    connection.sendall(json.dumps(response).encode() + b"\n")
                except (OSError, ValueError, TypeError, sqlite3.Error):
                    try:
                        connection.sendall(b'{"ok":false}\n')
                    except OSError:
                        pass
    finally:
        listener.close()
        if store:
            store.db.close()
        os.unlink(path)
        os.close(lock)
    return 0


def socket_request(path, request, timeout=0.75):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(timeout)
        connection.connect(path)
        connection.sendall(json.dumps(request).encode() + b"\n")
        with connection.makefile("rb") as stream:
            response = stream.readline(MAX_REQUEST + 1)
        if len(response) > MAX_REQUEST:
            raise ValueError("Invalid response")
        result = json.loads(response)
        if not result.get("ok"):
            raise ValueError("Autocomplete request failed")
        return result


class Client:
    def __init__(self, bundle=DEFAULT_BUNDLE):
        self.bundle = bundle
        self.child = None

    def ensure(self):
        root = support(self.bundle)
        root.mkdir(parents=True, exist_ok=True)
        # The starter lock spans readiness, so simultaneous clients launch only one child.
        lock = os.open(root / "ac.start", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            try:
                if self.request({"op": "health"})["ok"]:
                    return
            except (OSError, ValueError, KeyError):
                pass
            if self.child is None or self.child.poll() is not None:
                self.child = subprocess.Popen(
                    [sys.executable, "-B", str(Path(__file__).resolve()), "--serve", "--bundle-id", self.bundle],
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True)
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                try:
                    if self.request({"op": "health"}, timeout=0.25).get("ok"):
                        return
                except (OSError, ValueError):
                    pass
                if self.child is not None and self.child.poll() is not None:
                    if self.child.returncode:
                        raise OSError("Autocomplete service exited")
                    self.child = None
                time.sleep(0.05)
            raise OSError("Autocomplete service unavailable")
        except BaseException:
            self.close()
            raise
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
            os.close(lock)

    def request(self, request, timeout=0.75):
        try:
            return socket_request(socket_path(self.bundle), request, timeout)
        except (OSError, ValueError):
            if request.get("op") == "health":
                raise
            self.ensure()
            return socket_request(socket_path(self.bundle), request, timeout)

    def close(self):
        # Only the creator owns the process; clients that reused it leave it running.
        if self.child and self.child.poll() is None:
            self.child.terminate()
            try:
                self.child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.child.kill()
                self.child.wait()
        self.child = None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE)
    parser.add_argument("--serve", action="store_true")
    args = parser.parse_args()
    if not args.serve:
        parser.error("The service requires --serve")
    return serve(args.bundle_id)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, sqlite3.Error):
        print("Autocomplete service unavailable.", file=sys.stderr)
        sys.exit(1)
