#!/bin/bash
# Script to spin up a VM with YCSB installed on Google Cloud Compute
#
# Example usage: ./gcloud_ycsb_client.sh msbench n1-highmem-8 10GB ./ycsb-cassandra-binding-ts-0.18.0-SNAPSHOT.tar.gz

PREFIX=$1
MACHINE_TYPE=$2
DISK_SIZE=$3
YCSB_PACKAGE_PATH=$4


if gcloud compute snapshots list | grep -q $PREFIX-ycsb-client-debian-boot-disk; then
  echo "Existing YCSB Boot Disk Snapshot found, re-using this for new VM..."
  echo "Creating boot disk from snapshot..."
  gcloud compute disks create $PREFIX-ycsb-client --source-snapshot $PREFIX-ycsb-client-debian-boot-disk --type="pd-ssd" --zone="$(gcloud config get-value compute/zone)"
  echo "Creating instance..."
  gcloud compute instances create $PREFIX-ycsb-client --machine-type=$MACHINE_TYPE --min-cpu-platform "Intel Skylake" --disk name=$PREFIX-ycsb-client,boot=yes
  echo "Setting auto-delete flag for boot disk on instance..."
  gcloud compute instances set-disk-auto-delete $PREFIX-ycsb-client --disk $PREFIX-ycsb-client
else
  echo "NO existing YCSB Boot Disk Snapshot found, creating new VM and disk from scratch..."
  echo "Creating instance..."
  gcloud compute instances create $PREFIX-ycsb-client --machine-type=$MACHINE_TYPE --min-cpu-platform "Intel Skylake"  --boot-disk-size=$DISK_SIZE --boot-disk-type="pd-ssd" --image-project=debian-cloud --image-family=debian-9
  echo "Installing OpenJDK 8..."
  gcloud compute ssh $PREFIX-ycsb-client --command='sudo apt-get install -y openjdk-8-jdk dstat rsync'

  echo "Creating snapshot of boot disk for later reuse..."
  gcloud compute disks snapshot $PREFIX-ycsb-client --snapshot-names=$PREFIX-ycsb-client-debian-boot-disk --description="Debian 9 boot disk for YCSB Client" --zone="$(gcloud config get-value compute/zone)"
fi
echo "Copying YCSB package..."
gcloud compute scp $YCSB_PACKAGE_PATH $PREFIX-ycsb-client:~
echo "Extracting YCSB package..."
gcloud compute ssh $PREFIX-ycsb-client --command="tar -xzf \$(basename $YCSB_PACKAGE_PATH); ls -al"
echo "Done!"
