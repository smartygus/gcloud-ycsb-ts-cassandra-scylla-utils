#!/bin/bash
# Script to drop and re-setup the keyspace, and tables for the YCSB TimeSeries workloads
#
# Example usage (for cassandra) : ./gcloud_reset_ycsb_ts_database.sh msbench cassandra 3
# Example usage (for ScyllaDB): ./gcloud_reset_ycsb_ts_database.sh msbench scylla 3

PREFIX=$1
SUT=$2
CLUSTER_SIZE=$3

CQL="DROP KEYSPACE IF EXISTS ycsb; CREATE KEYSPACE IF NOT EXISTS ycsb WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': '2'} AND DURABLE_WRITES = true; USE ycsb; DROP TABLE IF EXISTS metrics; CREATE TABLE metrics (metric text, tags text, valuetime timestamp, value double, PRIMARY KEY (metric, tags, valuetime)) WITH CLUSTERING ORDER BY (tags ASC, valuetime ASC);"

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Checking space used on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="du -h --max-depth=1 /var/lib/$SUT/data/ycsb"; done

echo "Dropping and re-creating keyspace and table for YCSB Timeseries Workload..."
gcloud compute ssh $PREFIX-$SUT-cluster-1 --command="until cqlsh \$(hostname -I) --execute=\"$CQL\"; do echo \"Cassandra not yet up and running, will try again in 2 seconds...\"; sleep 2; done"
echo "Getting Info about ycsb keyspace via cqlsh..."
gcloud compute ssh $PREFIX-$SUT-cluster-1 --command="until cqlsh \$(hostname -I) --execute=\"DESC keyspace ycsb;\"; do echo \"Cassandra not yet up and running, will try again in 2 seconds...\"; sleep 2; done"

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool cleanup on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command='nodetool cleanup'; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool clearsnapshot on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command='nodetool clearsnapshot'; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Checking space used on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="du -h --max-depth=1 /var/lib/$SUT/data/ycsb"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do
  echo "Restarting $SUT on $i"
  if [ "$SUT" = "scylla" ]; then
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl restart scylla-server"
  else
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl restart $SUT"
  fi
done
for ((i=1; i<=CLUSTER_SIZE; i++)); do
  echo "$SUT status on $i"
  if [ "$SUT" = "scylla" ]; then
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl status scylla-server"
  else
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl status $SUT"
  fi
done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "nodetool status ycsb on $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="nodetool status ycsb"; done
