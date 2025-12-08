# 1 million TPS network instructions

This repository contains the instructions to run a NEAR protocol network benchmark which reaches 1 million transactions per second.

### Network details
* NEAR version: https://github.com/near/nearcore, `master` branch, commit `d178e1830b062b407c270e8f8045753fd41cd081`
* 140 nodes in the following regions:
    * us-central1 - 47 nodes
    * us-east1 - 47 nodes
    * us-east4 - 46 nodes
* 70 shards, two chunk producer nodes per shard
* All transactions are native NEAR token transfers
* 1 million accounts
* Uniform cross-shard traffic

### Cost

The estimated cost to run the benchmark is around $700 per hour.

Estimated cost of one node is:

| Item                    | Cost             |
| ----------------------- | ---------------- |
| c4d-highmem-16 VM       | ~$1 per hour     |
| 64 MB/s network traffic | ~$4 per hour     |
| 200 GB boot disk        | < $0.01 per hour |
| 390 GB hyper disk       | < $0.01 per hour |
| Total                   | $5 per hour      |

There are 140 nodes in the network, $5 * 140 = $700 per hour.

This is an estimate, the actual cost may vary and GCP pricing can change over time.

Note that starting up the network using the following instructions takes about an hour.

## Instructions

### 1. Google cloud setup

The network runs on google cloud VMs. We provide the terraform to create the VMs, but there are some setup steps needed before running terraform:

1. Acquire a google cloud account
2. Create a google cloud project which will contain the network, give the project a unique name that's unlikely to conflict with others.
3. Enable Compute Engine API for this project
4. Install the `gcloud` CLI tool and connect it to the google account. You should be able to run `gcloud compute instances list --project <GOOGLE CLOUD PROJECT NAME>`
5. Install terraform

### 2. Clone the repositories
```bash
git clone https://github.com/near/one-million-tps

git clone https://github.com/near/nearcore
cd nearcore
git checkout d178e1830b062b407c270e8f8045753fd41cd081
cd ..
```

### 3. Set the GCP project name in main.tf
Edit the file `provisioning/terraform/infra/network/mocknet/onemilnet-official/main.tf`

Set `project_id` to the name of your google cloud project and save.

### 4. Create the VMs using terraform
Run these commands to create the virtual machines:
```bash
pushd provisioning/terraform/infra/network/mocknet/onemilnet-official
terraform init
terraform apply -auto-approve
popd
```

Give the nodes ~5 minutes to start up and initialize, otherwise some commands might fail.

In case of quota errors, go to https://console.cloud.google.com/iam-admin/quotas and increase the quotas, then run `terraform apply` again.

At the end of the `terraform apply` output there will be the public IP of the prometheus server which collects metrics from the network.
```bash
...

prometheus_external_ip = "1.2.3.4"
```
Note it down, the IP will later be used to view network metrics.

### 5. Login into a node
Before going to next step please login into any VM using the `ubuntu` user.
It is required in order for `gcloud` to propagate the ssh key for the user.
Further steps use the `ubuntu` user to execute actions.

Run this command:
```bash
gcloud compute ssh --zone "us-central1-a" "ubuntu@mocknet-onemilnet-bench-prometheus" --project <GOOGLE CLOUD PROJECT NAME>
```
This should login into the node.
Log out of the node (e.g. press Ctrl+D) and proceed to the next steps.

### 5.1 Build neard from source (optional)
We provide a prebuilt binary in the repository (`files/neard`), but you can also build `neard` from source.

> Note that it's best to build it on `Ubuntu 22.04` with an x86_64 CPU, binaries built on other distributions might not be able to run on the VMs which are also on `Ubuntu 22.04`. It can be built in a Docker container based on `Ubuntu 22.04`.  To test if a binary you built will work, you can `gcloud compute scp` it onto a node and run `./neard --version`

```bash
# Install rust - see https://rust-lang.org/tools/install/

# Install build dependencies
sudo apt install -y git make cmake libssl-dev pkg-config curl clang

# Build the binary
cd nearcore
cargo build -p neard --release --features tx_generator
cd ..

# Copy the binary to the proper location
cp nearcore/target/release/neard <THIS_REPO>/files/neard
```

### 6. Setup python environment
The benchmark is started using python scripts which require some setup to work properly.
All python scripts should be run from the root of the repository.

Some of the scripts print `stderr` output. This is normal and doesn't mean that there was an error, just shows output of the commands that were run on the nodes.

```bash
# Install python
sudo apt install -y python3


# Optional - create a virtual environment and activate it
sudo apt install -y python3-venv
python3 -m venv venv
source venv/bin/activate

# Install python dependencies
python3 -m pip install -U -r ./scripts/mocknet/requirements.txt

# Setup environment variables
export CASE=cases/forknet/70-shards/
export BINARY=files/neard # Location of built binary
export MOCKNET_PROJECT=<GOOGLE CLOUD PROJECT NAME>
export MOCKNET_ID=onemilnet-bench # This is the default value, should correspond to mocknet_id in main.tf.
export MOCKNET_STORE_PATH="gs://near-$MOCKNET_PROJECT-artefact-store"
export NEAR_BENCHMARK_CASES_DIR=scripts
export NEARD_BINARY_URL="https://storage.googleapis.com/${MOCKNET_STORE_PATH#gs://}/neard"
```

