#/bin/bash

sudo apt update
sudo apt upgrade -y
sudo apt install python3-pip -y

sudo apt install openjdk-17-jre-headless -y

sudo pip3 install azure-storage-blob -y
