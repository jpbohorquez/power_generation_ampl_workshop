
# Model Name: Energy Portfolio Optimization with Unit Commitment (pricetaker)

### SETS
set PERIODS ordered;  # hours
set THERMAL_GENERATORS default {};
set RESERVOIR_HYDRO_GENERATORS default {};
set RESERVOIR_QUAD_EFF_GENERATORS within RESERVOIR_HYDRO_GENERATORS default {};
set CONVENTIONAL_GENERATORS = THERMAL_GENERATORS union RESERVOIR_HYDRO_GENERATORS;
set ROR_HYDRO_GENERATORS default {};
set HYDRO_GENERATORS = RESERVOIR_HYDRO_GENERATORS union ROR_HYDRO_GENERATORS;
set UPSTREAM_GENERATORS {HYDRO_GENERATORS} within HYDRO_GENERATORS default {};
set SOLAR_GENERATORS default {};
set WIND_GENERATORS default {};
set RENEWABLE_GENERATORS = SOLAR_GENERATORS union WIND_GENERATORS;
set GENERATORS = THERMAL_GENERATORS union HYDRO_GENERATORS union RENEWABLE_GENERATORS;
set BESS default {};
set PORTFOLIO = GENERATORS union BESS;

### PARAMETERS
# Forecasted Params
param market_price {PERIODS} >= 0;                # Forecasted market energy price ($/MWh)
param marginal_cost {THERMAL_GENERATORS, PERIODS} >= 0;    # Marginal fuel cost ($/MWh)
param inflows {HYDRO_GENERATORS, PERIODS} >= 0 default 0;  # Water contributions/inflows (m3/s)
param renewable_resource {RENEWABLE_GENERATORS, PERIODS} >= 0; # Renewable resource availability (MW)

# Thermal Units Params (Including New Unit Commitment Params)
param ramp_up_rate {THERMAL_GENERATORS} >= 0;     # Ramp up limit (MW/hour)
param ramp_down_rate {THERMAL_GENERATORS} >= 0;   # Ramp down limit (MW/hour)
param min_up_time {THERMAL_GENERATORS} >= 0 default 1;      # Minimum consecutive periods online
param min_down_time {THERMAL_GENERATORS} >= 0 default 1;    # Minimum consecutive periods offline
param initial_online {THERMAL_GENERATORS} binary default 0; # Initial status before period 1

# Hydro Params
param efficiency {HYDRO_GENERATORS diff RESERVOIR_QUAD_EFF_GENERATORS} > 0;                # Conversion Factor (MW/m3/s)
param reservoir_max_capacity {RESERVOIR_HYDRO_GENERATORS} >= 0; # Reservoir max capacity (Hm3)
param initial_storage {r in RESERVOIR_HYDRO_GENERATORS} >= 0 default 0.7*reservoir_max_capacity[r];         # Initial reservoir energy (Hm3)
param final_storage {r in RESERVOIR_HYDRO_GENERATORS} >= 0 default initial_storage[r];  # Required energy at end of horizon (Hm3)
# For QUAD efficiency
param quad_coeff {g in RESERVOIR_QUAD_EFF_GENERATORS, p in 1..3};  # Quadratic coefficient for efficiency function

# Operational Params/Limits
param max_generation {CONVENTIONAL_GENERATORS, PERIODS} >= 0;  # Maximum generation (MW)
param min_generation {GENERATORS, PERIODS} >= 0 default 0;  # Minimum generation (MW)

# BESS params
param max_bess_power {BESS} >= 0;  # MW
param bess_capacity {BESS} >= 0;  # MWh
param bess_efficiency {BESS} > 0, <= 1 default 0.85;  # Round trip efficiency
param initial_soc {b in BESS} >= 0 default 0.5*bess_capacity[b]; # Initial state of charge MWh
param min_charging_periods {BESS} >= 0 default 3; # Minimum number of consecutive periods that the BESS must charge when it starts
param min_charging_power {BESS} >= 0 default 10; # Minimum charging power when the BESS is charging

