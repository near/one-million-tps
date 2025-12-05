variable "region" {
  type        = string
  description = "Name of the deployed region, e.g. 'us-central1'"
}

variable "base_instance_name" {
  type = string
}

variable "machine_type" {
  type        = string
  description = "Machine type for new nodes (defines allocated CPU, RAM, etc)"
}

variable "boot_disk_type" {
  type        = string
  description = "Boot disk type (e.g., pd-ssd, hyperdisk-balanced, hyperdisk-extreme)"
  default     = "pd-ssd"
}

variable "disk_size_gb" {
  type        = number
  description = "Attached disk size in GB"
}

variable "node_disk_type" {
  type        = string
  description = "Disk type for the attached node data disk (e.g., pd-ssd, hyperdisk-balanced, hyperdisk-extreme)"
  default     = "pd-ssd"
}

variable "node_disk_provisioned_throughput" {
  type        = number
  description = "Provisioned throughput in MB/s (only for hyperdisk)"
  default     = null
}

variable "node_disk_provisioned_iops" {
  type        = number
  description = "Provisioned IOPS (only for hyperdisk)"
  default     = null
}

variable "image_size_gb" {
  type        = number
  description = "Image default size in GB"
  default     = 128
}

variable "machine_labels" {
  type        = map(any)
  description = "Labels for machine"
  default = {
    binary     = "neard",
    created_by = "terraform",
    owner      = "near-node-exp",
    repo       = "infra-ops"
    role       = "rpc"
  }
}

variable "extra_labels" {
  type        = map(any)
  description = "extra labels for machine"
  default     = {}
}

variable "monitoring_labels" {
  type        = map(any)
  description = "Labels for monitoring"
  default = {
    node_exporter = "true",
    prometheus    = "true",
  }
}

variable "monitoring_nodes_per_region" {
  type        = number
  description = "Number of monitored intances in the region"
  default     = 10
}

variable "tags" {
  type        = list(any)
  description = "Network tags for machine"
  default     = []
}

variable "machine_name" {
  type        = string
  description = "Network tags for machine"
  default     = "mocknet"
}

variable "machine_count" {
  type        = number
  description = "Number of intances in the region"
}

variable "image_name" {
  type    = string
  default = "true"
}

variable "startup_script_path" {
  type = string
}

variable "startup_script_args" {
  type = map(any)
}

variable "zones" {
  type        = list(string)
  description = "Optional list of zones within the region to place instances. If null or empty, all available zones in the region are used."
  default     = null
}

variable "mocknet_network" {
  default = null
}
