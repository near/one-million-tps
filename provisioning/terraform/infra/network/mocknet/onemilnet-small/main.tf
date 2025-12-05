# A small 4-node network, used only for testing, doesn't reach 1M TPS.
# Requires a different environment variable:
# export CASE=cases/forknet/4-shards/

module "mocknet-mirror" {
  # Set the GCP project that you want to use.
  project_id = "onemilnet-testing"
  source     = "../mirror-base"

  chain_id   = "onemilnet"
  unique_id  = ""
  mocknet_id = "onemilnet-bench"


  nodes_location = {
    us-central1 = 2
    us-east1    = 1
    us-east4    = 1
  }

  # Pin zones per region where needed (e.g., europe-west1-b only)
  zones_per_region = {
    us-central1 = ["us-central1-a", "us-central1-b", "us-central1-c"]
    us-east1    = ["us-east1-b", "us-east1-c"]
    us-east4    = ["us-east4-a", "us-east4-b", "us-east4-c"]
  }

  # Customise machine_type if required
  machine_type   = "c4d-standard-16"
  node_disk_type = "hyperdisk-balanced"
  boot_disk_type = "hyperdisk-balanced"

  # Optional Hyperdisk tuning (MB/s and IOPS). 
  # Leave commented unless using hyperdisk.
  node_disk_provisioned_throughput = 1200
  node_disk_provisioned_iops       = 20000

  # Controls total data disk size on the node
  node_disk_extra_gb = 390

  # Setup tracing server:
  tracing_server = true

  cp_monitoring_nodes_per_region = 64
  cv_monitoring_nodes_per_region = 64

  node_image = ""

  # more fine grain controls can be found in
  # ../mirror-base/variables.tf
}

output "prometheus_external_ip" {
  description = "External IP address of the Prometheus server"
  value       = module.mocknet-mirror.prometheus_external_ip
}
