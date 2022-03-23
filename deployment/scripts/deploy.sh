#/bin/bash
#####Clone the git repo#############
git clone https://github.com/djdean/PythonSyntheaFHIRClient.git
#####Run the environment setup script##########
./PythonSyntheaFHIRClient/deployment/scripts/setup_environment.sh
#####Build and install Synthea###########
./PythonSyntheaFHIRClient/deployment/scripts/install_synthea.sh
#####Build and install the python deamon##########
connection_string=$1		#Azure Storage account connection string to upload the data to 
polling_interval=$2		#The rate at which to check for new data
FHIR_output_path=$3		#The local directory to check for FHIR bundles
local_output_path=$4		#The local path to move uploaded FHIR data to after being stored in Azure
log_path=$5			#The path to send the log file to
container_name=$6		#The container name to upload the data to in the Azure Storage account
./PythonSyntheaFHIRClient/deployment/scripts/install_python_client.sh $connection_string $polling_interval $FHIR_output_path $local_output_path $log_path $container_name

