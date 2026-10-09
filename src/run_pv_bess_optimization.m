%% PV+BESS System Joint Optimal Sizing and Scheduling
clear; clc; close all;

%% 1. Load Input Profiles from CSV Files
zeta_PV = readmatrix('STU_003_pv_1h.csv');         
load_all_year = readmatrix('STU_003_load_1h.csv');   
prices_all_year = readmatrix('STU_003_price_1h.csv'); 

% Force column vector format (8760x1)
zeta_PV = zeta_PV(:);
load_all_year = load_all_year(:);
prices_all_year = prices_all_year(:);

% Cut off negative prices ---
%"Prices cannot be negative"-- same as HyEfRe DST
prices_all_year(prices_all_year < 0) = 0;

time_plot = 0:8759;
Td = 1; % Sampling time [h]
N = 8760;

%% 2. Unique Parameters Setup
% BESS parameters
eta_BESS_ch = 0.9;         % Charging efficiency [-] 
eta_BESS_dch = 0.9;        % Discharging efficiency [-]
DoD_max = 0.85;            % Max depth of discharge [-]
beta_batt = 2;             % Max charging rate [1/h] 
p_batt_inv = 985.68;       % Battery investment cost [EUR/kWh]
p_PC_inv = 246.9;          % Power converter investment cost [EUR/kW]
p_batt_mnt = 7.48;         % Battery maintenance cost [EUR/kWh]
p_PC_mnt = 6.49;           % Power converter maintenance cost [EUR/kW]
N_PC_LT = 19.41;           % Power converter lifetime [year]
N_batt_LT = 19.41;         % Battery lifetime [year]
p_PC_rpl = 185.14;         % Power converter replacement cost [EUR/kW]
p_batt_rpl = 234.25;       % Battery replacement cost [EUR/kWh]
N_cyc = 6832.84;           % Battery cycle life [cycles]

% PV parameters
S_PV_max = 953.57;         % Maximum PV capacity [kWp]
p_PV_inv = 999.24;         % PV investment cost [EUR/kWp]
p_PV_mnt = 22.85;          % PV maintenance cost [EUR/kWp] 
N_PV_LT = 20.79;           % PV lifetime [year]
p_PV_rpl = 871.23;         % PV replacement cost [EUR/kWp]

% Grid parameters
p_pp = 4;                  % Peak power price [EUR/kW]
p_grid_inv = 230;          % Grid investment cost [EUR/kW] 
p_grid_rev = 0;            % Grid downsizing revenue baseline 
P_grid_max = 150;          % Installed grid connection capacity [kW] 
c_grid_fee = 0.02;         % Grid usage fee [EUR/kWh]
feed_in_percentage = 46.39;% Feed-in percentage [%]

% Investment parameters
N_payoff = 11;             % Return of investment payoff limit [years] 
N_DL_base = 22;            % Default system design lifetime [years] 
CAPEX_max = 9759511;       % Budget limit [€] 


%% 3. Energy Cost Formulation (Mod 1a)
% Zero supplier margin on upscale/downscale; apply unique pricing formulas 
p_E_plus = prices_all_year + c_grid_fee; 
p_E_minus = prices_all_year * (feed_in_percentage / 100) - c_grid_fee;

%% 4. Pre-calculating Baseline OPEX (OPEX_noinv)
J_E_noinv = sum(max([p_E_plus p_E_minus].*(load_all_year*Td), [], 2));
number_of_days_in_month = [31 28 31 30 31 30 31 31 30 31 30 31];
starting_indices_for_month = [0 cumsum(number_of_days_in_month)*24] + 1;
P_pp_noinv = zeros(12, 1);
for i = 1:12
    P_pp_noinv(i) = max(load_all_year(starting_indices_for_month(i):starting_indices_for_month(i+1)-1));
end
J_pp_noinv = p_pp * sum(P_pp_noinv);
OPEX_noinv = J_E_noinv + J_pp_noinv;

%% =========================================================================
%% TASK 3: Base Optimization Run 
%% =========================================================================
fprintf('Running Baseline Optimization (Task 3)...\n');
[zopt_base, fval_base] = run_optimization(N_DL_base, [], ...
    zeta_PV, load_all_year, p_E_plus, p_E_minus, Td, N, p_pp, p_grid_inv, p_grid_rev, ...
    P_grid_max, S_PV_max, p_PV_inv, p_PV_mnt, N_PV_LT, p_PV_rpl, eta_BESS_ch, eta_BESS_dch, ...
    DoD_max, beta_batt, p_batt_inv, p_PC_inv, p_batt_mnt, p_PC_mnt, N_PC_LT, N_batt_LT, ...
    p_PC_rpl, p_batt_rpl, N_cyc, N_payoff, CAPEX_max, OPEX_noinv, starting_indices_for_month);

