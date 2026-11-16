"""Read local text without logging source content."""

import os
from pathlib import Path
import re
import zlib

VAULT = Path.home() / "LangolfVault"
HISTORY = Path.home() / ".zsh_history"
EXCLUDED = frozenset({".git", ".obsidian", "node_modules"})
TOKEN = re.compile(r"[A-Za-z0-9'-]+")
WORD = re.compile(r"[A-Za-z][A-Za-z'-]*[A-Za-z]\Z")
EXTENDED = re.compile(r"^: (\d+):0;(.*)")


def words(text):
    """Yield valid words, rejecting an entire token containing a digit."""
    for match in TOKEN.finditer(text):
        token = match.group().strip("'-")
        if 3 <= len(token) <= 30 and WORD.fullmatch(token):
            yield token


def note_paths(vault=VAULT):
    """Yield Markdown paths without following directory symlinks."""
    vault = Path(vault)
    def walk_error(error):
        raise OSError("A corpus directory could not be read") from None

    for directory, subdirs, files in os.walk(vault, onerror=walk_error):
        subdirs[:] = sorted(name for name in subdirs if name not in EXCLUDED)
        for name in sorted(files):
            if name.endswith(".md"):
                yield Path(directory) / name


def note_words(path):
    path = Path(path)
    timestamp = path.stat().st_mtime
    with path.open(encoding="utf-8", errors="replace") as source:
        for line in source:
            for word in words(line):
                yield word, timestamp


def history_words(history=HISTORY):
    try:
        source = Path(history).open(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return
    with source:
        for line in source:
            match = EXTENDED.match(line)
            if match:
                timestamp = int(match[1])
                for word in words(match[2]):
                    yield word, timestamp


DICTIONARIES = Path(
    "/System/Library/AssetsV2/com_apple_MobileAsset_DictionaryServices_dictionary3macOS")
OXFORD = ("Oxford Dictionary of English", "Oxford Thesaurus of English")
TITLE = re.compile(r'd:title="([^"]+)"')
INFLECTION = re.compile(r'class="inf"[^>]*>([^<]+)<')


def dictionary_words(names=OXFORD, root=DICTIONARIES):
    """Yield headwords and inflected forms from the macOS Oxford dictionaries.

    Body.data is a run of zlib streams, each holding XML entries.
    """
    for name in names:
        for body in root.glob(f"*/AssetData/{name}.dictionary/Contents/Resources/Body.data"):
            data = body.read_bytes()
            start = data.find(b"\x78\xda")
            while start != -1:
                stream = zlib.decompressobj()
                try:
                    xml = stream.decompress(data[start:]).decode("utf-8", errors="replace")
                except zlib.error:
                    start = data.find(b"\x78\xda", start + 1)
                    continue
                for match in (*TITLE.findall(xml), *INFLECTION.findall(xml)):
                    word = match.strip()
                    if 3 <= len(word) <= 30 and WORD.fullmatch(word):
                        yield word
                start = data.find(b"\x78\xda", len(data) - len(stream.unused_data))


def iter_corpus(vault=VAULT, history=HISTORY, notes=None):
    """Yield (word, timestamp) pairs; notes can restrict the training set."""
    for path in note_paths(vault) if notes is None else notes:
        yield from note_words(path)
    if history is not None:
        yield from history_words(history)
