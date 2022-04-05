# Installation Guide
An overview of the soltuion is below. There are two ways to install and configure the application: automated or manual. Only Ubuntu 20.04 is supported at this time.
# Automated Configuration and Deployment

1) Go to the Azure Portal <https://portal.azure.com/>, and click Azure Cloud Shell (First Icon next to the search box on the top).
If this is the first time you are using Azure Cloud Shell you might be asked to configure storage for this. Follow the configuration wizard.
2) **Clone the repository:** Next step is to clone this repository using the following command: `git clone https://github.com/djdean/PythonSyntheaFHIRClient.git`
3) `cd ./PythonSyntheaFHIRClient/IaC/`
4) Last step is to provision Infrastructure through the Bicep template. Provisioning needs to be initiated through the following commands.

The very first step is to create Service Account / Service Principal Name (SPN) for the application with the least privilege approach. You can specify 'Contributor' role at the resource group level but recommendation is to specify even lower permissions as needed.

```
az group create --name MyResourceGroupName --location MyLocation --subscription MySubscriptionId

az ad sp create-for-rbac --name MySPNName --role 'Contributor' --scopes /subscriptions/MySubscriptionId/resourceGroups/MyResourceGroupName --years 1 --subscription MySubscriptionId
```

After creation, you need to collect the information about SPN and credentials. You can see secret value as the output of the command. Copy and note the secret. You also need ClientId and ObjectId. For that, search in Azure Portal in search box 'Azure Active Directory', select it, click 'App Registrations', 'Owned Applications', search for the name of application you just created, click the application and click through the 'Managed application in local directory'.
Copy and note the value for the 'Application ID' (ClientID) and the ObjectId item for later use.

```
az deployment group create --resource-group MyResourceGroupName --template-file Synthea.bicep --parameters projectPrefix=specifyPrefix sqlServerLogin=specifySqlLogin sqlServerPassword=specifySqlPwd localAdminUserName='specifyVMLogin' localAdminPassword='specifyVMPwd' clientId='specifyClientId' objectId='specifyObjectId' clientSecret='specifyClientSecret' --subscription MySubscriptionId
```

Make sure you select good unique name for 'projectPrefix' to avoid name collisions for global names for Azure global resources. Select strong user name and password for SQL and VM credentials and provide information about SPN and its credentials. See previous section how to create SPN.

# Manual Configuration and Deployment
If manual configuration is needed, there are several steps which need to be followed in order to deploy the application. This guide assumes the following services have been configured and deployed already:<br/><br/> 1) *Azure Storage Account* <br/> 2) *[FHIR Importer App](https://github.com/microsoft/fhir-server-samples/tree/master/src/FhirImporter)*<br /> 3) *[FHIR to Synapse Sync Agent](https://github.com/microsoft/FHIR-Analytics-Pipelines/blob/main/FhirToDataLake/docs/Deployment.md)*<br /> 4) *Azure API for FHIR* <BR/> 5) *Azure Synapse Analytics* <Br/><Br/> Once all services have been deployed in the portal, run the following steps to finish the deployment of the solution:<br/>
1) **Clone the repository:** The first step is to clone this repository using the following command:<br /><br/>`git clone https://github.com/djdean/PythonSyntheaFHIRClient.git` <br /><br />
2) **Run the environment setup script:** Next, go to the "deployment/scripts" directory and run the following:<br /><br/>`./setup_environment.sh`<br /><br />This will update the apt package manager and also install all the necessary packages needed to run the application.
3) **Install synthea FHIR data generation tool:** After environment setup is complete, run the following command (located in the "deployment/scripts" directory)<br/><br/>`./install_synthea.sh`<br/><br/>This will install and configure Synthea.
4) **Configure and install the python FHIR client:** This step requires setting several variables:<br/>`connection_string=<Some value>`: The connection string for the Azure Storage Account created above.<br/>`polling_interval=<Rate in seconds>`: The rate, in seconds, for how frequently to check for new FHIR bundles.<br/>`FHIR_output_path=<Local FHIR path>`: The local directory to check for new FHIR bundles.<br/>`local_output_path=<Local output path>`: The local path for the Python daemon to output errors and uploaded data.<br/>`log_path=<Local log path>`: The local path to use to output log data.<br/>`container_name=<Storage Account container>`: The name of the container in the storage account to upload FHIR bundles. This should be the same container the FHIR Importer App, configured above, is monitoring.<br/><br/><br/>Once all of the variables above have been set, run the following script (located in the "deployment/scripts" directory) to configure and deploy the Python daemon:<br/><br/>`./install_python_client.sh $connection_string $polling_interval $FHIR_output_path $local_output_path $log_path $container_name`<br/>
