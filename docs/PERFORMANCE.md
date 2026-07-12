# Performance notes

The parser is byte-oriented and builds an in-memory immutable manual graph. It
does not create a persistent index in v1.

The deterministic synthetic benchmark generates 5,000 nodes (about 418 KiB)
and parses the same input five times:

```text
nodes=5000 iterations=5 input_bytes=417805 elapsed_ms=178.988
```

This was measured on the initial macOS development host after replacing an
O(nodes × bytes) line-number pass with a binary-search newline index. The
same release audit measured 217.301 ms; these numbers are orientation, not a
cross-machine CI threshold.

Global search parses one registered manual at a time and caches it only for the
current invocation. A persistent `XDG_CACHE_HOME` cache remains intentionally
deferred: current local scans are fast enough to avoid a cache invalidation and
stable-schema burden in v1.

Safety limits:

- compressed input and aggregate expanded split-manual output are bounded;
- regex evaluation uses RE2;
- root result collections are capped without injecting sentinel values into
  typed nested collections;
- `--all-results` is an explicit opt-out.
