#!/usr/bin/env bash

KEY_COUNTRY="US"
KEY_PROVINCE="CA"
KEY_CITY="SanFrancisco"
KEY_ORG="Fort-Funston"
KEY_EMAIL="me@myhost.mydomain"
KEY_OU="MyOrganizationalUnit"

# only specify a public IP address if you're not running on 
# Amazon EC2. The instance meta-data service will be used 
# to query this! 
#
# WARNING: Configure an Elastic IP **BEFORE** installing this
#          otherwise you will have to manually configure the 
#          elastic IP in all the config files...
PUBLIC_IP=""

# select the active openssl config file
OPENSSL_CONF_FILE="openssl-1.0.0.cnf"

# change the port number to stop ISPs blocking access to this port
OPENVPN_PORT=443