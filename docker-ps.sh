#!/usr/bin/env bash

GREEN="\033[1;32m"  # Bold green
BLUE="\033[0;34m"   # Regular blue (not bold)
RESET="\033[0m"

sudo docker ps --format "table {{.ID}}\t{{.Names}}\t{{.RunningFor}}\t{{.Status}}\t{{.Image}}" | {
    read -r header
    echo -e "${GREEN}$header${RESET}"
    sort -k2 | while IFS= read -r line; do
        echo -e "${BLUE}$line${RESET}"
    done
}
