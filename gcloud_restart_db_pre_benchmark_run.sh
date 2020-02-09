#!/bin/bash
# Script to flush all memtables to disk, and restart the database before doing a database run
#
# Example usage (for cassandra) : ./gcloud_restart_db_pre_benchmark_run.sh msbench cassandra 3
# Example usage (for ScyllaDB): ./gcloud_restart_db_pre_benchmark_run.sh msbench scylla 3

PREFIX=$1
SUT=$2
CLUSTER_SIZE=$3

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool flush -- ycsb metrics on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command='nodetool flush -- ycsb metrics'; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "nodetool status ycsb on $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="nodetool status ycsb"; done

sleep 5

for ((i=1; i<=CLUSTER_SIZE; i++)); do
  echo "Stopping $SUT on $i"
  if [ "$SUT" = "scylla" ]; then
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl stop scylla-server"
  else
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl stop $SUT"
  fi
done

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Clear page cache, dentries, and inodes on $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo free; sudo sync; echo 3 | sudo tee /proc/sys/vm/drop_caches; sudo free"; done

for ((i=1; i<=CLUSTER_SIZE; i++)); do
  echo "Starting $SUT on $i"
  if [ "$SUT" = "scylla" ]; then
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl start scylla-server"
  else
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl start $SUT"
  fi
done

sleep 5

for ((i=1; i<=CLUSTER_SIZE; i++)); do
  echo "$SUT status on $i"
  if [ "$SUT" = "scylla" ]; then
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl status scylla-server"
  else
    gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl status $SUT"
  fi
done

sleep 5

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "nodetool status ycsb on $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="nodetool status ycsb"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "nodetool compactionstats on $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="nodetool compactionstats"; done
