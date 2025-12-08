

provider "google" {
  project = var.project_id
}

resource "google_compute_network" "onemil_network" {
  name                    = "onemil-network"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "network_rules" {
  name    = "onemil-network-rules"
  network = google_compute_network.onemil_network.name

  description = "Allow SSH from anywhere"
  direction   = "INGRESS"
  priority    = 65534

  allow {
    protocol = "tcp"
    ports    = ["22", "3000", "4242", "4317", "5433", "8080", "3030", "24567", "9100", "3389", "9090"]
  }

  source_ranges = ["0.0.0.0/0"]

  disabled = false
}

resource "google_storage_bucket" "near_onemil_artefact_store" {
  name     = "near-${var.project_id}-artefact-store"
  location = "us-central1"

  storage_class = "STANDARD"

  # Required for IAM-only control
  uniform_bucket_level_access = true

  # Optional: allow public access through IAM (default = false)
  public_access_prevention = "unspecified"

  # Requester pays is ON
  requester_pays = false

  # Versioning disabled
  versioning {
    enabled = false
  }

  force_destroy = true
}

resource "google_storage_bucket_iam_member" "allow_node_writes" {
  bucket     = google_storage_bucket.near_onemil_artefact_store.name
  role       = "roles/storage.objectAdmin"
  member     = "serviceAccount:${google_service_account.near_node_sa.email}"
  depends_on = [google_storage_bucket.near_onemil_artefact_store]
}

resource "google_storage_bucket_iam_member" "allow_anonymous_reads" {
  bucket     = google_storage_bucket.near_onemil_artefact_store.name
  role       = "roles/storage.objectViewer"
  member     = "allUsers"
  depends_on = [google_storage_bucket.near_onemil_artefact_store]
}

data "google_compute_zones" "available" {
  region = var.tracing_server_region != null ? var.tracing_server_region : keys(var.nodes_location)[0]
}

# Query zones that support the traffic machine type
data "google_compute_machine_types" "traffic_check" {
  for_each = toset(data.google_compute_zones.available.names)
  zone     = each.key
  filter   = "name = \"${coalesce(var.tracing_server_machine_type, var.machine_type)}\""
}

locals {
  mocknet_id   = coalesce(var.mocknet_id, "${var.chain_id}-${var.start_height}-${var.unique_id}")
  new_chain_id = "onemilnet"
  test_label   = coalesce(var.mocknet_id, "mirror-traffic-${var.chain_id}-${var.start_height}")

  # Find zones that support the traffic machine type
  traffic_zones_available = [
    for zone in data.google_compute_zones.available.names :
    zone if length(data.google_compute_machine_types.traffic_check[zone].machine_types) > 0
  ]

  # Auto-select tracing server zone if not explicitly specified
  # Use the first available zone that supports the machine type
  tracing_server_zone_resolved = var.tracing_server_zone != null ? var.tracing_server_zone : (
    length(local.traffic_zones_available) > 0 ? local.traffic_zones_available[0] : data.google_compute_zones.available.names[0]
  )
}

module "mocknet-validator" {
  source          = "../../../../misc/modules/nearone-mocknet"
  mocknet_network = google_compute_network.onemil_network

  base_instance_name = "mocknet-${local.mocknet_id}-cv"

  machine_type = var.cv_machine_type
  disk_size_gb = var.cv_disk_size_gb
  image_name   = ""

  startup_script_path = "${path.module}/node-init.sh.tmpl"
  startup_script_args = {
    gcs_key    = ""
    empty_disk = "true"
  }

  extra_labels = {
    role       = "validator"
    test_type  = local.test_label
    chain_id   = local.new_chain_id
    mocknet_id = local.mocknet_id
  }

  for_each = var.cv_nodes_location

  region                      = each.key
  machine_count               = each.value
  monitoring_nodes_per_region = var.cv_monitoring_nodes_per_region
  zones                       = lookup(var.cv_zones_per_region, each.key, null)

  node_service_account = google_service_account.near_node_sa
}

module "mocknet-producer" {
  source          = "../../../../misc/modules/nearone-mocknet"
  mocknet_network = google_compute_network.onemil_network

  base_instance_name = "mocknet-${local.mocknet_id}"

  machine_type                     = var.machine_type
  disk_size_gb                     = local.node_disk_size_gb
  node_disk_type                   = var.node_disk_type
  node_disk_provisioned_throughput = var.node_disk_provisioned_throughput
  node_disk_provisioned_iops       = var.node_disk_provisioned_iops
  boot_disk_type                   = var.boot_disk_type

  image_name = var.node_image == "" ? "" : "projects/${var.project_id}/global/images/${var.node_image}"

  startup_script_path = "${path.module}/node-init.sh.tmpl"
  startup_script_args = {
    gcs_key    = ""
    empty_disk = var.node_image == "" ? "true" : "false"
  }

  extra_labels = {
    role       = "producer"
    test_type  = local.test_label
    chain_id   = local.new_chain_id
    mocknet_id = local.mocknet_id
  }

  for_each = var.nodes_location

  region                      = each.key
  machine_count               = each.value
  monitoring_nodes_per_region = var.cp_monitoring_nodes_per_region
  zones                       = lookup(var.zones_per_region, each.key, null)

  node_service_account = google_service_account.near_node_sa
}

resource "google_service_account" "near_node_sa" {
  account_id   = "near-node"
  description  = "near node service account"
  display_name = "near-node"
  project      = var.project_id
}

locals {
  node_disk_size_gb = var.node_disk_extra_gb # empty disk image, real disk size is set using node_disk_extra_gb
}

resource "google_compute_instance" "tracing_server" {
  # add a tracing server if the tracing_server variable is set to true
  count = var.tracing_server == true ? 1 : 0
  name  = "${local.mocknet_id}-tracing-server"

  labels = {
    created_by = "terraform"
    repo       = "infra-ops"
    role       = "mocknet-tracing-server"
    owner      = "nearone-sre"
  }
  tags = ["tracing-server"]

  machine_type = "n2d-standard-4"
  zone         = local.tracing_server_zone_resolved

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-lts"
      type  = "pd-ssd"
      # It is estimated that mocknet traces size will be around 100GB per day. Adjust this value
      # according to the expected test lenght.
      size = 1000
    }
  }

  metadata_startup_script = file("${path.module}/tracing-init.sh")

  network_interface {
    network = google_compute_network.onemil_network.name
    access_config {
      // create external ip
    }
  }
}
resource "google_compute_instance" "prom-scrapper" {
  name         = "mocknet-${local.mocknet_id}-prometheus"
  zone         = "us-central1-a"
  machine_type = "n2d-standard-16"

  boot_disk {
    initialize_params {
      type  = "pd-standard"
      image = "ubuntu-2204-lts"
      size  = 200
    }
    auto_delete = "true"
  }

  network_interface {
    network = google_compute_network.onemil_network.name
    access_config {
      // create external ip
    }
  }
  # Script to install prometheus and configure it to scrape metrics from the mocknet nodes
  metadata_startup_script = file("${path.module}/prometheus.sh")

  # Metadata required for Prometheus configuration
  metadata = {
    mocknet_id = local.mocknet_id
  }
  labels = {
    role       = "prometheus"
    repo       = "infra-ops"
    owner      = "nearone-sre"
    created_by = "terraform"
  }

  tags = ["prometheus-server"]

  service_account {
    email = google_service_account.prometheus_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}

resource "google_service_account" "prometheus_sa" {
  account_id   = "prometheus"
  description  = "prometheus service account"
  display_name = "prometheus"
  project      = var.project_id
}

resource "google_project_iam_binding" "metricWriter" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  members = [
    "serviceAccount:${google_service_account.prometheus_sa.email}",
  ]
}

resource "google_project_iam_binding" "resourceMetadataWriter" {
  project = var.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  members = [
    "serviceAccount:${google_service_account.prometheus_sa.email}",
  ]
}

resource "google_project_iam_binding" "logWriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  members = [
    "serviceAccount:${google_service_account.prometheus_sa.email}",
  ]
}

resource "google_project_iam_binding" "compteViewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  members = [
    "serviceAccount:${google_service_account.prometheus_sa.email}",
  ]
}


# Firewall rule to allow port 9090 to Prometheus
resource "google_compute_firewall" "prometheus_9090" {
  name    = "allow-prometheus-9090"
  network = google_compute_network.onemil_network.name

  allow {
    protocol = "tcp"
    ports    = ["9090"]
  }

  target_tags   = ["prometheus-server"]
  source_ranges = ["0.0.0.0/0"]
}

# Output Prometheus external IP
output "prometheus_external_ip" {
  description = "External IP address of the Prometheus server"
  value       = google_compute_instance.prom-scrapper.network_interface[0].access_config[0].nat_ip
}

