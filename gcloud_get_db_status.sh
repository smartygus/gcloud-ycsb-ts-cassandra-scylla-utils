#!/bin/bash
# Script to print out various stats for the DB, such as compaction status, disk usage, etc
#
# Example usage (for cassandra) : ./gcloud_get_db_status.sh msbench cassandra 3
# Example usage (for ScyllaDB): ./gcloud_get_db_status.sh msbench scylla 3

PREFIX=$1
SUT=$2
CLUSTER_SIZE=$3

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Checking space used on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="du -h --max-depth=1 /var/lib/$SUT/data/ycsb"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool compactionstats on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command='nodetool compactionstats'; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "nodetool status ycsb on $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="nodetool status ycsb"; done

