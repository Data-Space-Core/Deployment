# Deployment
There are two things that are needed to be in place to deploy the dataspace on the given host. 
First you need to have fully qualified domain name (FQDN) for the host. Sencond you need valid SSL 
certificates for the host machine that match the FQDN of the host. Once that is clear you can run the install script
````
sudo ./runner.sh
````
Script will ask your host FQDN and path where certificates are located. It will also ask for name of public certificate file and private key files. 

For certificates you should chain public certificates into one file. Chained certificate file simply all three certificates concanated one 
afther the other. The three certificates that are needed are: your host machine certificate, certificate authority intermediate certificate and the certificate
authority certificate. You will get all these from the SSL certificate package that you obtain. 

Private key (and certificate signing request) are created when you order certificates and are not part of the package that you get from certificate 
authority so remember to hold onto those. 

NOTE: If you need to re-run the runner script, delete the folder and re-clone the repository first. Install script replaces variables in the deployment files with
values you provide and re-running the script does not work as intended if previous run has already replaced those variables

# Included Components

This installation package include following dataspace components:

- IDSA Data Space Connector
- IDSA Omejdn DAPS Identity provider
- IDSA Omejdn DAPS Web User Interface
- IDSA Data Space Broker

It also provides supporting components

- PostgreSQL Database for data space connector persistency
- NGINX Reverse Proxy to act as gateway to the different components

# Usage

Here is shor list of available user interfaces in the Deployement:
## Conncetor
- https://<host>/connecor/api/docs - Swagger UI for the connector
## Broker
- https://<host>/broker/fuseki/
## DAPS 
- https://<host>/