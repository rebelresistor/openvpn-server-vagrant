# openvpn-server-vagrant

Spin up an OpenVPN Server and tunnel your traffic through it, to bypass region locking.

## Requirements

This script was designed to work with Ubuntu Server 18.04 on Amazon EC2.

## Set up

    $ git clone https://github.com/rebelresistor/openvpn-server-vagrant.git
    $ cd openvpn-server-vagrant
    $ sudo ./ubuntu.sh
    $ cp config-default.sh config.sh

Edit config.sh, filling in your config details

    $ nano config.sh

Install:

    $ sudo ./openvpn.sh

## Add a client

The following should be repeated for each new client/user for whom you wish to grant access to your VPN. Replace client-name with a unique name.

    $ sudo su -
    $ add-config.sh client-name

You will then find a file like the following that you should provide to the individual who will be connecting to your VPN. This ovpn file can then be used with Tunnelblick (OS X), OpenVPN (Linux, iOS, Android and Windows).

    ~/client-configs/files/client-name.ovpn


## Revoke client certificate

If you ever need to revoke access, simply execute:

    $ sudo su -
    $ revoke-full.sh client-name


## Extra Info

* See [Using a VPN Server to Connect to Your AWS VPC for Just the Cost of an EC2 Nano Instance](https://medium.com/@redgeoff/using-a-vpn-server-to-connect-to-your-aws-vpc-for-just-the-cost-of-an-ec2-nano-instance-3c81269c71c2)
* See [How To Set Up an OpenVPN Server on Ubuntu 16.04](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-openvpn-server-on-ubuntu-16-04)
