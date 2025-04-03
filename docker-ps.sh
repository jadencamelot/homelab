#!/usr/bin/env bash

sudo docker ps --format "table {{.ID}}\t{{.Names}}\t{{.RunningFor}}\t{{.Status}}\t{{.Image}}" | { read -r header; echo "$header"; sort -k2; }
