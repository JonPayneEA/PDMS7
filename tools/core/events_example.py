"""Find rainfall-runoff events with the PDM core from Python, using only the standard library.

Build the shared library first, from the package root (see tools/core/README.md):

    gcc -std=c99 -O2 -shared -fPIC src/pdm_core.c -lm -o libpdmcore.so

then run:

    python3 tools/core/events_example.py libpdmcore.so inst/golden

It finds the events of the golden hourly record and checks them against the expected file,
so it doubles as a test that the Python binding is right.
"""

import csv
import ctypes
import math
import sys
from pathlib import Path

lib = ctypes.CDLL(sys.argv[1] if len(sys.argv) > 1 else "./libpdmcore.so")
golden = Path(sys.argv[2] if len(sys.argv) > 2 else "inst/golden")

c_double_p = ctypes.POINTER(ctypes.c_double)
c_int64_p = ctypes.POINTER(ctypes.c_int64)
lib.pdm_find_events.restype = ctypes.c_int32
lib.pdm_find_events.argtypes = [
    c_double_p, c_double_p, ctypes.c_int64, ctypes.c_double, ctypes.c_double, ctypes.c_int32,
    ctypes.POINTER(ctypes.c_int32), c_double_p, ctypes.c_int64, c_int64_p, c_int64_p,
    ctypes.c_char_p, ctypes.c_int64,
]
lib.pdm_event_scores.restype = ctypes.c_int32
lib.pdm_event_scores.argtypes = [
    c_double_p, c_double_p, ctypes.c_int64, ctypes.c_double, c_int64_p, ctypes.c_int64,
    c_double_p, ctypes.c_char_p, ctypes.c_int64,
]


def read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


case = next(row for row in read(golden / "events_cases.csv") if row["case"] == "hourly")
series = read(golden / "hourly_events_series.csv")
n = len(series)
rain = (ctypes.c_double * n)(*[float(r["rain_mm"]) for r in series])
flow = (ctypes.c_double * n)(*[float(r["flow_m3s"]) for r in series])
simulated = (ctypes.c_double * n)(*[float(r["simulated_m3s"]) for r in series])

capacity = n // 2 + 1
events = (ctypes.c_int64 * (4 * capacity))()
count = ctypes.c_int64(0)
steps = ctypes.c_int32(0)
message = ctypes.create_string_buffer(256)
code = lib.pdm_find_events(rain, flow, n, float(case["dt"]), float(case["rain_min"]),
                           int(float(case["h_max"])), ctypes.byref(steps), None, capacity,
                           ctypes.byref(count), events, message, len(message))
if code != 0:
    sys.exit("pdm_find_events failed: " + message.value.decode())

scores = (ctypes.c_double * (6 * count.value))()
code = lib.pdm_event_scores(simulated, flow, n, float(case["dt"]), events, count.value, scores,
                            message, len(message))
if code != 0:
    sys.exit("pdm_event_scores failed: " + message.value.decode())

expected = read(golden / "hourly_events_expected.csv")
names = ["rain_start", "rain_end", "flow_start", "flow_end"]
same = count.value == len(expected) and all(
    events[4 * i + j] == int(float(expected[i][names[j]]))
    for i in range(count.value) for j in range(4))
worst = max((abs(scores[6 * i + 2] - float(expected[i]["peak_error"]))
             for i in range(count.value)), default=0.0)
print(f"{count.value} events, response time {steps.value} h; "
      f"windows match the golden file: {same}; largest peak-error difference {worst:.1e}")
print("first event (0-based rows): rain", events[0], "to", events[1], "| flow", events[2], "to",
      events[3], f"| peak error {scores[2]:+.1%}")
sys.exit(0 if same and worst <= 1e-12 and not math.isnan(worst) else 1)
