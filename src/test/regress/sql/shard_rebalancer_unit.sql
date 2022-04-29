CREATE OR REPLACE FUNCTION shard_placement_rebalance_array(
    worker_node_list json[],
    shard_placement_list json[],
    threshold float4 DEFAULT 0,
    max_shard_moves int DEFAULT 1000000,
    drain_only bool DEFAULT false,
    improvement_threshold float4 DEFAULT 0.5
)
RETURNS json[]
AS 'citus'
LANGUAGE C STRICT VOLATILE;

-- Check that even with threshold=0.0 shard_placement_rebalance_array returns
-- something when there's no completely balanced solution.


SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2"}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname1"}']::json[]
));

-- Check that a node can be drained in a balanced cluster

SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4"}',
          '{"node_name": "hostname2"}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}'
        ]::json[]
));

-- Check that an already drained node won't be filled again after a second
-- rebalance

SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4"}',
          '{"node_name": "hostname2"}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname2"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}'
        ]::json[]
));


-- Check that even when shards are already balanced, but shard 4 is on a node
-- where it is not allowed it will be moved and there will be rebalancing later

SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,5,6"}',
          '{"node_name": "hostname2", "disallowed_shards": "4"}',
          '{"node_name": "hostname3", "disallowed_shards": "4"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname3"}',
          '{"shardid":6, "nodename":"hostname3"}'
        ]::json[]
));

-- Check that even when shards are already balanced, disallowed shards will be
-- moved away from hostname1 and the only shard that is allowed there will be
-- moved there

SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,5,6"}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname3"}',
          '{"shardid":6, "nodename":"hostname3"}'
        ]::json[]
));

-- Check that an error is returned when a shard is not allowed anywhere

SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "2,4"}',
          '{"node_name": "hostname2", "disallowed_shards": "1,4"}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}'
        ]::json[]
));

-- Check that cost is taken into account when rebalancing

SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2"}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname1"}',
          '{"shardid":4, "nodename":"hostname1", "cost": 3}']::json[]
));


-- Check that cost is taken into account when rebalancing disallowed placements

SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4"}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname1"}',
          '{"shardid":4, "nodename":"hostname1", "cost": 3}']::json[]
));


-- Check that node capacacity is taken into account.

SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 3}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname1"}',
          '{"shardid":4, "nodename":"hostname1"}']::json[]
));

-- Check that shards are not moved when target utilization stays the same and
-- the source utilization goes below the original target utilization. hostname1
-- has utilization of 1, after move hostname2 would have a utilization of 1 as
-- well. hostname1 would have utilization of 1 while hostname2 has utilization
-- of 2/3 now. Since load is spread more fairly with utilization 2/3 than 0 it
-- should choose that distribution.
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 3}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}']::json[]
));


-- Check that shards are moved even when target utilization stays the same, but
-- source utilization goes below the original target utilization. hostname2
-- has utilization of 1, after move hostname1 would have a utilization of 1 as
-- well. hostname2 would have utilization of 2/3 while hostname1 now has
-- utilization of 0 now. Since load is spread more fairly with utilization 2/3
-- than 0 it should choose that distribution.
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 3}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname2"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}']::json[]
));

-- Check that shards are moved even when target utilization stays the same, but
-- source utilization goes below the original target utilization. hostname2
-- has utilization of 2, after move hostname1 would have a utilization of 2 as
-- well. hostname2 would have utilization of 1.5 while hostname1 now has
-- utilization of 1. Since load is spread more fairly with utilization 1.5 than
-- 1 it should choose that distribution.
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 2}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}']::json[]
));

-- Check that shards are moved even when target utilization stays the same, but
-- source utilization goes below the original target utilization. hostname1
-- has utilization of 2, after move hostname2 would have a utilization of 2 as
-- well. hostname1 would have utilization of 1 while hostname2 now has
-- utilization of 1.5. Since load is spread more fairly with utilization 1.5
-- than 1 it should choose that distribution.
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 2}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}']::json[]
));


-- Check that all shards will be moved to 1 node if its capacity is big enough
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 4}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname1"}']::json[]
));

-- Check that shards will be moved to a smaller node node if utilization improves
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 3}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname2"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}']::json[]
));

-- Check that node capacity works with different shard costs
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 3}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname2"}',
          '{"shardid":2, "nodename":"hostname2", "cost": 3}']::json[]
));

-- Check that node capacity works with different shard costs again
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 3}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname1", "cost": 2}']::json[]
));

-- Check that max_shard_moves works and that we get a NOTICE that it is hit
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 3}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname1"}',
          '{"shardid":3, "nodename":"hostname1", "cost": 2}']::json[],
    max_shard_moves := 1
));


