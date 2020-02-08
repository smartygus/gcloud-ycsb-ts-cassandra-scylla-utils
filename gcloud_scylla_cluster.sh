#!/bin/bash
# Script to spin up an n-Node Scylla Cluster on Google Cloud Compute with Local SSDs
# One local 375GB SSD will also be attached and setup to be used as the data
# volume for ScyllaDB. This is setup using Scylla's own scylla_raid_setup utility.
#
# Example usage (for a 3-node cluster, 15GB RAM, 8 vCPUs, 10GB Boot disk): ./gcloud_scylla_cluster.sh msbench 15GB 8 10GB 3
# (Above command takes approx. 12-13 Minutes to complete assuming existing boot drive snapshot)

PREFIX=$1
MEMORY=$2 # should be provided with unit (either MB or GB), but must be an integer and must be a multiple of 256MB (1GB = 1024MB)
VCPU_COUNT=$3 # should just be an integer, must be an even number
DISK_SIZE=$4
CLUSTER_SIZE=$5

if gcloud compute snapshots list | grep -q $PREFIX-scylla-cluster-debian-boot-disk; then
  echo "Existing Scylla Cluster Boot Disk Snapshot found, re-using this for new VM..."
  echo "Creating boot disk from snapshot..."
  gcloud compute disks create $PREFIX-scylla-cluster-1 --source-snapshot $PREFIX-scylla-cluster-debian-boot-disk --type="pd-ssd" --zone="$(gcloud config get-value compute/zone)"
  echo "Creating instance..."
  gcloud compute instances create $PREFIX-scylla-cluster-1 --custom-cpu=$VCPU_COUNT --custom-memory=$MEMORY --min-cpu-platform "Intel Skylake" --boot-disk-auto-delete --disk name=$PREFIX-scylla-cluster-1,boot=yes --local-ssd interface=NVME
  echo "Setting auto-delete flag for boot disk on instance..."
  gcloud compute instances set-disk-auto-delete $PREFIX-scylla-cluster-1 --disk $PREFIX-scylla-cluster-1
else
  echo "NO existing Scylla Cluster Boot Disk Snapshot found, creating new VM and disk from scratch..."
  echo "Creating instance..."
  gcloud compute instances create $PREFIX-scylla-cluster-1 --custom-cpu=$VCPU_COUNT --custom-memory=$MEMORY --min-cpu-platform "Intel Skylake" --boot-disk-auto-delete --boot-disk-size=$DISK_SIZE --boot-disk-type "pd-ssd" --local-ssd interface=NVME --image-project=debian-cloud --image-family=debian-9
  echo "Installing Scylla..."
  gcloud compute ssh $PREFIX-scylla-cluster-1 --command='sudo apt-get install apt-transport-https wget gnupg2 dirmngr; sudo apt-get update; sudo apt-key adv --fetch-keys https://download.opensuse.org/repositories/home:/scylladb:/scylla-3rdparty-stretch/Debian_9.0/Release.key; sudo apt-get update; sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 5e08fbd8b5d6ec9c; sudo wget -O /etc/apt/sources.list.d/scylla.list http://repositories.scylladb.com/scylla/repo/a71634f3-502b-4970-9062-0da0b9738121/debian/scylladb-3.2-stretch.list; sudo apt-get update; sudo apt-get install -y scylla;'
  echo "Creating snapshot of boot disk for later reuse..."
  gcloud compute disks snapshot $PREFIX-scylla-cluster-1 --snapshot-names=$PREFIX-scylla-cluster-debian-boot-disk --description="Debian 9 boot disk for Scylla cluster" --zone="$(gcloud config get-value compute/zone)"
fi

echo "Creating remaining disks and instance for cluster..."
for ((i=2; i<=CLUSTER_SIZE; i++)); do echo "Creating disk $i"; gcloud compute disks create $PREFIX-scylla-cluster-$i --source-snapshot $PREFIX-scylla-cluster-debian-boot-disk --type="pd-ssd" --zone="$(gcloud config get-value compute/zone)"; done
for ((i=2; i<=CLUSTER_SIZE; i++)); do echo "Creating instance $i"; gcloud compute instances create $PREFIX-scylla-cluster-$i --custom-cpu=$VCPU_COUNT --custom-memory=$MEMORY --min-cpu-platform "Intel Skylake" --boot-disk-auto-delete --disk name=$PREFIX-scylla-cluster-$i,boot=yes --local-ssd interface=NVME; done
 for ((i=2; i<=CLUSTER_SIZE; i++)); do echo "Setting auto delete for boot disk on instance $i"; gcloud compute instances set-disk-auto-delete $PREFIX-scylla-cluster-$i --disk "$PREFIX-scylla-cluster-$i"; done

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Configuring host on instance $i"; gcloud compute ssh $PREFIX-scylla-cluster-$i --command='sudo sed -i -- "s/localhost/$(hostname -i)/g" /etc/scylla/scylla.yaml'; done

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running scylla_raid_setup on instance $i"; gcloud compute ssh $PREFIX-scylla-cluster-$i --command='sudo scylla_raid_setup --disks /dev/nvme0n1 --raiddev /dev/md0 --update-fstab --root /var/lib/scylla --volume-role all'; done
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Running scylla_setup (for remaining options) on instance $i"; gcloud compute ssh $PREFIX-scylla-cluster-$i --command='sudo scylla_setup --no-raid-setup --nic eth0 --no-coredump-setup --no-version-check --no-node-exporter'; done

INSTANCE_IP_ADDRESSES=$(echo $(for ((i=1; i<=CLUSTER_SIZE; i++)); do gcloud compute ssh "$PREFIX-scylla-cluster-$i" --command="echo \"\$(hostname -I | awk '{print \$1}'),\""; done) | tr -d ' ' | sed 's/.$//')
echo "IP Addresses of all hosts in the cluster --> $INSTANCE_IP_ADDRESSES"
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Updating seeds in scylla.yaml with all IP Addresses on instance $i"; gcloud compute ssh $PREFIX-scylla-cluster-$i --command="sudo sed -i -- "/seeds/s/127.0.0.1/$INSTANCE_IP_ADDRESSES/g" /etc/scylla/scylla.yaml"; done

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Restarting scylla-server on instance $i"; gcloud compute ssh $PREFIX-scylla-cluster-$i --command='sudo systemctl restart scylla-server; sleep 2; sudo systemctl status scylla-server'; done

sleep 10

CQL="DROP KEYSPACE IF EXISTS ycsb; CREATE KEYSPACE IF NOT EXISTS ycsb WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': '2'} AND DURABLE_WRITES = true; USE ycsb; DROP TABLE IF EXISTS metrics; CREATE TABLE metrics (metric text, tags text, valuetime timestamp, value double, PRIMARY KEY ((metric, tags), valuetime)) WITH CLUSTERING ORDER BY (tags ASC, valuetime ASC);"
echo "Creating keyspace and table for YCSB Timeseries Workload..."
gcloud compute ssh $PREFIX-scylla-cluster-1 --command="until echo \"$CQL\" | cqlsh \$(hostname -I); do echo \"Scylla not yet up and running, will try again in 2 seconds...\"; sleep 2; done"

sleep 5

gcloud compute ssh $PREFIX-scylla-cluster-1 --command='nodetool status ycsb'

echo "<<Script finished in $SECONDS seconds>>"
