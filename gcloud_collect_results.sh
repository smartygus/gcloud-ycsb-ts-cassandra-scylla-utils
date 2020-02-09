#!/bin/bash
# Script to copy various results and montioring files from the YCSB Client and Cluster
# 
# Relies on starting up dstat manually on each of the nodes on the cluster before the benchmark run, and using the same
# filename format for each output.
#
# Example dstat command: dstat -tam --output ~/20200209-1308-ycsb-tsworkload_ms_bachelor_smw1t-load-cassandra-8vCPU-8GB-localssd-192_threads-dstat_monitoring_output-msbench-cassandra-cluster-1.csv
#
# Likewise when starting the benchmark run with YCSB one need to use a properly-formatted name for the output:
#
# Example: bin/ycsb load cassandra-cql-ts -P workloads/tsworkload_ms_bachelor_smw1t -p hosts="10.128.15.211,10.128.15.212,10.128.15.213" -threads 192 -p measurementtype=hdrhistogram -s > 20200209-1302-ycsb-tsworkload_ms_bachelor_smw1t-load-cassandra-8vCPU-8GB-localssd-192_threads-benchmark_output-hdrhistogram.dat
#
# Example usage (for cassandra) : ./gcloud_collect_results.sh msbench cassandra 3 20200209-1302-ycsb-tsworkload_ms_bachelor_smw1t-load-cassandra-8vCPU-8GB-localssd-192_threads hdrhistogram ycsb-cassandra-binding-ts-0.18.0-SNAPSHOT ~/output_dir
# Example usage (for ScyllaDB): ./gcloud_collect_results.sh msbench scylla 3 20200209-1302-ycsb-tsworkload_ms_bachelor_smw1t-load-scylla-8vCPU-8GB-localssd-192_threads hdrhistogram ycsb-cassandra-binding-ts-0.18.0-SNAPSHOT ~/output_dir

PREFIX=$1
SUT=$2
CLUSTER_SIZE=$3
FILE_BASE_NAME=$4
MEASUREMENT_TYPE=$5
YCSB_CLIENT_DIR=$6
OUTPUT_DIR=$7 # should not have any spaces in it

for ((i=1; i<=CLUSTER_SIZE; i++)); do echo "Copying dstat monitoring data from instance $i"; gcloud compute scp $PREFIX-$SUT-cluster-$i:~/$FILE_BASE_NAME-dstat_monitoring_output-$PREFIX-$SUT-cluster-$i.csv $OUTPUT_DIR; done
echo "Copying dstat monitoring and benchmark results from YCSB Client"

# Use rsync instead of scp for the benchmark output because it can sometime be rather big when raw meausurements are used and scp it just too slow ;)
rsync -rlptDvzP $(gcloud compute instances list --filter="name=$PREFIX-ycsb-client" --format "get(networkInterfaces[0].accessConfigs[0].natIP)"):~/$YCSB_CLIENT_DIR/$FILE_BASE_NAME-benchmark_output-$MEASUREMENT_TYPE.dat $OUTPUT_DIR
gcloud compute scp $PREFIX-ycsb-client:~/$FILE_BASE_NAME-dstat_monitoring_output-$PREFIX-ycsb-client.csv $OUTPUT_DIR
ls -al $OUTPUT_DIR

