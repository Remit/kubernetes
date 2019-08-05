Before tests:
1) start workload-API via running (once!) scripts/setup-load-driver.sh
2) recompile kubelet with scripts/kubelet-recompile.sh

FIRST TEST:
1) ensure that couchbase-simplest.yaml does NOT contain label "testpolicy: antinuma" and CONTAINS label "numapolicy: numaaware"
2) deploy Couchbase with script deploy-couchbase.sh
3) start test with testYCSBworkloads.sh (remember to adjust it according to your needs/system!)
4) copy results from /tmp/YCSB folder to some other directory so they won't be overwritten by the next test
5) run script undeploy-couchbase.sh to ensure that there will be no data from the previous run in the database (attempt to rewrite might result in error!)

SECOND TEST:
1) ensure that couchbase-simplest.yaml CONTAINS label "testpolicy: antinuma" and label "numapolicy: numaaware"
2) deploy Couchbase with script deploy-couchbase.sh
3) start test with testYCSBworkloads.sh (remember to adjust it according to your needs/system!)
4) copy results from /tmp/YCSB folder to some other directory so they won't be overwritten by the next test
5) run script undeploy-couchbase.sh to ensure that there will be no data from the previous run in the database (attempt to rewrite might result in error!)