# Penalty Params
param penalty_spillage {HYDRO_GENERATORS} >= 0 default 2.5* max{t in PERIODS}(market_price[t]); # Penalty for water spillage ($/MWh)

# Computed/Scalar Params
param period_duration >=0 default 3600; # Duration of each period in seconds (default: 1 hour)
param delta_t default period_duration / 1000000;  # Constant to convert m3/s to Hm3 per period


### VARIABLES
var Generation {GENERATORS, PERIODS} >= 0;  # MW
var ReservoirStorage {RESERVOIR_HYDRO_GENERATORS, PERIODS} >= 0;  # Hm3
var TurbiningFlow {HYDRO_GENERATORS, PERIODS} >= 0;  # m3/s
var Spillage {HYDRO_GENERATORS, PERIODS} >= 0;  # MWh
var SpillageFlow {HYDRO_GENERATORS, PERIODS} >= 0;  # m3/s

# Thermal Unit Commitment Variables
var IsOnline {THERMAL_GENERATORS, PERIODS} binary;  # 1 if generating, 0 otherwise
var StartUp {THERMAL_GENERATORS, PERIODS} binary;   # 1 if turned on in period t
var ShutDown {THERMAL_GENERATORS, PERIODS} binary;  # 1 if turned off in period t

# Efficiency as a function of Reservoir Storage (QUAD)
var ScaledReservoirStorage {g in RESERVOIR_QUAD_EFF_GENERATORS, t in PERIODS} = ReservoirStorage[g,t]/1000; # Scale to match function
var Efficiency_QUAD {g in RESERVOIR_QUAD_EFF_GENERATORS, t in PERIODS} = 
    quad_coeff[g,1] * (ScaledReservoirStorage[g,t])^2 + quad_coeff[g,2] * ScaledReservoirStorage[g,t] + quad_coeff[g,3];

# BESS Variables
var Charge {BESS, PERIODS} >= 0;     # MW
var Discharge {BESS, PERIODS} >= 0;  # MW
var SoC {g in BESS, t in PERIODS} >= 0 <= bess_capacity[g];        # State of Charge (MWh)
var IsCharging {BESS, PERIODS} binary;

### OBJECTIVE FUNCTION
maximize TotalProfit:
    sum {g in GENERATORS, t in PERIODS} (market_price[t] * Generation[g, t])
    + sum {b in BESS, t in PERIODS} (market_price[t] * Discharge[b, t])
    - sum {b in BESS, t in PERIODS} (market_price[t] * Charge[b, t])
    - sum {g in THERMAL_GENERATORS, t in PERIODS} (marginal_cost[g, t] * Generation[g, t])
    - sum {g in HYDRO_GENERATORS, t in PERIODS} (penalty_spillage[g] * Spillage[g, t]);


### CONSTRAINTS

# --- Thermal Unit Commitment Constraints ---

subject to ThermalStateLogic {g in THERMAL_GENERATORS, t in PERIODS}:
    IsOnline[g, t] - (if t = first(PERIODS) then initial_online[g] else IsOnline[g, prev(t)]) 
    = StartUp[g, t] - ShutDown[g, t];

subject to MinUpTimeLimit {g in THERMAL_GENERATORS, t in PERIODS}:
    sum {tp in PERIODS: ord(tp) >= ord(t) - min_up_time[g] + 1 and ord(tp) <= ord(t)} 
        StartUp[g, tp] <= IsOnline[g, t];

subject to MinDownTimeLimit {g in THERMAL_GENERATORS, t in PERIODS}:
    sum {tp in PERIODS: ord(tp) >= ord(t) - min_down_time[g] + 1 and ord(tp) <= ord(t)} 
        ShutDown[g, tp] <= 1 - IsOnline[g, t];

subject to ThermalGenerationMax {g in THERMAL_GENERATORS, t in PERIODS}:
    Generation[g, t] <= max_generation[g, t] * IsOnline[g, t];

subject to ThermalGenerationMin {g in THERMAL_GENERATORS, t in PERIODS}:
    Generation[g, t] >= min_generation[g, t] * IsOnline[g, t];

