# dnser
Automatizes the process of installing bind9 on a Debian-based system and configuring all the files so it works for your domain.

## Usage
`./dnser.sh <IN_IP_ADDRESS> <FULL_DOMAIN_NAME>'`

## What does it do?
* Installs bind9 and its utilities
* Checks if the service is working (if not it tries to start it)
* Checks if there is UFW installed (if it is, creates a new rule, if not, creates iptables rules)
* Configures named.conf.options
* Configures named.conf.local
* Creates forward.your.domain and configures it
* Creates reverse.your.domain and configures it
* Updates /etc/resolv.conf so the system uses its own DNS service
* Makes sure everything works
