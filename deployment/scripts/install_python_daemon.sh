#/bin/bash
connection_string=$1		#Azure Storage account connection string to upload the data to 
polling_interval=$2		#The rate at which to check for new data
FHIR_output_path=$3		#The local directory to check for FHIR bundles
local_output_path=$4		#The local path to move uploaded FHIR data to after being stored in Azure
log_path=$5			#The path to send the log file to
container_name=$6		#The container name to upload the data to in the Azure Storage account
###Write the config file for the deamon###
echo "Writing config file..."

content=$'{\n"connection_string":"'"${connection_string}"$'",\n"polling_interval":"'"${polling_interval}"$'",\n"FHIR_output_path":"'"${FHIR_output_path}"$'",\n"local_output_path":"'"${local_output_path}"$'",\n"log_path":"'"${log_path}"$'",\n"container_name":"'"${container_name}"$'"\n}'

echo "$content" > ./PythonSyntheaFHIRClient/python_client/deploy_config.json