-- Check that node capacity works with different shard costs and disallowed_shards
-- NOTE: these moves are not optimal, once we implement merging of updates this
-- output should change.
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1"}',
          '{"node_name": "hostname2", "capacity": 5}',
          '{"node_name": "hostname3", "disallowed_shards": "1,2"}']::json[],
    ARRAY['{"shardid":1, "nodename":"hostname3"}',
          '{"shardid":2, "nodename":"hostname3", "cost": 2}']::json[]
));

-- Check that draining + rebalancing nodes works
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4,5,6", "capacity": 0}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}',
          '{"shardid":6, "nodename":"hostname2"}'
        ]::json[]
));


-- Check that draining nodes with drain only works
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4,5,6", "capacity": 0}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}',
          '{"shardid":6, "nodename":"hostname2"}'
        ]::json[],
    drain_only := true
));

-- Check that draining nodes has priority over max_shard_moves
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4,5,6", "capacity": 0}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}',
          '{"shardid":6, "nodename":"hostname2"}'
        ]::json[],
    max_shard_moves := 0
));

-- Check that drained moves are counted towards shard moves and thus use up the
-- limit when doing normal rebalance moves
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4,5,6", "capacity": 0}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}',
          '{"shardid":6, "nodename":"hostname2"}'
        ]::json[],
    max_shard_moves := 2
));

-- Check that draining for all colocation groups is done before rebalancing
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4,5,6,7,8,9,10,11,12", "capacity": 0}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}',
          '{"shardid":6, "nodename":"hostname2"}',
          '{"shardid":7, "nodename":"hostname1", "next_colocation": true}',
          '{"shardid":8, "nodename":"hostname2"}',
          '{"shardid":9, "nodename":"hostname2"}',
          '{"shardid":10, "nodename":"hostname2"}',
          '{"shardid":11, "nodename":"hostname2"}',
          '{"shardid":12, "nodename":"hostname2"}'
        ]::json[]
));

-- Check that max_shard_moves warning is only shown once even if more than one
-- colocation group its placement updates are ignored because of it
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4,5,6,7,8,9,10,11,12", "capacity": 0}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}',
          '{"shardid":6, "nodename":"hostname2"}',
          '{"shardid":7, "nodename":"hostname1", "next_colocation": true}',
          '{"shardid":8, "nodename":"hostname2"}',
          '{"shardid":9, "nodename":"hostname2"}',
          '{"shardid":10, "nodename":"hostname2"}',
          '{"shardid":11, "nodename":"hostname2"}',
          '{"shardid":12, "nodename":"hostname2"}'
        ]::json[],
    max_shard_moves := 1
));

-- Check that moves for different colocation groups are added together when
-- taking into account max_shard_moves
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "hostname1", "disallowed_shards": "1,2,3,4,5,6,7,8,9,10,11,12", "capacity": 0}',
          '{"node_name": "hostname2"}',
          '{"node_name": "hostname3"}'
        ]::json[],
    ARRAY['{"shardid":1, "nodename":"hostname1"}',
          '{"shardid":2, "nodename":"hostname2"}',
          '{"shardid":3, "nodename":"hostname2"}',
          '{"shardid":4, "nodename":"hostname2"}',
          '{"shardid":5, "nodename":"hostname2"}',
          '{"shardid":6, "nodename":"hostname2"}',
          '{"shardid":7, "nodename":"hostname1", "next_colocation": true}',
          '{"shardid":8, "nodename":"hostname2"}',
          '{"shardid":9, "nodename":"hostname2"}',
          '{"shardid":10, "nodename":"hostname2"}',
          '{"shardid":11, "nodename":"hostname2"}',
          '{"shardid":12, "nodename":"hostname2"}'
        ]::json[],
    max_shard_moves := 5
));


-- Don't move a big shards if it doesn't improve the utilization balance much.
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b"}']::json[],
    ARRAY['{"shardid":1, "cost":20,  "nodename":"a"}',
          '{"shardid":2, "cost":20,  "nodename":"a"}',
          '{"shardid":3, "cost":100, "nodename":"b"}',
          '{"shardid":4, "cost":50,  "nodename":"b"}'
        ]::json[]
));
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b"}']::json[],
    ARRAY['{"shardid":1, "cost":40,  "nodename":"a"}',
          '{"shardid":2, "cost":40,  "nodename":"a"}',
          '{"shardid":3, "cost":100, "nodename":"b"}',
          '{"shardid":4, "cost":100,  "nodename":"b"}'
        ]::json[]
));

