#!/bin/bash

################################ global config ################################

# public ip/dns of the couchbase instance
# the workload-api instance assumes that all required ports are accessible to connect to Couchbase by using the default ports: https://docs.couchbase.com/server/current/install/install-ports.html
COUCHBASE_IP=127.0.0.1

# the publicly acessible ip/dns of the workload-api instance
WORKLOAD_API_IP=127.0.0.1


# workload setting, recordsize is 5 KB, i.e. total recordsize is 100GB not including additional DBMS metadata
TOTAL_RECORD_COUNT=20




################################ write-heavy workload ################################

WRITE_WORKER_THREADS=2

BODY="{\"dbEndpoints\":[{\"ipAddress\":\"$COUCHBASE_IP\",\"port\":0}],\"measurementConfig\":{\"interval\":10,\"measurementType\":\"NONE\"},\"workloadConfig\":{\"workloadType\":\"LOAD\",\"workloadClass\":\"com.yahoo.ycsb.workloads.CoreWorkload\",\"maxExecutionTime\":0,\"threadCount\":$WRITE_WORKER_THREADS,\"recordCount\":$TOTAL_RECORD_COUNT,\"insertStart\":0,\"insertCount\":0,\"operations\":1000,\"targetOps\":0,\"fieldCount\":10,\"fieldLength\":500,\"readAllFileds\":true,\"readModifyWriteProportion\":0,\"requestdistribution\":\"UNIFORM\",\"scanLengthDistribution\":\"UNIFORM\",\"insertOrder\":\"ORDERED\",\"readProportion\":0,\"updateProportion\":0,\"insertProportion\":1,\"scanProportion\":0,\"maxScanLength\":1000,\"coreWorkloadInsertionRetryLimit\":3,\"coreWorkloadInsertionRetryInterval\":3},\"databaseConfig\":{\"databaseBinding\":\"COUCHBASE2\",\"endpointParameterName\":\"couchbase.host\",\"tableParameterName\":\"couchbase.bucket\",\"tableName\":\"ycsb\",\"configPorperties\":[{\"name\":\"couchbase.user\",\"value\":\"ycsb\"},{\"name\":\"couchbase.password\",\"value\":\"mowgli19\"},{\"name\":\"couchbase.persistTo\",\"value\":\"0\"},{\"name\":\"couchbase.replicateTo\",\"value\":\"0\"}]}}"

curl -X POST "http://$WORKLOAD_API_IP:8181/v1/workload/ycsb?taskId=numa-write" -H "accept: application/json" -H "Content-Type: application/json" -d "$BODY"



################################ checking the workload execution state ################################

#TODO: either check constanly via a script of manually

curl -X GET "http://$WORKLOAD_API_IP:8181/v1/workload/status?applicationInstanceId=numa-write" -H "accept: application/json"



################################ getting the workload results ################################
# results can be found diretly on fileystem of the workload-api under: /tmp/YCSB/numa-write.txt and /tmp/YCSB/numa-read.txt

#in addition results can be get via the workload-api interface:

curl -X GET "http://$WORKLOAD_API_IP:8181/v1/workload/result?taskId=numa-write&workloadType=YCSB" -H "accept: text/plain"
