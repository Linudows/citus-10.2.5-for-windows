--
-- Distributed Partitioned Table MX Tests
--

SET citus.next_shard_id TO 1700000;

SET citus.shard_count TO 4;
SET citus.shard_replication_factor TO 1;

-- make sure wen can create partitioning tables in MX
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);

-- 1-) Distributing partitioned table
-- create partitioned table
CREATE TABLE partitioning_test(id int, time date) PARTITION BY RANGE (time);

-- create its partitions
CREATE TABLE partitioning_test_2009 PARTITION OF partitioning_test FOR VALUES FROM ('2009-01-01') TO ('2010-01-01');
CREATE TABLE partitioning_test_2010 PARTITION OF partitioning_test FOR VALUES FROM ('2010-01-01') TO ('2011-01-01');

-- load some data and distribute tables
INSERT INTO partitioning_test VALUES (1, '2009-06-06');
INSERT INTO partitioning_test VALUES (2, '2010-07-07');

INSERT INTO partitioning_test_2009 VALUES (3, '2009-09-09');
INSERT INTO partitioning_test_2010 VALUES (4, '2010-03-03');

-- distribute partitioned table
SELECT create_distributed_table('partitioning_test', 'id');

-- see from MX node, the data is loaded to shards
\c - - - :worker_1_port

SELECT * FROM partitioning_test ORDER BY 1;

-- see from MX node, partitioned table and its partitions are distributed
SELECT
	logicalrelid
FROM
	pg_dist_partition
WHERE
	logicalrelid IN ('partitioning_test', 'partitioning_test_2009', 'partitioning_test_2010')
ORDER BY 1;

SELECT
	logicalrelid, count(*)
FROM pg_dist_shard
	WHERE logicalrelid IN ('partitioning_test', 'partitioning_test_2009', 'partitioning_test_2010')
GROUP BY
	logicalrelid
ORDER BY
	1,2;

-- see from MX node, partitioning hierarchy is built
SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'partitioning_test'::regclass ORDER BY 1;

\c - - - :master_port
SET citus.shard_replication_factor TO 1;

-- 2-) Creating partition of a distributed table
CREATE TABLE partitioning_test_2011 PARTITION OF partitioning_test FOR VALUES FROM ('2011-01-01') TO ('2012-01-01');

-- see from MX node, new partition is automatically distributed as well
\c - - - :worker_1_port

SELECT
	logicalrelid
FROM
	pg_dist_partition
WHERE
	logicalrelid IN ('partitioning_test', 'partitioning_test_2011')
ORDER BY 1;

SELECT
	logicalrelid, count(*)
FROM pg_dist_shard
	WHERE logicalrelid IN ('partitioning_test', 'partitioning_test_2011')
GROUP BY
	logicalrelid
ORDER BY
	1,2;

-- see from MX node, partitioning hierarchy is built
SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'partitioning_test'::regclass ORDER BY 1;

\c - - - :master_port
SET citus.shard_replication_factor TO 1;

-- 3-) Attaching non distributed table to a distributed table
CREATE TABLE partitioning_test_2012(id int, time date);

-- load some data
INSERT INTO partitioning_test_2012 VALUES (5, '2012-06-06');
INSERT INTO partitioning_test_2012 VALUES (6, '2012-07-07');

ALTER TABLE partitioning_test ATTACH PARTITION partitioning_test_2012 FOR VALUES FROM ('2012-01-01') TO ('2013-01-01');

-- see from MX node, attached partition is distributed as well
\c - - - :worker_1_port

SELECT
	logicalrelid
FROM
	pg_dist_partition
WHERE
	logicalrelid IN ('partitioning_test', 'partitioning_test_2012')
ORDER BY 1;

SELECT
	logicalrelid, count(*)
FROM pg_dist_shard
	WHERE logicalrelid IN ('partitioning_test', 'partitioning_test_2012')
GROUP BY
	logicalrelid
ORDER BY
	1,2;

-- see from MX node, see the data is loaded to shards
SELECT * FROM partitioning_test ORDER BY 1;

-- see from MX node, partitioning hierarchy is built
SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'partitioning_test'::regclass ORDER BY 1;

\c - - - :master_port
SET citus.shard_replication_factor TO 1;

-- 4-) Attaching distributed table to distributed table
CREATE TABLE partitioning_test_2013(id int, time date);
SELECT create_distributed_table('partitioning_test_2013', 'id');

-- load some data
INSERT INTO partitioning_test_2013 VALUES (7, '2013-06-06');
INSERT INTO partitioning_test_2013 VALUES (8, '2013-07-07');

ALTER TABLE partitioning_test ATTACH PARTITION partitioning_test_2013 FOR VALUES FROM ('2013-01-01') TO ('2014-01-01');

