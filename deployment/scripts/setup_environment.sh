#/bin/bash

sudo apt update
sudo apt upgrade -y
sudo apt install jq -y
sudo apt install python3-pip -y

sudo apt install default-jdk -y

sudo pip3 install azure-storage-blob
