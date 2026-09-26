import pathlib
import subprocess
import sys

P = pathlib.Path("src/wb_api_client_core")
BUGS = {
    "S1-acquire-base-rate": (
        "ratelimit.py",
        "rate = self.effective_rate\n",
        "rate = self._base_rate\n",
    ),
    "S2-pause-shortened": (
        "ratelimit.py",
        "self._s.paused_until = max(self._s.paused_until, t + max(0.0, seconds))",
        "self._s.paused_until = t + max(0.0, seconds)",
    ),
    "S3-strict-gt-token": (
        "ratelimit.py",
        "                    if self._s.tokens >= 1.0:\n                        self._s.tokens -= 1.0\n                        return",
        "                    if self._s.tokens > 1.0:\n                        self._s.tokens -= 1.0\n                        return",
    ),
    "S4-post-window": (
        "ratelimit.py",
        "post = end - max(start, he)",
        "post = end - max(start, hs)",
    ),
    "S5-no-504": (
        "transport.py",
        "frozenset({429, 500, 502, 503, 504})",
        "frozenset({429, 500, 502, 503})",
    ),
    "S6-5xx-end": (
        "errors.py",
        "_HTTP_SERVER_ERROR_END = 600",
        "_HTTP_SERVER_ERROR_END = 599",
    ),
    "S7-auth-override": (
        "transport.py",
        'merged_headers.setdefault("Authorization", f"Bearer {token}")',
        'merged_headers["Authorization"] = f"Bearer {token}"',
    ),
    "S8-fullstats-rate": (
        "rates.py",
        '"fullstats": ("3/m", 1)',
        '"fullstats": ("3/s", 1)',
    ),
    "S9-pick-fallback": (
        "rates.py",
        'return scope_cfg.get(endpoint_group, scope_cfg.get("default", _FALLBACK_SPEC))',
        "return scope_cfg.get(endpoint_group) or _FALLBACK_SPEC",
    ),
    "S10-retry-after-naive-local": (
        "transport.py",
        "        dt = dt.replace(tzinfo=UTC)",
        "        dt = dt.astimezone()",
    ),
    "S11-attempts-off-by-one": (
        "transport.py",
        "stop=stop_after_attempt(self._retry.max_attempts)",
        "stop=stop_after_attempt(self._retry.max_attempts + 1)",
    ),
    "S12-429-no-bucket-for-503": (
        "transport.py",
        "resp.status_code == _HTTP_TOO_MANY_REQUESTS\n                    and retry_after",
        "resp.status_code in _RETRYABLE_STATUSES\n                    and retry_after",
    ),
    "S13-refill-before-pause": (
        "ratelimit.py",
        "            if t < self._s.paused_until:\n                return False\n            self._refill()",
        "            self._refill()\n            if t <= self._s.paused_until:\n                return False",
    ),
    "S14-validation-422": ("errors.py", "frozenset({400, 422})", "frozenset({400})"),
}
mode = sys.argv[1]
if mode == "probe":
    for k, (f, old, new) in BUGS.items():
        p = P / f
        src = p.read_text()
        assert src.count(old) == 1, k
        p.write_text(src.replace(old, new))
        r = subprocess.run(
            ["timeout", "15", "pytest", "-q", "-x", "-p", "no:cacheprovider"],
            capture_output=True,
            text=True,
        )
        p.write_text(src)
        print(
            k,
            "CAUGHT" if r.returncode else "survives",
            r.stdout.strip().splitlines()[-1],
        )
else:
    for k in sys.argv[2:]:
        f, old, new = BUGS[k]
        p = P / f
        src = p.read_text()
        assert src.count(old) == 1, k
        p.write_text(src.replace(old, new))
