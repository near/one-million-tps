data "google_compute_zones" "available" {
  region = var.region
}

data "google_project" "default" {}

# Query zones that support the required machine type
data "google_compute_machine_types" "check_availability" {
  for_each = toset(data.google_compute_zones.available.names)
  zone     = each.key
  filter   = "name = \"${var.machine_type}\""
}

resource "random_id" "server_suffix" {
  count = var.machine_count
  keepers = {
    # Generate a new id each time we switch these variables
    base_name = var.base_instance_name
    region    = var.region
    idx       = count.index
  }

  byte_length = 3
}

locals {
  zones_input = tolist(coalesce(var.zones, []))

  # Filter zones to only include those that have the required machine type available
  zones_with_machine_type = [
    for zone in data.google_compute_zones.available.names :
    zone if length(data.google_compute_machine_types.check_availability[zone].machine_types) > 0
  ]

  # Use user-provided zones if specified, otherwise use zones that have the machine type
  candidate_zones = length(local.zones_input) > 0 ? local.zones_input : local.zones_with_machine_type

  # Filter candidate zones to ensure they have the machine type available
  selected_zones = [
    for zone in local.candidate_zones :
    zone if contains(keys(data.google_compute_machine_types.check_availability), zone) &&
    length(data.google_compute_machine_types.check_availability[zone].machine_types) > 0
  ]

  # Validation: ensure we have at least one zone available
  has_available_zones = length(local.selected_zones) > 0
}

resource "google_compute_disk" "node_disk" {
  count = var.machine_count
  name  = format("%s-%s-1", var.base_instance_name, random_id.server_suffix[count.index].hex)
  zone  = element(local.selected_zones, count.index % length(local.selected_zones))
  type  = var.node_disk_type
  image = var.image_name != "" ? var.image_name : null
  size  = var.disk_size_gb

  # Optional Hyperdisk tuning
  lifecycle {
    precondition {
      condition     = var.node_disk_provisioned_throughput == null || contains(["hyperdisk-balanced", "hyperdisk-throughput"], var.node_disk_type)
      error_message = "Provisioned throughput is supported only for hyperdisk-balanced or hyperdisk-throughput."
    }
    precondition {
      condition     = var.node_disk_provisioned_iops == null || contains(["hyperdisk-balanced", "hyperdisk-extreme"], var.node_disk_type)
      error_message = "Provisioned IOPS is supported only for hyperdisk-balanced or hyperdisk-extreme."
    }
    precondition {
      condition     = local.has_available_zones
      error_message = "Machine type '${var.machine_type}' is not available in any zones in region '${var.region}'. Available zones in region: ${join(", ", data.google_compute_zones.available.names)}. Please choose a different machine type or region."
    }
  }

  provisioned_throughput = var.node_disk_provisioned_throughput
  provisioned_iops       = var.node_disk_provisioned_iops
}

# Create the specified number of instances distributed across the available zones
resource "google_compute_instance" "mocknet_instance" {
  count        = var.machine_count
  name         = format("%s-%s", var.base_instance_name, random_id.server_suffix[count.index].hex)
  machine_type = var.machine_type
  zone         = element(local.selected_zones, count.index % length(local.selected_zones))

  lifecycle {
    precondition {
      condition     = local.has_available_zones
      error_message = "Machine type '${var.machine_type}' is not available in any zones in region '${var.region}'. Available zones in region: ${join(", ", data.google_compute_zones.available.names)}. Zones with machine type: ${join(", ", local.zones_with_machine_type)}. Please choose a different machine type or region."
    }
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-minimal-2204-lts"
      type  = var.boot_disk_type
      size  = 200
    }
  }

  attached_disk {
    source      = google_compute_disk.node_disk[count.index].self_link
    device_name = google_compute_disk.node_disk[count.index].name
  }

  network_interface {
    network = var.mocknet_network.name
    access_config {
      // create external IP
    }
  }

  metadata_startup_script = templatefile(
    var.startup_script_path,
    merge(
      var.startup_script_args,
      {
        disk_name = google_compute_disk.node_disk[count.index].name
      }
    )
  )

  metadata = {
    enable-oslogin = "false"
  }

  labels = merge(
    var.machine_labels,
    var.extra_labels,
    count.index < var.monitoring_nodes_per_region ? var.monitoring_labels : {}
  )

  tags = var.tags
}

