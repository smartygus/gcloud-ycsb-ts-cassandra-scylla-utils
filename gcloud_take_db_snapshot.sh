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
# nodetool snapshot on Scylla doesn't automatically dump the schema like Cassandra does, so we do that manually here
if [ "$SUT" = "scylla" ]; then
  TABLE_DIRECTORY=$(gcloud compute ssh "$PREFIX-$SUT-cluster-1" --command="ls -ald /var/lib/$SUT/data/ycsb/*/snapshots/$SNAPSHOT_NAME | cut -d/ -f7")
  echo "TABLE_DIRECTORY found -> $TABLE_DIRECTORY"
  for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Dumping CQL schema on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="cqlsh \$(hostname -I) --execute=\"DESC SCHEMA\" | sudo tee /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY/snapshots/$SNAPSHOT_NAME/schema.cql"; done
  for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "CHOWNing schema.cql on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo chown $SUT:$SUT /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY/snapshots/$SNAPSHOT_NAME/schema.cql"; done
fi
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Viewing snapshot data on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="ls -al /var/lib/$SUT/data/ycsb/*/snapshots/$SNAPSHOT_NAME"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Checking space used on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="du -h --max-depth=3 /var/lib/$SUT/data/ycsb"; done