One may use the `4-shards` case to experiment with the setup without incurring significant costs. The corresponding terraform files for the 4-shard setup is in `onemilnet-small`.

### 7. Upload the `neard` binary to all nodes.

```bash
# Upload the binary
gcloud storage cp $BINARY $MOCKNET_STORE_PATH/neard
python3 scripts/mocknet/mirror.py --mocknet-id $MOCKNET_ID run-cmd --cmd "gsutil cp ${MOCKNET_STORE_PATH}/neard ."
# Mark it as executable
python3 scripts/mocknet/mirror.py --mocknet-id $MOCKNET_ID run-cmd --cmd 'chmod +x neard'
```

### 8. Create node setup state
```bash
python3 scripts/mocknet/mirror.py --mocknet-id $MOCKNET_ID run-cmd --cmd './neard --home .near/setup init'
python3 scripts/mocknet/mirror.py --mocknet-id $MOCKNET_ID upload-file --src files/config.json --dst .near/setup
```

### 9. Init neard runner
Install `neard-runner` on all nodes. It takes care of running `neard` on the node.

```bash
python3 scripts/mocknet/mirror.py --mocknet-id $MOCKNET_ID init-neard-runner --neard-binary-url "$NEARD_BINARY_URL" --neard-upgrade-binary-url ""
```

At some point it will print out this output repeatedly. This is fine, don't cancel the command:
```bash
INFO: Found 140 instances with mocknet_id=onemilnet-bench
INFO: Searching for instances with mocknet_id=onemilnet-bench in project=onemilnet-testing (all zones)
INFO: Found 140 instances with mocknet_id=onemilnet-bench
INFO: Searching for instances with mocknet_id=onemilnet-bench in project=onemilnet-testing (all zones)
INFO: Found 140 instances with mocknet_id=onemilnet-bench
...
```

### 10. Init the benchmark
Init benchmark state on all nodes.

```bash
python3 scripts/mocknet/sharded_bm.py --mocknet-id $MOCKNET_ID init --neard-binary-url "$NEARD_BINARY_URL"
```

### 11. Run the benchmark
Start the benchmark.

```bash
python3 scripts/mocknet/sharded_bm.py --mocknet-id $MOCKNET_ID start --enable-tx-generator --receivers-from-senders-ratio=0.0
```

### 12. Observe metrics

Take the prometheus IP that was printed in step `4.` and open the prometheus web page at `http://<prometheus-ip>:9090`.
If you lost the IP, it can be recovered by running `terraform apply` again, or finding the prometheus VM in the google project and taking its external IP.

Below are a few query examples. You can enter them in the text field and execute the query to view the metrics. Choose `Graph` to view them as a graph.
Note that the graphs will not refresh on their own, you have to execute the query again to view the latest data.

The metrics might not be available immediately after starting the benchmark. Give the network ~15 minutes to start up.

#### Show total transactions per second:
```promql
sum(rate(near_chunk_transactions_total[2m]))
```

#### Show block height of each node:
```promql
near_block_height_head
```

#### Show blocks per second
```promql
avg(rate(near_block_height_head[2m]))
```

### 13. Stop the benchmark (optional)

```bash
python3 scripts/mocknet/sharded_bm.py --mocknet-id $MOCKNET_ID stop
```

### 14. Destroying the network
To destroy the VMs you can run `terraform destroy` in the same folder as `terraform apply`:
```bash
pushd provisioning/terraform/infra/network/mocknet/onemilnet-official
terraform destroy
popd
```

## Troubleshooting

The instructions provided here should be enough to reliably reproduce the benchmark, but if you run into issues, here are a few things to try:

#### Find a node on the google cloud page and ssh into it
```bash
gcloud compute ssh --project <GOOGLE CLOUD PROJECT NAME> ubuntu@mocknet-onemilnet-bench-<random-string>
```

#### Check node's startup scripts logs:
```bash
# (run on a node)
journalctl -u google-startup-scripts
```

> Note if the scripts failed with a transient failure, they can be re-run by restarting the `google-startup-scripts` service.

#### Check `neard` logs:
```bash
# (run on a node)
cat neard-logs/logs.txt
```

#### Check `neard-runner` logs:
```bash
# (run on a node)
journalctl -u neard-runner
```

#### If prometheus doesn't work, check the status of the prometheus service:
```bash
# Run on the prometheus VM
systemctl status prometheus
journalctl -u prometheus
```

#### Enable debug logs in the python scripts
Search for `logging.INFO` in the `nearcore` repository and replace all occurrences with `logging.DEBUG`.

#### Don't ignore errors in the python scripts

Some commands in the python scripts ignore errors with `on_exception=""`. This can sometimes hide the error messages, you can temporarily remove it to check for errors.
Note that some commands do this on purpose - removing it in the file upload routines will break the script, so add them back before retrying the setup steps.


#### Let the commands run, don't cancel them

Sometimes it seems that a command is stuck, but it is actually doing work.
Don't cancel them when they seem stuck. Let them run for at least 15 minutes.

#### Rerun the commands

The commands should generally be idempotent. If something went wrong, you can run them again until things work.

#### Destroy the network an try again

Destroying the network and starting from clean state can help to get things working.

Most of the time running `sharded_bm.py init` (step `10.`) should be enough to reset the network, but destroying it gives 100% confidence that it's starting from a clean state.

#### Open an issue

If there is a problem with the instructions, please open an issue in this github repository.
