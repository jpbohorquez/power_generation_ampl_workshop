# 🚩 No sections. Everything is mixed together.
var g_t {1..24} >= 0; # 🚩 Terrible, cryptic naming
param c {1..24};
var g_s {1..24} >= 0;
param r_s {1..24};
# 🚩 Hardcoded scalars mixed into declarations
param eff = 0.85;
var v {0..24} >= 0; # 🚩 Hardcoded time indices (1..24)
var q {1..24} >= 0;
var sp {1..24} >= 0;
param p {1..24};
maximize z: # 🚩 Meaningless objective name
sum{t in 1..24} (p[t] * (g_t[t] + g_s[t] + (eff*q[t])))
- sum{t in 1..24} (c[t]*g_t[t])
- sum{t in 1..24} (250*sp[t]); # 🚩 Hardcoded penalty inside objective
subject to c1 {t in 1..24}: g_t[t] <= 100; # 🚩 Unhelpful constraint names
subject to c2 {t in 1..24}: g_s[t] <= r_s[t];
subject to c3 {t in 1..24}:
# 🚩 Clunky index math (t-1) and hardcoded unit conversions
v[t] = v[t-1] + 0.0036 * (15 - q[t] - sp[t]);
# 🚩 Initial/Final conditions hardcoded as brittle constraints
subject to c4: v[0] = 0.7 * 500;
subject to c5: v[24] = 350;
# 🚩 Clunky subset bounding for ramps
subject to c6 {t in 2..24}: g_t[t] - g_t[t-1] <= 40;