-- see from MX node, see the data is loaded to shards
\c - - - :worker_1_port

SELECT * FROM partitioning_test ORDER BY 1;

-- see from MX node, partitioning hierarchy is built
SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'partitioning_test'::regclass ORDER BY 1;

\c - - - :master_port

-- 5-) Detaching partition of the partitioned table
ALTER TABLE partitioning_test DETACH PARTITION partitioning_test_2009;

-- see from MX node, partitioning hierarchy is built
\c - - - :worker_1_port

SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'partitioning_test'::regclass ORDER BY 1;

-- make sure DROPping from worker node is not allowed
DROP TABLE partitioning_test;

\c - - - :master_port

-- Make sure that creating index on only parent and child won't form any inheritance but it will
-- be formed after attaching child index to parent index
CREATE INDEX partitioning_test_2010_idx ON ONLY partitioning_test_2010 USING btree (id);

-- Show that there is no inheritance relation for the index above
SELECT count(*) FROM pg_inherits WHERE inhrelid::regclass = 'partitioning_test_2010_idx'::regclass;

-- Now add the index only on parent and show that there won't be any inheritance for those indices
CREATE INDEX partition_only_parent_index ON ONLY partitioning_test USING btree (id);
SELECT count(*) FROM pg_inherits WHERE inhrelid::regclass = 'partitioning_test_2010_idx'::regclass;

-- Now attach the child index to parent and show there is inheritance
ALTER INDEX partition_only_parent_index ATTACH PARTITION partitioning_test_2010_idx;
SELECT count(*) FROM pg_inherits WHERE inhrelid::regclass = 'partitioning_test_2010_idx'::regclass;

-- show that index on parent is invalid before attaching partition indices for all partitions
CREATE INDEX partitioning_test_2011_idx ON ONLY partitioning_test_2011 USING btree (id);
CREATE INDEX partitioning_test_2012_idx ON ONLY partitioning_test_2012 USING btree (id);
CREATE INDEX partitioning_test_2013_idx ON ONLY partitioning_test_2013 USING btree (id);

SELECT indisvalid FROM pg_index WHERE indexrelid::regclass = 'partition_only_parent_index'::regclass;

-- show that index on parent becomes valid after attaching all partition indices
ALTER INDEX partition_only_parent_index ATTACH PARTITION partitioning_test_2011_idx;
ALTER INDEX partition_only_parent_index ATTACH PARTITION partitioning_test_2012_idx;
ALTER INDEX partition_only_parent_index ATTACH PARTITION partitioning_test_2013_idx;

SELECT indisvalid FROM pg_index WHERE indexrelid::regclass = 'partition_only_parent_index'::regclass;

-- show that creating new partitions gets the index by default and the index is still valid
CREATE TABLE partitioning_test_2014 PARTITION OF partitioning_test FOR VALUES FROM ('2014-01-01') TO ('2015-01-01');

SELECT count(*) FROM pg_index WHERE indexrelid::regclass::text LIKE 'partitioning_test_2014%';

SELECT indisvalid FROM pg_index WHERE indexrelid::regclass = 'partition_only_parent_index'::regclass;

\c - - - :worker_1_port

-- Show that partitioned index is not visible on the MX worker node
select citus_table_is_visible(indexrelid::regclass) from pg_index where indexrelid::regclass::text LIKE 'partition_only_parent_index_%' limit 1;

\c - - - :master_port

DROP INDEX partition_only_parent_index;

-- make sure we can repeatedly call start_metadata_sync_to_node
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);
SELECT start_metadata_sync_to_node('localhost', :worker_1_port);

-- make sure we can drop partitions
DROP TABLE partitioning_test_2009;
DROP TABLE partitioning_test_2010;

-- make sure we can drop partitioned table
DROP TABLE partitioning_test;
DROP TABLE IF EXISTS partitioning_test_2013;

-- test schema drop with partitioned tables
SET citus.shard_replication_factor TO 1;
CREATE SCHEMA partition_test;
SET SEARCH_PATH TO partition_test;

CREATE TABLE partition_parent_table(a int, b int, c int) PARTITION BY RANGE (b);
SELECT create_distributed_table('partition_parent_table', 'a');
CREATE TABLE partition_0 PARTITION OF partition_parent_table FOR VALUES FROM (1) TO (10);
CREATE TABLE partition_1 PARTITION OF partition_parent_table FOR VALUES FROM (10) TO (20);
CREATE TABLE partition_2 PARTITION OF partition_parent_table FOR VALUES FROM (20) TO (30);
CREATE TABLE partition_3 PARTITION OF partition_parent_table FOR VALUES FROM (30) TO (40);

DROP SCHEMA partition_test CASCADE;
RESET SEARCH_PATH;

