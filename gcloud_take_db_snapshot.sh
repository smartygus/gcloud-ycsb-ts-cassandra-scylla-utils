#!/bin/bash
# Script to take a snapshot of the Cassandra / ScyllaDB database at a particular point
#
# Example usage (for cassandra) : ./gcloud_take_db_snapshot.sh msbench cassandra 3 ycsb_20200208-2011
# Example usage (for ScyllaDB): ./gcloud_take_db_snapshot.sh msbench scylla 3 ycsb_20200208-2011

PREFIX=$1
SUT=$2
CLUSTER_SIZE=$3
SNAPSHOT_NAME=$4


for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool cleanup ycsb on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command='nodetool cleanup ycsb'; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Checking space used on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="du -h --max-depth=3 /var/lib/$SUT/data/ycsb"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool snapshot -t $SNAPSHOT_NAME ycsb on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="nodetool snapshot -t $SNAPSHOT_NAME ycsb"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Viewing snapshot data on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="ls -al /var/lib/$SUT/data/ycsb/*/snapshots/$SNAPSHOT_NAME"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Checking space used on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="du -h --max-depth=3 /var/lib/$SUT/data/ycsb"; done

