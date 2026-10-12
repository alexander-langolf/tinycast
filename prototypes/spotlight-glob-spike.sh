#!/bin/bash
# PROTOTYPE: compare Spotlight substring vs subsequence-glob name queries. Read-only.
terms=(fork forktypo invmarch ariel pkg agenda sigils stardust tc)
for t in "${terms[@]}"; do
  glob=$(echo "$t" | sed 's/./*&/g')*
  for q in "kMDItemFSName == \"*$t*\"cd" "kMDItemFSName == \"$glob\"cd"; do
    start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    n=$(mdfind -onlyin "$HOME" "$q" | head -1000 | wc -l | tr -d ' ')
    end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
    printf "%-10s %-40s %5s results %6.0f ms\n" "$t" "$q" "$n" "$(echo "($end-$start)*1000" | bc)"
  done
done
