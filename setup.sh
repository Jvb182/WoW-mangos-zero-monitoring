#!/bin/bash
echo "Setting data directory permissions..."
sudo chown -R 472:472 grafana/data/
sudo chown -R 10001:10001 loki/data/
sudo chown -R 65534:65534 prometheus/data/
echo "Done! Run: docker compose up -d"