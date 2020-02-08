#!/bin/bash
# Script to spin up an n-Node Cassandra Cluster on Google Cloud Compute with Local SSDs
# One local 375GB SSD will also be attached and setup to be used as the data
# volume for Cassandra. This is setup by formatting the drive, mounting it, then symlinking
# the Cassandra data directly (/var/lib/cassandra) to the mount point of the SSD.
#
# Example usage (for a 3-node cluster, 15GB RAM, 8 vCPUs, 10GB Boot disk): ./gcloud_cassandra_cluster.sh msbench 15GB 8 10GB 3

PREFIX=$1
MEMORY=$2 # should be provided with unit (either MB or GB), but must be an integer and must be a multiple of 256MB (1GB = 1024MB)
VCPU_COUNT=$3 # should just be an integer, must be an even number
DISK_SIZE=$4
CLUSTER_SIZE=$5

if gcloud compute snapshots list | grep -q $PREFIX-cassandra-cluster-debian-boot-disk; then
  echo "Existing Cassandra Cluster Boot Disk Snapshot found, re-using this for new VM..."
  echo "Creating boot disk from snapshot..."
  gcloud compute disks create $PREFIX-cassandra-cluster-1 --source-snapshot $PREFIX-cassandra-cluster-debian-boot-disk --type="pd-ssd" --zone="$(gcloud config get-value compute/zone)" --size=$DISK_SIZE
  echo "Creating instance..."
  gcloud compute instances create $PREFIX-cassandra-cluster-1 --custom-cpu=$VCPU_COUNT --custom-memory=$MEMORY --min-cpu-platform "Intel Skylake" --boot-disk-auto-delete --disk name=$PREFIX-cassandra-cluster-1,boot=yes --local-ssd interface=NVME
  echo "Setting auto-delete flag for boot disk on instance..."
  gcloud compute instances set-disk-auto-delete $PREFIX-cassandra-cluster-1 --disk $PREFIX-cassandra-cluster-1
else
  echo "NO existing Cassandra Cluster Boot Disk Snapshot found, creating new VM and disk from scratch..."
  echo "Creating instance..."
  gcloud compute instances create $PREFIX-cassandra-cluster-1 --custom-cpu=$VCPU_COUNT --custom-memory=$MEMORY --min-cpu-platform "Intel Skylake" --boot-disk-auto-delete --boot-disk-size=$DISK_SIZE --boot-disk-type "pd-ssd" --local-ssd interface=NVME --image-project=debian-cloud --image-family=debian-9
  echo "Installing Cassandra..."
  gcloud compute ssh $PREFIX-cassandra-cluster-1 --command='sudo apt-get install -y openjdk-8-jdk xfsprogs; echo "deb http://www.apache.org/dist/cassandra/debian 311x main" | sudo tee -a /etc/apt/sources.list.d/cassandra.sources.list; curl https://www.apache.org/dist/cassandra/KEYS | sudo apt-key add -; sudo apt-get update; sudo apt-get install -y cassandra'
  echo "Creating snapshot of boot disk for later reuse..."
  gcloud compute disks snapshot $PREFIX-cassandra-cluster-1 --snapshot-names=$PREFIX-cassandra-cluster-debian-boot-disk --description="Debian 9 boot disk for Cassandra cluster" --zone="$(gcloud config get-value compute/zone)"
fi

