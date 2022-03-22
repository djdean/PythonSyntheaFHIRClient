#/bin/bash
#####Clone the git repo#############
git clone https://github.com/jbinko/PythonSyntheaFHIRClient.git
#####Run the environment setup script##########
./setup_environment.sh
#####Build and install Synthea###########
./install_synthea.sh
#####Build and install the python deamon##########
./install_python_client.sh