% Extract Sizing Outputs
S_PV_opt = zopt_base(1);   S_batt_opt = zopt_base(2); S_PC_opt = zopt_base(3);
P_grid_delta_opt = zopt_base(4);

% Recalculate operational profiles
P_PV_opt = zopt_base(5+N : 5+2*N-1);
P_BESS_ch_opt = zopt_base(5+2*N : 2 : 5+4*N-2);
P_BESS_dch_opt = zopt_base(5+2*N+1 : 2 : 5+4*N-1);
P_grid_opt = load_all_year + P_BESS_ch_opt - P_BESS_dch_opt - P_PV_opt;

% Plotting 3 Days (e.g., Summer Days: Hours 4000 to 4072) 
day_start = 4000; day_end = day_start + 72;
time_3days = time_plot(day_start:day_end);

figure('Name', 'Task 3: 3-Day Operational Profile');
stairs(time_3days, P_grid_opt(day_start:day_end), 'LineWidth', 1.5); hold on;
stairs(time_3days, P_BESS_ch_opt(day_start:day_end), '--', 'LineWidth', 1.2);
stairs(time_3days, P_BESS_dch_opt(day_start:day_end), '--', 'LineWidth', 1.2);
stairs(time_3days, P_PV_opt(day_start:day_end), 'LineWidth', 1.5);
stairs(time_3days, load_all_year(day_start:day_end), 'k:', 'LineWidth', 1.5);
grid on; xlabel('Time [h]'); ylabel('Power [kW]');
legend('P_{total} (P_{grid})', 'P_{chg}', 'P_{dchg}', 'P_{PV}', 'P_{load}'); 
title(sprintf('Optimal Sizing: PV = %.1f kWp, BESS = %.1f kWh', S_PV_opt, S_batt_opt));

figure;
stairs(time_3days, prices_all_year(day_start:day_end));

%% =========================================================================
%% TASK 5: Design Lifetime Sensitivity Analysis 
%% =========================================================================
N_DL_values = [3, 5, 7, 10, 20];
t5_PV = zeros(size(N_DL_values)); t5_batt = zeros(size(N_DL_values)); t5_PC = zeros(size(N_DL_values));

fprintf('Running Design Lifetime Sweeps (Task 5)...\n');
for idx = 1:length(N_DL_values)
    zopt_t5 = run_optimization(N_DL_values(idx), [], ...
        zeta_PV, load_all_year, p_E_plus, p_E_minus, Td, N, p_pp, p_grid_inv, p_grid_rev, ...
        P_grid_max, S_PV_max, p_PV_inv, p_PV_mnt, N_PV_LT, p_PV_rpl, eta_BESS_ch, eta_BESS_dch, ...
        DoD_max, beta_batt, p_batt_inv, p_PC_inv, p_batt_mnt, p_PC_mnt, N_PC_LT, N_batt_LT, ...
        p_PC_rpl, p_batt_rpl, N_cyc, N_payoff, CAPEX_max, OPEX_noinv, starting_indices_for_month);
    t5_PV(idx) = zopt_t5(1); t5_batt(idx) = zopt_t5(2); t5_PC(idx) = zopt_t5(3);
end

figure('Name', 'Task 5: Impact of Design Lifetime');
subplot(3,1,1); plot(N_DL_values, t5_PV, '-o', 'Color', [0.85 0.33 0.1]); grid on; ylabel('PV [kWp]');
title('Influence of Design Lifetime on Sizing Decisions'); 
subplot(3,1,2); plot(N_DL_values, t5_batt, '-s', 'Color', [0.49 0.18 0.56]); grid on; ylabel('BESS [kWh]');
subplot(3,1,3); plot(N_DL_values, t5_PC, '-^', 'Color', [0.46 0.67 0.18]); grid on; ylabel('Converter [kW]');
xlabel('Design Lifetime [years]'); 