-- improvement_threshold can be used to force a move of big shards
-- if needed.
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b"}']::json[],
    ARRAY['{"shardid":1, "cost":20,  "nodename":"a"}',
          '{"shardid":2, "cost":20,  "nodename":"a"}',
          '{"shardid":3, "cost":100, "nodename":"b"}',
          '{"shardid":4, "cost":50,  "nodename":"b"}'
        ]::json[],
    improvement_threshold := 0.1
));
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b"}']::json[],
    ARRAY['{"shardid":1, "cost":40,  "nodename":"a"}',
          '{"shardid":2, "cost":40,  "nodename":"a"}',
          '{"shardid":3, "cost":100, "nodename":"b"}',
          '{"shardid":4, "cost":100,  "nodename":"b"}'
        ]::json[],
    improvement_threshold := 0.2
));

-- limits notices about ignored moves
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b"}',
          '{"node_name": "c"}',
          '{"node_name": "d"}',
          '{"node_name": "e"}',
          '{"node_name": "f"}',
          '{"node_name": "g"}'
        ]::json[],
    ARRAY['{"shardid":1, "cost":39,  "nodename":"a"}',
          '{"shardid":2, "cost":39,  "nodename":"b"}',
          '{"shardid":3, "cost":39,  "nodename":"c"}',
          '{"shardid":4, "cost":39,  "nodename":"d"}',
          '{"shardid":5, "cost":39,  "nodename":"e"}',
          '{"shardid":6, "cost":39,  "nodename":"f"}',
          '{"shardid":7, "cost":40,  "nodename":"g"}',
          '{"shardid":8, "cost":39,  "nodename":"g"}'
        ]::json[],
    improvement_threshold := 0.1
));



-- limits notices based on GUC
set citus.max_rebalancer_logged_ignored_moves = 1;
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b"}',
          '{"node_name": "c"}',
          '{"node_name": "d"}',
          '{"node_name": "e"}',
          '{"node_name": "f"}',
          '{"node_name": "g"}'
        ]::json[],
    ARRAY['{"shardid":1, "cost":39,  "nodename":"a"}',
          '{"shardid":2, "cost":39,  "nodename":"b"}',
          '{"shardid":3, "cost":39,  "nodename":"c"}',
          '{"shardid":4, "cost":39,  "nodename":"d"}',
          '{"shardid":5, "cost":39,  "nodename":"e"}',
          '{"shardid":6, "cost":39,  "nodename":"f"}',
          '{"shardid":7, "cost":40,  "nodename":"g"}',
          '{"shardid":8, "cost":39,  "nodename":"g"}'
        ]::json[],
    improvement_threshold := 0.1
));
set citus.max_rebalancer_logged_ignored_moves = 10;
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b"}',
          '{"node_name": "c"}',
          '{"node_name": "d"}',
          '{"node_name": "e"}',
          '{"node_name": "f"}',
          '{"node_name": "g"}'
        ]::json[],
    ARRAY['{"shardid":1, "cost":39,  "nodename":"a"}',
          '{"shardid":2, "cost":39,  "nodename":"b"}',
          '{"shardid":3, "cost":39,  "nodename":"c"}',
          '{"shardid":4, "cost":39,  "nodename":"d"}',
          '{"shardid":5, "cost":39,  "nodename":"e"}',
          '{"shardid":6, "cost":39,  "nodename":"f"}',
          '{"shardid":7, "cost":40,  "nodename":"g"}',
          '{"shardid":8, "cost":39,  "nodename":"g"}'
        ]::json[],
    improvement_threshold := 0.1
));
set citus.max_rebalancer_logged_ignored_moves = -1;
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b"}',
          '{"node_name": "c"}',
          '{"node_name": "d"}',
          '{"node_name": "e"}',
          '{"node_name": "f"}',
          '{"node_name": "g"}'
        ]::json[],
    ARRAY['{"shardid":1, "cost":39,  "nodename":"a"}',
          '{"shardid":2, "cost":39,  "nodename":"b"}',
          '{"shardid":3, "cost":39,  "nodename":"c"}',
          '{"shardid":4, "cost":39,  "nodename":"d"}',
          '{"shardid":5, "cost":39,  "nodename":"e"}',
          '{"shardid":6, "cost":39,  "nodename":"f"}',
          '{"shardid":7, "cost":40,  "nodename":"g"}',
          '{"shardid":8, "cost":39,  "nodename":"g"}'
        ]::json[],
    improvement_threshold := 0.1
));


-- Combining improvement_threshold and capacity works as expected.
SELECT unnest(shard_placement_rebalance_array(
    ARRAY['{"node_name": "a"}',
          '{"node_name": "b", "capacity": 2}']::json[],
    ARRAY['{"shardid":1, "cost":20,  "nodename":"a"}',
          '{"shardid":2, "cost":10,  "nodename":"a"}',
          '{"shardid":3, "cost":10,  "nodename":"a"}',
          '{"shardid":4, "cost":100, "nodename":"b"}',
          '{"shardid":5, "cost":50,  "nodename":"b"}',
          '{"shardid":6, "cost":50,  "nodename":"b"}'
        ]::json[],
    improvement_threshold := 0.6
));
