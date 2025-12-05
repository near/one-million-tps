#!/bin/bash
# Initialization script for a mocknet node.
set -exo pipefail


function initialize_tracer {
  apt update
  apt -y install docker-compose
  runuser -l ubuntu -c "git clone https://github.com/near/nearcore /home/ubuntu/nearcore"
  # fix docker compose file
  sed -i '1s/^/version: "3" \n/' /home/ubuntu/nearcore/tracing/docker-compose.yml

  # start docker compose in dettached mode
  cd /home/ubuntu/nearcore/tracing && docker-compose up -d
}

initialize_tracer