subject to ThermalRampUpLimit {g in THERMAL_GENERATORS, t in PERIODS: ord(t) > 1}:
    Generation[g, t] - Generation[g, prev(t)] <= 
        ramp_up_rate[g] * IsOnline[g, prev(t)] + max_generation[g, t] * StartUp[g, t];

subject to ThermalRampDownLimit {g in THERMAL_GENERATORS, t in PERIODS: ord(t) > 1}:
    Generation[g, prev(t)] - Generation[g, t] <= 
        ramp_down_rate[g] * IsOnline[g, t] + max_generation[g, prev(t)] * ShutDown[g, t];

# --- Hydro Constraints ---

subject to ReservoirHydroBalance {g in RESERVOIR_HYDRO_GENERATORS, t in PERIODS}:
    ReservoirStorage[g, t] = (if t = first(PERIODS) then initial_storage[g] else ReservoirStorage[g, prev(t)])
                                + delta_t * (inflows[g, t]
                                            + sum {ug in UPSTREAM_GENERATORS[g]} (TurbiningFlow[ug, t] + SpillageFlow[ug, t])
                                            - TurbiningFlow[g, t]
                                            - SpillageFlow[g, t]);

subject to RunOfRiverBalance {g in ROR_HYDRO_GENERATORS, t in PERIODS}:
    TurbiningFlow[g, t] + SpillageFlow[g, t] <= inflows[g, t];

subject to ReservoirStorageLimit {g in RESERVOIR_HYDRO_GENERATORS, t in PERIODS}:
    ReservoirStorage[g, t] <= reservoir_max_capacity[g];

subject to ReservoirFinalStorage {g in RESERVOIR_HYDRO_GENERATORS}:
    ReservoirStorage[g, last(PERIODS)] = final_storage[g];

subject to HydroGenerationFromFlow {g in HYDRO_GENERATORS, t in PERIODS}:
    Generation[g, t] = (if g in RESERVOIR_QUAD_EFF_GENERATORS 
                        then Efficiency_QUAD[g, t] 
                        else efficiency[g]) * TurbiningFlow[g, t];

subject to HydroSpillageFromFlow {g in HYDRO_GENERATORS, t in PERIODS}:
    Spillage[g, t] = (if g in RESERVOIR_QUAD_EFF_GENERATORS 
                      then Efficiency_QUAD[g, t] 
                      else efficiency[g]) * SpillageFlow[g, t];

subject to HydroGenerationMax {g in RESERVOIR_HYDRO_GENERATORS, t in PERIODS}:
    Generation[g, t] <= max_generation[g, t];

# --- General Generation Constraints ---

subject to RenewableGenerationLimit {g in RENEWABLE_GENERATORS, t in PERIODS}:
    Generation[g, t] <= renewable_resource[g, t];

subject to NonThermalGenerationMin {g in GENERATORS diff THERMAL_GENERATORS, t in PERIODS}:
    Generation[g, t] >= min_generation[g, t];

# --- BESS Constraints ---

subject to ChargeMaxLimit {g in BESS, t in PERIODS}:
    Charge[g, t] <= max_bess_power[g] * IsCharging[g, t];

subject to ChargeMinLimit {g in BESS, t in PERIODS}:
    Charge[g, t] >= min_charging_power[g] * IsCharging[g, t];

subject to DischargeLimit {g in BESS, t in PERIODS}:
    Discharge[g, t] <= max_bess_power[g] * (1 - IsCharging[g, t]);

subject to SoC_Balance {g in BESS, t in PERIODS}:
    SoC[g, t] = (if t = first(PERIODS) then initial_soc[g] else SoC[g, prev(t)])
                + (Charge[g, t] * (bess_efficiency[g]^0.5)) 
                - (Discharge[g, t] / (bess_efficiency[g]^0.5));

subject to MinChargingPeriods {g in BESS, t in PERIODS: ord(t) > 1}:
    (IsCharging[g,t] == 1 and IsCharging[g, prev(t)] == 0) ==> forall {tp in t..min(t+min_charging_periods[g]-1, last(PERIODS))} IsCharging[g, tp] == 1;
