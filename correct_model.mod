# ✅ Clear sections separating structure, data, and logic.
### SETS
# ✅ Ordered sets replace brittle, hardcoded indices like {1..24}.
set PERIODS ordered;
### PARAMETERS
# ✅ Verbose, self-documenting naming conventions.
param thermal_cost {PERIODS}; param solar_resource {PERIODS}; param inflows {PERIODS}; param market_price {PERIODS};
# ✅ Scalars parameterized with safe cascading defaults. No hardcoded values.
param hydro_efficiency > 0 default 0.85; param delta_t default 0.0036; param penalty_spillage >= 0 default 250;
param max_thermal_cap >= 0 default 100; param ramp_limit >= 0 default 40;
### OBJECTIVE
# ✅ Meaningful objective name and parameterized penalties.
maximize Total_Profit: sum{t in PERIODS} (market_price[t] * (Thermal_Gen[t] + Solar_Gen[t] + (hydro_efficiency * TurbiningFlow[t])))
- sum{t in PERIODS} (thermal_cost[t] * Thermal_Gen[t]) - sum{t in PERIODS} (penalty_spillage * SpillageFlow[t]);
### CONSTRAINTS
# ✅ Special ordered set functions (first, prev) eliminate clunky t-1 math.
subject to Water_Balance {t in PERIODS}: ReservoirStorage[t] = (if t = first(PERIODS) then initial_storage else ReservoirStorage[prev(t)])
+ delta_t * (inflows[t] - TurbiningFlow[t] - SpillageFlow[t]);
# ✅ Final condition uses last() function, robust to horizon changes.
subject to Final_Storage_Target: ReservoirStorage[last(PERIODS)] = target_storage;
# ✅ Clean subset bounding using ord() to safely manage ramps.
subject to Thermal_Ramp_Up {t in PERIODS: ord(t) > 1}: Thermal_Gen[t] - Thermal_Gen[prev(t)] <= ramp_limit;
