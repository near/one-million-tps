output "tracer_public_ip" {
  value = var.tracing_server == true ? google_compute_instance.tracing_server[0].network_interface.0.access_config.0.nat_ip : null
}
