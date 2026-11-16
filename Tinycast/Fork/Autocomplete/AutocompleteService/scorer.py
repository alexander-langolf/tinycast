"""Bounded Kneser-Ney trigram ranking shared by both autocomplete clients."""
from bisect import bisect_left
from collections import defaultdict
import heapq
import re

BOS = "<s>"
SEG = re.compile(r'[.!?\n:;()\[\]{}"`|<>/\\=*#_~@$%^&+,0-9]+')
TOK = re.compile(r"[A-Za-z][A-Za-z'-]*")
WORD = re.compile(r"[a-z][a-z'-]{0,29}\Z")


def sentences(text):
    for segment in SEG.split(text):
        words = [word.strip("'-").lower() for word in TOK.findall(segment)]
        words = [word for word in words if word and len(word) <= 30]
        if words:
            yield words


class Followers:
    """Exact count leaders per prefix, refreshed incrementally as counts increase."""
    def __init__(self, counts, limit=40):
        self.counts = counts
        self.limit = limit
        self.words = sorted(counts)
        self.cache = {}

    def bumped(self, word):
        position = bisect_left(self.words, word)
        if position == len(self.words) or self.words[position] != word:
            self.words.insert(position, word)
        for prefix in ("", word[:1], word[:2]):
            if prefix not in self.cache:
                continue
            leaders = self.cache[prefix]
            if word in leaders:
                leaders.remove(word)
            leaders.append(word)
            leaders.sort(key=lambda item: (-self.counts[item], item))
            del leaders[self.limit:]

    def top(self, prefix, count):
        if len(prefix) <= 2:
            if prefix not in self.cache:
                self.cache[prefix] = self._top(prefix, self.limit)
            return self.cache[prefix][:count]
        return self._top(prefix, count)

    def _top(self, prefix, count):
        lo = bisect_left(self.words, prefix)
        hi = bisect_left(self.words, prefix + "\uffff", lo)
        return heapq.nsmallest(count, self.words[lo:hi],
                               key=lambda word: (-self.counts[word], word))


class Scorer:
    D = 0.75

    def __init__(self, training=(), online=True, cache_lambda=0.1, cache_half_words=2000):
        self.online = online
        self.lam = cache_lambda
        self.chalf = cache_half_words
        self.c3 = defaultdict(lambda: defaultdict(int))
        self.c3tot = defaultdict(int)
        self.cc2 = defaultdict(lambda: defaultdict(int))
        self.cc2tot = defaultdict(int)
        self.cc1 = defaultdict(int)
        self.cc1tot = 0
        self.trigram_indexes = {}
        self.bigram_indexes = {}
        self.cache = defaultdict(float)
        self.cache_t = 0
        self.cache_total = 0.0
        self.cache_index = Followers(self.cache, 200)
        for sentence in training:
            u, v = BOS, BOS
            for word in sentence:
                self._add(u, v, word)
                u, v = v, word
        self.unigram_index = Followers(self.cc1)

    def _add(self, u, v, word, count=1):
        followers = self.c3[(u, v)]
        if word not in followers:
            lower = self.cc2[v]
            if word not in lower:
                self.cc1[word] += 1
                self.cc1tot += 1
                if hasattr(self, "unigram_index"):
                    self.unigram_index.bumped(word)
            lower[word] += 1
            self.cc2tot[v] += 1
            if v in self.bigram_indexes:
                self.bigram_indexes[v].bumped(word)
        followers[word] += count
        self.c3tot[(u, v)] += count
        if (u, v) in self.trigram_indexes:
            self.trigram_indexes[(u, v)].bumped(word)

    def p1(self, word):
        return self.cc1.get(word, 0) / self.cc1tot if self.cc1tot else 0

    def p2(self, v, word):
        total = self.cc2tot.get(v, 0)
        if not total:
            return self.p1(word)
        followers = self.cc2[v]
        return (max(followers.get(word, 0) - self.D, 0) / total
                + self.D * len(followers) / total * self.p1(word))

    def prob(self, u, v, word):
        total = self.c3tot.get((u, v), 0)
        if total:
            followers = self.c3[(u, v)]
            probability = (max(followers.get(word, 0) - self.D, 0) / total
                           + self.D * len(followers) / total * self.p2(v, word))
        else:
            probability = self.p2(v, word)
        cached = self.cache.get(word, 0) / self.cache_total if self.cache_total else 0
        return (1 - self.lam) * probability + self.lam * cached

    def _leaders(self, counts, indexes, context, prefix):
        followers = counts.get(context)
        if not followers:
            return ()
        if len(followers) <= 40:
            return (word for word in followers if word.startswith(prefix))
        if context not in indexes:
            indexes[context] = Followers(followers)
        return indexes[context].top(prefix, 40)

    def predict(self, context, prefix, k=5):
        u, v = context
        candidates = set(self._leaders(self.c3, self.trigram_indexes, (u, v), prefix))
        candidates.update(self._leaders(self.cc2, self.bigram_indexes, v, prefix))
        candidates.update(self.unigram_index.top(prefix, 20))
        if self.lam:
            candidates.update(word for word in self.cache_index.top("", 200)
                              if word.startswith(prefix))
        candidates.discard(prefix)
        if not candidates:
            return [], 0.0
        scored = heapq.nlargest(30, ((self.prob(u, v, word), word) for word in candidates))
        total = sum(score for score, _ in scored) or 1
        return [word for _, word in scored[:k]], scored[0][0] / total

    def update(self, context, word, timestamp=0):
        if not self.online:
            return
        self._add(*context, word)
        if not self.lam:
            return
        self.cache_t += 1
        growth = 2 ** (self.cache_t / self.chalf)
        self.cache[word] += growth
        self.cache_total += growth
        self.cache_index.bumped(word)
        if self.cache_t >= self.chalf * 20:
            scale = 2 ** (-self.cache_t / self.chalf)
            for item in self.cache:
                self.cache[item] *= scale
            self.cache_total *= scale
            self.cache_t = 0
