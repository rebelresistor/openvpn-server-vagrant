#!/usr/bin/env bash

OPENVPN_CONF=/etc/openvpn/server.conf


# Change to script directory
sd=`dirname $0`
cd $sd
# if you ran the script from its own directory you actually just got '.'
# so capture the abs path to wd now
sd=`pwd`

# Make sure config file exists
if [ ! -f ./config.sh ]; then
  echo "config.sh not found!"
  exit;
fi

# Load config
source ./config.sh
source ./interfaces.sh


# if no PUBLIC_IP was specified, then ask Amazon what it is!
if [ -z "$PUBLIC_IP" ]; then
	# query the AWS metadata service
	PUBLIC_IP=`curl -sm 1 http://169.254.169.254/latest/meta-data/public-ipv4`
	RSLT=$?
	if [ $RSLT -ne 0 ]; then
		echo "ERROR: no public IP address was specified, and the AWS metadata"
		echo "       service could not be queried. Please specify a PUBLIC_IP in"
		echo "       \"config.sh\" and try again."
		exit 1
	fi
fi

# Install OpenVPN and expect
apt-get -y install openvpn easy-rsa expect

# Set up the CA directory
make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# The latest version of the make-cadir command doesn't 
# create a single "openssl.cnf" file. It makes multiple:
#	openssl-0.9.6.cnf
#	openssl-0.9.8.cnf
#	openssl-1.0.0.cnf
# 
# Check the latest version exists and then move it into place
if [ ! -f "$OPENSSL_CONF_FILE" ]; then
	echo "ERROR: the openssl config file \"$OPENSSL_CONF_FILE\" was not found."
	echo "       Please specify the correct file and try again."
	exit 1
fi

cp "$OPENSSL_CONF_FILE" "openssl.cnf"

# Update vars
sed -i "s/export KEY_COUNTRY=\"[^\"]*\"/export KEY_COUNTRY=\"${KEY_COUNTRY}\"/" vars
sed -i "s/export KEY_PROVINCE=\"[^\"]*\"/export KEY_PROVINCE=\"${KEY_PROVINCE}\"/" vars
sed -i "s/export KEY_CITY=\"[^\"]*\"/export KEY_CITY=\"${KEY_CITY}\"/" vars
sed -i "s/export KEY_ORG=\"[^\"]*\"/export KEY_ORG=\"${KEY_ORG}\"/" vars
sed -i "s/export KEY_EMAIL=\"[^\"]*\"/export KEY_EMAIL=\"${KEY_EMAIL}\"/" vars
sed -i "s/export KEY_OU=\"[^\"]*\"/export KEY_OU=\"${KEY_OU}\"/" vars
sed -i "s/export KEY_NAME=\"[^\"]*\"/export KEY_NAME=\"server\"/" vars


function ensure_exists () {
	# a function to check a list of files exist, exit if they don't!
	for file in $@ ; do 
		if [ ! -f "$file" ]; then
			echo "ERROR: a required file \"$file\" was not created in the last step."
			echo "       Please check the logs above to see what failed."
			exit 2
		fi
	done
}

source vars
./clean-all

# Build the Certificate Authority
yes "" | ./build-ca
ensure_exists keys/ca.key

# Create the server certificate, key, and encryption files
$sd/build-key-server.sh
ensure_exists keys/server.crt keys/server.key

./build-dh
ensure_exists keys/dh2048.pem


openvpn --genkey --secret keys/ta.key
ensure_exists keys/ta.key

# Copy the files to the OpenVPN directory
cd ~/openvpn-ca/keys
cp ca.crt ca.key server.crt server.key ta.key dh2048.pem /etc/openvpn
gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz > $OPENVPN_CONF



### Adjust the OpenVPN configuration
sed -i "s/tls-auth ta.key 0.*/tls-auth ta.key 0\nkey-direction 0/" $OPENVPN_CONF
sed -i "s/cipher AES-256-CBC/cipher AES-128-CBC\nauth SHA256/" $OPENVPN_CONF
sed -i "s/;user nobody/user nobody/" $OPENVPN_CONF
sed -i "s/;group nogroup/group nogroup/" $OPENVPN_CONF

# this stuff is required to allow all traffic from clients to go through the tunnel
sed -i "s/;push \"redirect-gateway def1 bypass-dhcp\"/push \"redirect-gateway def1 bypass-dhcp\"/" $OPENVPN_CONF
sed -i "s/;push \"dhcp-option DNS 208.67.222.222\"/push \"dhcp-option DNS 208.67.222.222\"/" $OPENVPN_CONF
sed -i "s/;push \"dhcp-option DNS 208.67.220.220\"/push \"dhcp-option DNS 208.67.220.220\"/" $OPENVPN_CONF

# change the port to the specified one
sed -i "s/port 1194/port $OPENVPN_PORT/" $OPENVPN_CONF



# Allow IP forwarding
sed -i "s/#net.ipv4.ip_forward/net.ipv4.ip_forward/" /etc/sysctl.conf
sysctl -p

# Install iptables-persistent so that rules can persist across reboots
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
apt-get install -y iptables-persistent

# Edit iptables rules to allow for forwarding
iptables -t nat -A POSTROUTING -o tun+ -j MASQUERADE
iptables -t nat -A POSTROUTING -o $VPNDEVICE -j MASQUERADE

# Make iptables rules persistent across reboots
iptables-save > /etc/iptables/rules.v4



# change the firewall policy
sed -i "s/DEFAULT_FORWARD_POLICY=\"DROP\"/DEFAULT_FORWARD_POLICY=\"ACCEPT\"/" /etc/default/ufw

sudo ufw allow $OPENVPN_PORT/udp
sudo ufw allow OpenSSH

sudo ufw disable
yes "y" | sudo ufw enable


# Start and enable the OpenVPN service
systemctl start openvpn@server
systemctl enable openvpn@server

# Create the client config directory structure
mkdir -p ~/client-configs/files

# Create a base configuration
cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/base.conf
sed -i "s/remote my-server-1 1194/remote ${PUBLIC_IP} $OPENVPN_PORT/" ~/client-configs/base.conf
sed -i "s/;user nobody/user nobody/" ~/client-configs/base.conf
sed -i "s/;group nogroup/group nogroup/" ~/client-configs/base.conf
sed -i "s/ca ca.crt/#ca ca.crt/" ~/client-configs/base.conf
sed -i "s/cert client.crt/#cert client.crt/" ~/client-configs/base.conf
sed -i "s/key client.key/#key client.key/" ~/client-configs/base.conf
echo "cipher AES-128-CBC" >> ~/client-configs/base.conf
echo "auth SHA256" >> ~/client-configs/base.conf
echo "key-direction 1" >> ~/client-configs/base.conf
echo "#script-security 2" >> ~/client-configs/base.conf
echo "#up /etc/openvpn/update-resolv-conf" >> ~/client-configs/base.conf
echo "#down /etc/openvpn/update-resolv-conf" >> ~/client-configs/base.conf
