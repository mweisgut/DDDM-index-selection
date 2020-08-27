# parameters
## basic
param index_count integer, >= 0; # number of indexes
set indexes = {1..index_count}; # index ids
param query_count integer, > 0; # number of queries
set queries = {1..query_count}; # query ids
param memory_limit integer, >= 0; # available memory
param memory_consumption_i {i in indexes} integer, >=0; # memory consumption for index i

## multi-index configurations
param configuration_count integer, >= index_count; # number of index configurations
set configurations = {0..configuration_count}; # configuration ids, configuration 0 does not contain any index
param contains_c_i {c in configurations, i in indexes} binary default 0; # boolean whether configuration c contains index i
param costs_q_c {q in queries, c in configurations} integer, >= 0;

## chunking
param chunk_size integer, > 0, <= configuration_count;
param chunk_count := ceil(configuration_count / chunk_size);
set chunks = {1..chunk_count}; # chunk ids
set configurations_ck {ck in chunks} := {c in configurations: ceil(c / chunk_size) = ck }; # assign configurations to chunks
set chunk_configurations within configurations;
set configuration_candidates default {0};

## workloads
param workload_count integer, >= 0; # number of workloads
set workloads = {1..workload_count}; # workload ids
param total_cost_weight >= 0; # weight for total costs
param max_workload_cost_weight >= 0; # weight for "squeezing" using upper barrier based on max workload cost
param workload_cost_mean_variance_weight >= 0; # weight for "squeezing" using mean variance
param count_w_q {w in workloads, q in queries} integer, >=0; # count how often query q occurs for workload w
param probability_w {w in workloads} >= 1; # probability of a workload w
param total_workload_probabilities = sum{w in workloads} probability_w[w];

## transition costs aka changing workloads
param prev_use_i {i in indexes} binary; # boolean whether index i was used before. If so, the index currently exists.
param creation_costs_i {i in indexes}, integer, >= 0; # costs for adding index i to in_memory
param removal_costs_i {i in indexes}, integer, >= 0; # costs for removing index i from in_memory

# variables
## basic
var use_i {i in indexes} binary; # boolean whether index i is used in any query
var memory_consumption = sum{i in indexes} (use_i[i] * memory_consumption_i[i]); # memory consumption based on all chosen indexes

## multi-index configurations
var use_q_c {q in queries, c in configurations} binary; # boolean whether configuration c is used for query q

## workloads
var costs_w {w in workloads}; # optimal costs for each workload
var max_workload_cost; # max workload costs
var mean_workload_cost = (sum{w in workloads} costs_w[w]) / workload_count; # mean workload costs
var workload_cost_variance = sum{w in workloads} (((costs_w[w] - mean_workload_cost) ^ 2) * (probability_w[w] / total_workload_probabilities)); # workload cost variance
var total_costs = sum{w in workloads} (costs_w[w] * probability_w[w] / total_workload_probabilities); # optimal total costs if all workloads would occur

## transition costs aka changing workloads
var creation_costs = sum{i in indexes} (use_i[i] * (1 - prev_use_i[i]) * creation_costs_i[i]);
var removal_costs = sum{i in indexes} (prev_use_i[i] * (1 - use_i[i]) * removal_costs_i[i]);
var transition_costs = creation_costs + removal_costs; # costs required to achieve the target configuration from the current configuration

# objectives
## basic
minimize costs: total_cost_weight * total_costs + max_workload_cost_weight * max_workload_cost + workload_cost_mean_variance_weight * workload_cost_variance + transition_costs; # consider reconstruction costs and weights and costs for total, worst case and mean variance

# constraints
## basic
subject to do_not_exceed_memory_limit: # make sure the memory consumption does not exceed the memory limit
    memory_limit >= memory_consumption;

## multi-index configurations
subject to one_config_per_query {q in queries}: # use at most one configuration per query
	1 = sum{c in chunk_configurations} use_q_c[q, c];
subject to connect_index_unused {i in indexes}: # connect unused indexes
    use_i[i] <= sum{q in queries, c in chunk_configurations} (use_q_c[q, c] * contains_c_i[c, i]);
subject to connect_index_used {i in indexes}: # connect used indexes
    use_i[i] >= sum{q in queries, c in chunk_configurations} (use_q_c[q, c] * contains_c_i[c, i]) / query_count;

## workloads
subject to workload_costs {w in workloads}: # calculate the costs per workload without taking probability into account
    costs_w[w] = sum{q in queries, c in chunk_configurations} (use_q_c[q, c] * costs_q_c[q, c] * count_w_q[w, q]);
subject to max_workload_costs {w in workloads}: # calculate the max workload costs for "squeezing"
    max_workload_cost >= costs_w[w];
