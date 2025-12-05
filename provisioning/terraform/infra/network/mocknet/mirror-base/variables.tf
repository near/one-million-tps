variable "project_id" {
  type        = string
  default     = "nearone-mocknet"
  description = "GCP project that you want to use for your resources"
}

variable "nodes_location" {
  type    = map(string)
  default = {}
}

variable "zones_per_region" {
  type        = map(list(string))
  default     = {}
  description = "Optional per-region list of zones to use for nodes."
}

variable "machine_type" {
  type    = string
  default = "n2d-standard-8"
}

variable "boot_disk_type" {
  type        = string
  default     = "pd-ssd"
  description = "Disk type for the boot disk (e.g., pd-ssd, hyperdisk-balanced, hyperdisk-extreme)"
}

variable "node_disk_type" {
  type        = string
  default     = "pd-ssd"
  description = "Disk type for the node data disk (e.g., pd-ssd, hyperdisk-balanced, hyperdisk-extreme)"
}

variable "node_disk_provisioned_throughput" {
  type        = number
  default     = null
  description = "Provisioned throughput in MB/s for Hyperdisk (balanced/throughput)."
}

variable "node_disk_provisioned_iops" {
  type        = number
  default     = null
  description = "Provisioned IOPS for Hyperdisk (balanced/extreme)."
}

variable "unique_id" {
  type        = string
  default     = null
  description = "The unique identifier for the network"
}

variable "chain_id" {
  type        = string
  default     = "mainnet"
  description = "The chain ID of an available test case. run util.sh ls-test-cases to see what's available"
}

variable "start_height" {
  type        = number
  default     = 0
  description = "The start height of an available test case. run util.sh ls-test-cases to see what's available"
}

variable "mocknet_id" {
  type        = string
  default     = null
  description = "Unique identifier for the mocknet instance. This overwrites the (chain_id, start_height, unique_id) tuple"
}

variable "tracing_server_region" {
  type        = string
  default     = null
  description = "Region for tracing server. If not specified, uses the first region from nodes_location"
}

variable "tracing_server_zone" {
  type        = string
  default     = null
  description = "Zone for tracing server. If not specified, automatically selects a zone that supports the required machine type"
}

variable "tracing_server" {
  type    = bool
  default = false
}
variable "tracing_server_machine_type" {
  type        = string
  default     = null
  description = "Host type of the tracing server. By default will be machine_type of other nodes."
}

# If your disk image cannot be identified by chain_id and height, you can use this variable.
variable "node_image" {
  type        = string
  default     = null
  description = "Name of the image that is going to be mounted on the nodes. Only use this one if you are not setting up a mocknet with traffic mirroring"
}

variable "cp_monitoring_nodes_per_region" {
  type        = number
  description = "Number of monitored producers intances in the region"
  default     = 10
}

variable "cv_monitoring_nodes_per_region" {
  type        = number
  description = "Number of monitored chunk validators intances in the region"
  default     = 10
}

########################################
#  Variables for the chunk validator.  #
########################################

variable "cv_nodes_location" {
  type    = map(string)
  default = {}
}

variable "cv_zones_per_region" {
  type        = map(list(string))
  default     = {}
  description = "Optional per-region list of zones to use for CV nodes."
}

variable "cv_disk_size_gb" {
  type        = number
  default     = 100
  description = "The size of the disk attached to the chunk validator host."
}

variable "cv_machine_type" {
  type        = string
  default     = "n2d-standard-4"
  description = "Host type of the chunk validators."
}

variable "node_disk_extra_gb" {
  type        = number
  default     = 1418
  description = "Extra GB to add to base image size for neard node disks"
}
