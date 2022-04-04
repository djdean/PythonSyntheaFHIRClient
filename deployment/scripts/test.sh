#/bin/bash
mkdir /home/synthea
sudo chmod 744 /home/synthea/
cd /home/synthea
git clone https://github.com/djdean/PythonSyntheaFHIRClient.git

sudo apt update
sudo apt upgrade -y
sudo apt install python3-pip -y
sudo apt install default-jdk -y
sudo pip3 install azure-storage-blob

git clone https://github.com/synthetichealth/synthea.git
cd synthea 
./gradlew build -x check -x test

connection_string=$1		#Azure Storage account connection string to upload the data to 
polling_interval=$2		#The rate at which to check for new data
FHIR_output_path=$3		#The local directory to check for FHIR bundles
local_output_path=$4		#The local path to move uploaded FHIR data to after being stored in Azure
log_path=$5			#The path to send the log file to
container_name=$6		#The container name to upload the data to in the Azure Storage account

echo "Writing config file..."
content_string="{"$'\n'
content_string+=$(printf '%s' $'\t'"\"connection_string\":\"$connection_string\"",)$'\n'
content_string+=$(printf '%s' $'\t'"\"polling_interval\":\"$polling_interval\"",)$'\n'
content_string+=$(printf '%s' $'\t'"\"FHIR_output_path\":\"$FHIR_output_path\"",)$'\n'
content_string+=$(printf '%s' $'\t'"\"local_output_path\":\"$local_output_path\"",)$'\n'
content_string+=$(printf '%s' $'\t'"\"log_path\":\"$log_path\"",)$'\n'
content_string+=$(printf '%s' $'\t'"\"container_name\":\"$container_name\"")$'\n'
content_string+="}"
echo "$content_string" > ./../PythonSyntheaFHIRClient/deployment/scripts/deploy_config.json

echo "Done!"
