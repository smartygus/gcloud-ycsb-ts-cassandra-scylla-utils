#!/bin/bash
# Script to update the YCSB Client with a new build 
#
# Example usage: ./gcloud_update_ycsb_client.sh msbench ./ycsb-cassandra-binding-ts-0.18.0-SNAPSHOT.tar.gz

PREFIX=$1
YCSB_PACKAGE_PATH=$2

echo "Removing existing YCSB package..."
gcloud compute ssh $PREFIX-ycsb-client --command="ls -al; rm -rf ~/\$(basename $YCSB_PACKAGE_PATH .tar.gz); rm  ~/\$(basename $YCSB_PACKAGE_PATH); ls -al"
echo "Copying YCSB package..."
gcloud compute scp $YCSB_PACKAGE_PATH $PREFIX-ycsb-client:~
echo "Extracting YCSB package..."
gcloud compute ssh $PREFIX-ycsb-client --command="tar -xzf \$(basename $YCSB_PACKAGE_PATH); ls -al"
echo "Done!"