%% =========================================================================
%% TASK 6: Fixed Battery Capacity Sensitivity Analysis
%% =========================================================================
% Create 3 values lower and 3 values higher than optimal baseline 
fixed_batt_steps = [S_batt_opt*[0.4, 0.6, 0.8], S_batt_opt, S_batt_opt*[1.2, 1.4, 1.6]]; 
t6_profit = zeros(size(fixed_batt_steps)); t6_ROI = zeros(size(fixed_batt_steps)); t6_CAPEX = zeros(size(fixed_batt_steps));

fprintf('Running Fixed Battery Capacity Sweeps (Task 6)...\n');
for idx = 1:length(fixed_batt_steps)
    [zopt_t6, fval_t6] = run_optimization(N_DL_base, fixed_batt_steps(idx), ...
        zeta_PV, load_all_year, p_E_plus, p_E_minus, Td, N, p_pp, p_grid_inv, p_grid_rev, ...
        P_grid_max, S_PV_max, p_PV_inv, p_PV_mnt, N_PV_LT, p_PV_rpl, eta_BESS_ch, eta_BESS_dch, ...
        DoD_max, beta_batt, p_batt_inv, p_PC_inv, p_batt_mnt, p_PC_mnt, N_PC_LT, N_batt_LT, ...
        p_PC_rpl, p_batt_rpl, N_cyc, N_payoff, CAPEX_max, OPEX_noinv, starting_indices_for_month);
    
    % Reconstruct localized parameter configurations for degradation metric calculations
    p_PV_deg = ((N_DL_base - N_PV_LT)/(N_DL_base * N_PV_LT)) * p_PV_rpl;
    p_PC_deg = ((N_DL_base - N_PC_LT)/(N_DL_base * N_PC_LT)) * p_PC_rpl;
    
    % Compute Economics
    t6_CAPEX(idx) = [p_PV_inv p_batt_inv p_PC_inv 0 zeros(1, 5*N + 12) 0 1] * zopt_t6; 
    OPEX_inv = [p_PV_mnt+p_PV_deg, p_batt_mnt, p_PC_mnt+p_PC_deg, 0, zeros(1, 4*N), ones(1, N), p_pp*ones(1, 12), 1, 0] * zopt_t6;
    
    t6_profit(idx) = N_DL_base * (OPEX_noinv - OPEX_inv) - t6_CAPEX(idx); 
    if (OPEX_noinv - OPEX_inv) > 0
        t6_ROI(idx) = t6_CAPEX(idx) / (OPEX_noinv - OPEX_inv); 
    else
        t6_ROI(idx) = NaN;
    end
end

figure('Name', 'Task 6: Sensitivity to Fixed Battery Capacity');
subplot(3,1,1); plot(fixed_batt_steps, t6_profit, '-o'); grid on; ylabel('Total Profit [€]'); 
title('Economic Dependencies on Fixed Battery Capacity');
subplot(3,1,2); plot(fixed_batt_steps, t6_ROI, '-s'); grid on; ylabel('ROI Period [Years]'); 
subplot(3,1,3); plot(fixed_batt_steps, t6_CAPEX, '-^'); grid on; ylabel('Optimal CAPEX [€]'); 
xlabel('Fixed Battery Capacity [kWh]'); 


