"""Case-preserving prefix completion with frequency and recency scores."""

from array import array
from bisect import bisect_left
from collections import Counter
import heapq
import time

import corpus


class WordIndex:
    def __init__(self, occurrences=None, *, dictionary=None, now=None, alphabetical=False):
        if occurrences is None:
            occurrences = corpus.iter_corpus()
        if dictionary is None:
            dictionary = corpus.dictionary_words()
        if now is None:
            now = time.time()
        scores = {}
        casings = {}
        for word, timestamp in occurrences:
            key = word.lower()
            if key not in scores:
                scores[key] = 0.0
                casings[key] = Counter()
            if not alphabetical:
                age_days = (now - timestamp) / 86400.0
                scores[key] += 0.5 ** (age_days / 30.0)
            casings[key][word] += 1
        # Dictionary-only words form a second tier below every word Sasha used;
        # within it, shorter words rank first. A lowercase headword wins over a capitalised one.
        extra = {}
        for word in dictionary:
            key = word.lower()
            if key not in scores and (key not in extra or word == key):
                extra[key] = word
        self.words = sorted((*scores, *extra))
        self.scores = [scores.get(word, 0.0) for word in self.words]
        self.personal = [word in scores for word in self.words]
        self.casings = [
            min(casings[word], key=lambda form: (-casings[word][form], form))
            if word in casings else extra[word]
            for word in self.words
        ]
        self.alphabetical = alphabetical
        if alphabetical:
            return

        # A tournament tree stores the best rank in each sorted-word range.
        # Queries split only ranges that can contribute a top-k result.
        self.order = sorted(
            range(len(self.words)),
            key=lambda i: (not self.personal[i], -self.scores[i], len(self.words[i]), self.words[i]),
        )
        self.size = 1 << max(0, (len(self.words) - 1).bit_length())
        self.sentinel = len(self.words)
        self.tree = array("q", [self.sentinel]) * (2 * self.size)
        for rank, i in enumerate(self.order):
            self.tree[self.size + i] = rank
        for node in range(self.size - 1, 0, -1):
            self.tree[node] = min(self.tree[node * 2], self.tree[node * 2 + 1])

    def complete(self, prefix, k=5):
        if not prefix or k <= 0:
            return []
        key = prefix.lower()
        lo = bisect_left(self.words, key)
        hi = bisect_left(self.words, key + "\uffff", lo)
        if lo == hi:
            return []
        capitalize = prefix[0].isupper()
        results = []
        if self.alphabetical:
            for i in range(lo, hi):
                if self.words[i] != key:
                    word = self.casings[i]
                    results.append(word[0].upper() + word[1:] if capitalize else word)
                    if len(results) == k:
                        break
            return results

        tree = self.tree
        left, right = lo + self.size, hi + self.size
        heap = []
        while left < right:
            if left & 1:
                heap.append((tree[left], left))
                left += 1
            if right & 1:
                right -= 1
                heap.append((tree[right], right))
            left //= 2
            right //= 2
        heapq.heapify(heap)
        while heap and len(results) < k:
            rank, node = heapq.heappop(heap)
            if rank == self.sentinel:
                continue
            if node < self.size:
                child = node * 2
                heapq.heappush(heap, (tree[child], child))
                heapq.heappush(heap, (tree[child + 1], child + 1))
            else:
                i = self.order[rank]
                if self.words[i] != key:
                    word = self.casings[i]
                    results.append(word[0].upper() + word[1:] if capitalize else word)
        return results


class AlphabeticalIndex(WordIndex):
    def __init__(self, occurrences=None, *, dictionary=None, now=None):
        super().__init__(occurrences, dictionary=dictionary, now=now, alphabetical=True)


Index = WordIndex
_default = None


def complete(prefix, k=5):
    """Build the default corpus lazily, then reuse its in-memory index."""
    global _default
    if _default is None:
        _default = WordIndex()
    return _default.complete(prefix, k)
