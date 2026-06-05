#!/usr/bin/env python3
"""
SLO Calculator — Queries Prometheus and calculates SLO compliance.
Author: Jenella Awo

Usage:
    python slo-calculator.py --prometheus-url http://localhost:9090 --window 30d
"""

import argparse
import json
import sys
from datetime import datetime, timedelta
from urllib.request import urlopen, Request
from urllib.parse import urlencode


# SLO definitions per service tier
SLO_TIERS = {
    "tier-1": {"availability": 99.95, "latency_p99_ms": 200},
    "tier-2": {"availability": 99.9, "latency_p99_ms": 500},
    "tier-3": {"availability": 99.5, "latency_p99_ms": 1000},
}


def query_prometheus(base_url, query, time=None):
    """Execute a PromQL instant query."""
    params = {"query": query}
    if time:
        params["time"] = time
    url = f"{base_url}/api/v1/query?{urlencode(params)}"
    req = Request(url, headers={"Accept": "application/json"})
    try:
        with urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
            if data["status"] == "success" and data["data"]["result"]:
                return float(data["data"]["result"][0]["value"][1])
    except Exception as e:
        print(f"  [WARN] Query failed: {e}")
    return None


def calculate_error_budget(slo_target, actual_availability, window_hours):
    """Calculate error budget remaining."""
    total_minutes = window_hours * 60
    allowed_downtime = total_minutes * (1 - slo_target / 100)
    actual_downtime = total_minutes * (1 - actual_availability / 100)
    remaining = max(0, allowed_downtime - actual_downtime)
    budget_pct = (remaining / allowed_downtime * 100) if allowed_downtime > 0 else 100
    return {
        "allowed_downtime_min": round(allowed_downtime, 2),
        "actual_downtime_min": round(actual_downtime, 2),
        "remaining_min": round(remaining, 2),
        "remaining_pct": round(budget_pct, 1),
    }


def main():
    parser = argparse.ArgumentParser(description="SLO Compliance Calculator")
    parser.add_argument("--prometheus-url", default="http://localhost:9090")
    parser.add_argument("--window", default="30d", help="Time window: 7d, 30d, 90d")
    args = parser.parse_args()

    # Parse window
    window_days = int(args.window.replace("d", ""))
    window_hours = window_days * 24

    print("=" * 70)
    print(f"  SLO Compliance Report — {args.window} Window")
    print(f"  Generated: {datetime.utcnow().isoformat()}Z")
    print(f"  Prometheus: {args.prometheus_url}")
    print("=" * 70)

    # Calculate availability SLI
    avail_query = f"""
        1 - (
          sum(rate(http_requests_total{{code=~"5.."}}[{args.window}]))
          / sum(rate(http_requests_total[{args.window}]))
        )
    """
    availability = query_prometheus(args.prometheus_url, avail_query)

    # Calculate latency SLI
    latency_query = f"""
        histogram_quantile(0.99,
          sum(rate(http_request_duration_seconds_bucket[{args.window}])) by (le)
        )
    """
    latency_p99 = query_prometheus(args.prometheus_url, latency_query)

    # Request rate
    rps_query = f"sum(rate(http_requests_total[{args.window}]))"
    rps = query_prometheus(args.prometheus_url, rps_query)

    print(f"\n{'Metric':<30} {'Value':<20} {'Status'}")
    print("-" * 70)

    if availability is not None:
        avail_pct = availability * 100
        slo_target = SLO_TIERS["tier-1"]["availability"]
        status = "PASS" if avail_pct >= slo_target else "FAIL"
        print(f"{'Availability':<30} {avail_pct:.4f}%{'':<12} [{status}] (target: {slo_target}%)")

        # Error budget
        budget = calculate_error_budget(slo_target, avail_pct, window_hours)
        print(f"{'Error Budget Remaining':<30} {budget['remaining_pct']}%{'':<12} ({budget['remaining_min']} min left)")
        print(f"{'Allowed Downtime':<30} {budget['allowed_downtime_min']} min")
        print(f"{'Actual Downtime':<30} {budget['actual_downtime_min']} min")
    else:
        print(f"{'Availability':<30} {'N/A':<20} [NO DATA]")

    if latency_p99 is not None:
        latency_ms = latency_p99 * 1000
        target_ms = SLO_TIERS["tier-1"]["latency_p99_ms"]
        status = "PASS" if latency_ms <= target_ms else "FAIL"
        print(f"{'Latency (P99)':<30} {latency_ms:.1f}ms{'':<13} [{status}] (target: {target_ms}ms)")
    else:
        print(f"{'Latency (P99)':<30} {'N/A':<20} [NO DATA]")

    if rps is not None:
        print(f"{'Request Rate':<30} {rps:.1f} req/s")

    print("\n" + "=" * 70)
    print("  SLO Tier Definitions")
    print("=" * 70)
    for tier, targets in SLO_TIERS.items():
        print(f"  {tier}: Availability >= {targets['availability']}%, P99 Latency <= {targets['latency_p99_ms']}ms")

    print()


if __name__ == "__main__":
    main()