echo "Creating remaining disks and instance for cluster..."
for ((i=2; i<=CLUSTER_SIZE; i++)); do echo "Creating disk $i"; gcloud compute disks create $PREFIX-cassandra-cluster-$i --source-snapshot $PREFIX-cassandra-cluster-debian-boot-disk --type="pd-ssd" --zone="$(gcloud config get-value compute/zone)" --size=$DISK_SIZE; done
for ((i=2; i<=CLUSTER_SIZE; i++)); do echo "Creating instance $i"; gcloud compute instances create $PREFIX-cassandra-cluster-$i --custom-cpu=$VCPU_COUNT --custom-memory=$MEMORY --min-cpu-platform "Intel Skylake" --boot-disk-auto-delete --disk name=$PREFIX-cassandra-cluster-$i,boot=yes --local-ssd interface=NVME; done
 for ((i=2; i<=CLUSTER_SIZE; i++)); do echo "Setting auto delete for boot disk on instance $i"; gcloud compute instances set-disk-auto-delete $PREFIX-cassandra-cluster-$i --disk "$PREFIX-cassandra-cluster-$i"; done

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Updating Cassandra config on instance $i"; gcloud compute ssh $PREFIX-cassandra-cluster-$i --command="sudo sed -i -- \"s/localhost/\$(hostname -i)/g\" /etc/cassandra/cassandra.yaml; sudo sed -i -- \"/endpoint_snitch/s/SimpleSnitch/GossipingPropertyFileSnitch/\" /etc/cassandra/cassandra.yaml; sudo sed -i -- \"s/Test Cluster/Cassandra Benchmark Cluster/g\" /etc/cassandra/cassandra.yaml; sudo sed -i -- \"s/#concurrent_compactors: 1/concurrent_compactors: $VCPU_COUNT/\" /etc/cassandra/cassandra.yaml; sudo sed -i -- \"s/compaction_throughput_mb_per_sec:.*$/compaction_throughput_mb_per_sec: 0/\" /etc/cassandra/cassandra.yaml"; done

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Setting up local SSD for Cassandra Data on instance $i"; gcloud compute ssh $PREFIX-cassandra-cluster-$i --command='sudo mkfs.xfs -f /dev/nvme0n1; sudo mkdir -p /mnt/disks/cassandra; sudo mount /dev/nvme0n1 /mnt/disks/cassandra; sudo chown cassandra:cassandra /mnt/disks/cassandra; sudo systemctl stop cassandra; sudo rm -rf /var/lib/cassandra; sudo ln -s /mnt/disks/cassandra /var/lib/cassandra; sudo chown cassandra:cassandra /var/lib/cassandra'; done

INSTANCE_IP_ADDRESSES=$(echo $(for ((i=1; i<=CLUSTER_SIZE; i++)); do gcloud compute ssh "$PREFIX-cassandra-cluster-$i" --command="echo \"\$(hostname -I | awk '{print \$1}'),\""; done) | tr -d ' ' | sed 's/.$//')
echo "IP Addresses of all hosts in the cluster --> $INSTANCE_IP_ADDRESSES"
for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Updating seeds in cassandra.yaml with all IP Addresses on instance $i"; gcloud compute ssh $PREFIX-cassandra-cluster-$i --command="sudo sed -i -- \"/seeds/s/127.0.0.1/$INSTANCE_IP_ADDRESSES/g\" /etc/cassandra/cassandra.yaml"; done

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Restarting cassandra on instance $i"; gcloud compute ssh $PREFIX-cassandra-cluster-$i --command='sudo systemctl restart cassandra; sleep 2; sudo systemctl status cassandra'; done

sleep 10


CQL="DROP KEYSPACE IF EXISTS ycsb; CREATE KEYSPACE IF NOT EXISTS ycsb WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': '2'} AND DURABLE_WRITES = true; USE ycsb; DROP TABLE IF EXISTS metrics; CREATE TABLE metrics (metric text, tags text, valuetime timestamp, value double, PRIMARY KEY ((metric, tags), valuetime)) WITH CLUSTERING ORDER BY (valuetime ASC);"
echo "Creating keyspace and table for YCSB Timeseries Workload..."
gcloud compute ssh $PREFIX-cassandra-cluster-1 --command="until echo \"$CQL\" | cqlsh \$(hostname -I); do echo \"Cassandra not yet up and running, will try again in 2 seconds...\"; sleep 2; done"

sleep 5

gcloud compute ssh $PREFIX-cassandra-cluster-1 --command='nodetool status'

echo "<<Script finished in $SECONDS seconds>>"