%% =========================================================================
%% MONOLITHIC MATRIX GENERATION & LP SOLVER FUNCTION
%% =========================================================================
function [zopt, fval] = run_optimization(N_DL, fixed_S_batt, ...
    zeta_PV, load_all_year, p_E_plus, p_E_minus, Td, N, p_pp, p_grid_inv, p_grid_rev, ...
    P_grid_max, S_PV_max, p_PV_inv, p_PV_mnt, N_PV_LT, p_PV_rpl, eta_BESS_ch, eta_BESS_dch, ...
    DoD_max, beta_batt, p_batt_inv, p_PC_inv, p_batt_mnt, p_PC_mnt, N_PC_LT, N_batt_LT, ...
    p_PC_rpl, p_batt_rpl, N_cyc, N_payoff, CAPEX_max, OPEX_noinv, starting_indices_for_month)

    % Recalculate dynamic annualized degradation costs based on current lifetime input
    p_PV_deg = ((N_DL - N_PV_LT) / (N_DL * N_PV_LT)) * p_PV_rpl;
    p_PC_deg = ((N_DL - N_PC_LT) / (N_DL * N_PC_LT)) * p_PC_rpl;
    p_batt_deg = ((N_DL - N_batt_LT) / (N_DL * N_batt_LT)) * p_batt_rpl;

    A_ineq = sparse([]); b_ineq = sparse([]);

    % [1-N] and [N+1 - 2N]: Volatile Energy Costs (Behind-the-meter inequalities)
    A_part = [sparse(N,4+N) -spdiags(p_E_plus,0,N,N)*Td spdiags(p_E_plus,0,N,N)*sparse(kron(eye(N),[1 -1])*Td) -speye(N) sparse(N,12+2)];
    b_part = -p_E_plus .* load_all_year * Td;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    A_part = [sparse(N,4+N) -spdiags(p_E_minus,0,N,N)*Td spdiags(p_E_minus,0,N,N)*sparse(kron(eye(N),[1 -1])*Td) -speye(N) sparse(N,12+2)];
    b_part = -p_E_minus .* load_all_year * Td;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % [2N+1 - 3N]: Monthly peak power bounds
    aux_mat = sparse(N,12);
    for j = 1:12
        aux_mat(starting_indices_for_month(j):starting_indices_for_month(j+1)-1, j) = -1;
    end
    A_part = [sparse(N,4+N) -speye(N) sparse(kron(eye(N),[1 -1])) sparse(N,N) aux_mat sparse(N,2)];
    b_part = -load_all_year;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % [3N+1 - 3N+12]: Non-negative peak tracking variables
    A_part = [sparse(12, 4+5*N) -speye(12) sparse(12,2)];
    b_part = sparse(12,1);
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % Constraint (5): Battery Calendar Aging Lower Bound
    A_part = [0 p_batt_deg 0 0 sparse(1,5*N+12) -1 0];
    b_part = 0;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % Constraint (6): Battery Cyclic Lifetime Throughput Lower Bound
    Pch_multiplier = (p_batt_rpl * eta_BESS_ch * Td) / (2 * N_cyc * DoD_max);
    Pdch_multiplier = (p_batt_rpl * Td) / (2 * N_cyc * DoD_max * eta_BESS_dch);
    A_part = [0 -p_batt_rpl/N_DL 0 0 sparse(1,2*N) sparse(repmat([Pch_multiplier Pdch_multiplier],1,N)) sparse(1,N+12) -1 0];
    b_part = 0;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % Constraints (7 & 8): Grid Point Investment Convex Optimization Rules
    A_part = [0 0 0 p_grid_inv sparse(1,5*N+12) 0 -1]; b_ineq = [b_ineq; 0]; A_ineq = [A_ineq; A_part];
    A_part = [0 0 0 p_grid_rev sparse(1,5*N+12) 0 -1]; b_ineq = [b_ineq; 0]; A_ineq = [A_ineq; A_part];

    % [3N+17 - 4N+16]: Non-negative solar generation rules
    A_part = [sparse(N,4+N) -speye(N) sparse(N,3*N) sparse(N,12+2)];
    b_part = zeros(N,1);
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % [4N+17 - 5N+16]: Environmental weather production ceiling limitations
    A_part = [sparse(-zeta_PV) sparse(N,3+N) speye(N) sparse(N,3*N) sparse(N,12+2)];
    b_part = zeros(N,1);
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % Constraint (11): Space/Geometrical Peak PV Boundary Check
    A_part = [1 sparse(1,5*N+17)];
    b_part = S_PV_max;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % [5N+18 - 6N+17]: Minimum permissible Depth of Discharge boundary tracking
    A_part = [sparse(N,1) sparse((1-DoD_max)*ones(N,1)) sparse(N,2) -speye(N) sparse(N,4*N+12+2)];
    b_part = sparse(N,1);
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % [6N+18 - 7N+17]: Instantaneous physical storage availability caps
    A_part = [sparse(N,1) sparse(-ones(N,1)) sparse(N,2) speye(N) sparse(N,4*N+12+2)];
    b_part = sparse(N,1);
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % [7N+18 - 8N+17] and [8N+18 - 9N+17]: Positivity tracking for charging operations
    A_part = [sparse(N,4+2*N) sparse(kron(eye(N),[-1 0])) sparse(N,N+12+2)];
    b_part = sparse(N,1); A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];
    A_part = [sparse(N,4+2*N) sparse(kron(eye(N),[0 -1])) sparse(N,N+12+2)];
    b_part = sparse(N,1); A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % [9N+18 - 10N+17]: Converter capacity throughput checking
    A_part = [sparse(N,2) sparse(-ones(N,1)) sparse(N,1) sparse(N,2*N) sparse(kron(eye(N),[1 1])) sparse(N,N+12+2)];
    b_part = sparse(N,1);
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % Constraint (17): Battery C-Rate performance tracking
    A_part = [0 -beta_batt 1 0 sparse(1,5*N+12+2)];
    b_part = 0;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % [10N+19 - 11N+18] and [11N+19 - 12N+18]: Bidirectional real-time operational grid flow caps
    A_part = [zeros(N,3) sparse(-ones(N,1)) sparse(N,N) speye(N) sparse(kron(eye(N),[-1 1])) sparse(N,N+12+2)];
    b_part = load_all_year + P_grid_max;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    A_part = [zeros(N,3) sparse(-ones(N,1)) sparse(N,N) -speye(N) sparse(kron(eye(N),[1 -1])) sparse(N,N+12+2)];
    b_part = -load_all_year + P_grid_max;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % Constraint (20): Minimal grid reverse limit protection check
    A_part = [0 0 0 -1 sparse(1,5*N+12+2)];
    b_part = P_grid_max;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % MODIFICATION 1b: Remove upper boundary limits for grid connection enlargement
    % (Constraint matching "P_grid_max_delta <= P_grid_max_delta_grid - P_grid_max" has been completely removed)

    % Constraint (22): Regulatory Payoff Return Validation Checks
    A_part = [p_PV_mnt+p_PV_deg+p_PV_inv/N_payoff, p_batt_mnt+p_batt_inv/N_payoff, p_PC_mnt+p_PC_deg+p_PC_inv/N_payoff, 0, sparse(1,5*N+12), 1, 1/N_payoff];
    b_part = OPEX_noinv;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    % Constraint (23): Total Financial Budget Limit
    A_part = [p_PV_inv p_batt_inv p_PC_inv 0 sparse(1,5*N+12+1) 1];
    b_part = CAPEX_max;
    A_ineq = [A_ineq; A_part]; b_ineq = [b_ineq; b_part];

    %% MODIFICATION 2: Add additional constraint sum(P_grid(k)) >= 0 
    % Formulates as: sum(P_PV(k) - P_BESS_ch(k) + P_BESS_dch(k)) <= sum(P_load(k))
    A_task2 = [0, 0, 0, 0, sparse(1,N), ones(1,N), repmat([-1 1], 1, N), sparse(1, N + 12 + 2)];
    b_task2 = sum(load_all_year);
    A_ineq = [A_ineq; A_task2]; b_ineq = [b_ineq; b_task2];

    %% Equality Constraints Assembly
    A_eq = sparse([]); b_eq = sparse([]);

    % [eq 1 - eq N-1]: Temporal BESS State-of-Charge system tracking
    auxmat = spdiags([1 -1], [-1 0], N, N); auxmat = auxmat(2:N, 1:N);
    A_part = [sparse(N-1,4) auxmat sparse(N-1,N) sparse(kron(eye(N-1), [eta_BESS_ch*Td, -Td/eta_BESS_dch])) sparse(N-1,2) sparse(N-1,N+12+2)];
    b_part = sparse(N-1,1);
    A_eq = [A_eq; A_part]; b_eq = [b_eq; b_part];

    % Constraint (eq N): Boundary cyclic standard continuity condition (E_end == E_start)
    A_part = [sparse(1,4) -1 sparse(1,N-2) 1 sparse(1,N) sparse(1,2*(N-1)) eta_BESS_ch*Td -Td/eta_BESS_dch sparse(1,N+12+2)];
    b_part = 0;
    A_eq = [A_eq; A_part]; b_eq = [b_eq; b_part];

    %% TASK 6: Fixed Battery Capacity Equality Modification
    if ~isempty(fixed_S_batt)
        A_fixed_batt = [0, 1, 0, 0, zeros(1, 5*N + 12 + 2)]; 
        b_fixed_batt = fixed_S_batt;
        A_eq = [A_eq; A_fixed_batt]; b_eq = [b_eq; b_fixed_batt];
    end

    %% Base Core Objective Cost Vector Setup
    c = [p_PV_mnt+p_PV_deg+p_PV_inv/N_DL, p_batt_mnt+p_batt_inv/N_DL, p_PC_mnt+p_PC_deg+p_PC_inv/N_DL, 0, sparse(1,4*N), sparse(ones(1,N)), sparse(p_pp*ones(1,12)), 1, 1/N_DL];

    % Run Solver Optimization
    options = optimoptions('linprog', 'Display', 'none');
    [zopt, fval] = linprog(c, A_ineq, b_ineq, A_eq, b_eq, [], [], options);
end