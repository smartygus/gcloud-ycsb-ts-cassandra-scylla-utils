#!/bin/bash
# Script to restore from a given snapshot of the Cassandra / ScyllaDB database
#
# Example usage (for cassandra) : ./gcloud_restore_from_snapshot.sh msbench cassandra 3 ycsb_20200208-2011
# Example usage (for ScyllaDB): ./gcloud_restore_from_snapshot.sh msbench scylla 3 ycsb_20200208-2011

PREFIX=$1
SUT=$2
CLUSTER_SIZE=$3
SNAPSHOT_NAME=$4


# This gets the directory for the table including the UUID, which we will use to copy the snapshot data back
TABLE_DIRECTORY=$(gcloud compute ssh "$PREFIX-$SUT-cluster-1" --command="ls -ald /var/lib/$SUT/data/ycsb/*/snapshots/$SNAPSHOT_NAME | cut -d/ -f7")
echo "TABLE_DIRECTORY found -> $TABLE_DIRECTORY"

CQL="CONSISTENCY; CONSISTENCY ALL; TRUNCATE TABLE ycsb.metrics;"

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool status on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command='nodetool status'; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Contents of table data directory (before TRUNCATE) on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="ls -al /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY"; done
echo "Truncating ycsb.metrics table..."
gcloud compute ssh $PREFIX-$SUT-cluster-1 --command="until cqlsh \$(hostname -I) --execute=\"$CQL\"; do echo \"Cassandra not yet up and running, will try again in 2 seconds...\"; sleep 2; done"
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Contents of table data directory (after TRUNCATE) on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="ls -al /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY"; done

if [ "$SUT" = "scylla" ]; then
for ((i=1; i<=CLUSTER_SIZE; i++)); do
  echo "Shutting down $SUT-server on $i"
  gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl stop scylla-server"
done
sleep 20
fi

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Copying snapshot data back into table data on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo cp -r /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY/snapshots/$SNAPSHOT_NAME/* /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY/"; done
# Having the schema.cql data causes startup issues for Scylla (doesn't seem to bother Cassandra), so we'll remove it after it was copied
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Removing schema.cql file from table data folder on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo rm /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY/schema.cql"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "CHOWNing copied table data on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo chown $SUT:$SUT /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY/*"; done

if [ "$SUT" = "scylla" ]; then
for ((i=1; i<=CLUSTER_SIZE; i++)); do
  echo "Starting $SUT-server on $i"
  gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="sudo systemctl start scylla-server"
  echo "Waiting 20 seconds for Scylla Server(s) to start..."
  sleep 20
done
fi

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool refresh ycsb metrics on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="nodetool refresh ycsb metrics"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running nodetool repair ycsb metrics on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="nodetool repair ycsb metrics"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Contents of table data directory (after restoring snapshot) on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="ls -al /var/lib/$SUT/data/ycsb/$TABLE_DIRECTORY"; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Checking space used on instance $i"; gcloud compute ssh $PREFIX-$SUT-cluster-$i --command="du -h --max-depth=3 /var/lib/$SUT/data/ycsb"; done

