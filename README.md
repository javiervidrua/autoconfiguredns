# autoconfiguredns
Automatically installs *Bind9* on your *Debian-based* system and does a base, working configuration so **in matter of seconds you have your own DNS server up and running**.

**It is meant to be used with a freshly installed system** but it also works on a system that already has *Bind9* installed, but it overwrites configuration files, so make sure to perform a backup before running it if this is your case.

This tool configures the Bind9 service to make it work as a Master server, and accepts all queries.

### **This is an insecure setup. Use at your own risk**.

## What does it do?
* Installs *Bind9* and its utilities (*bind9utils* and *dnsutils*)
* Checks if the service is working (if not it tries to start it)
* Checks if there is *UFW* installed (if it is, creates a new rule, if not, creates iptables rules)
* Configures *"named.conf.options"*
* Configures *"named.conf.local"*
* Creates *"forward.your.domain"* and configures it
* Creates *"reverse.your.domain"* and configures it
* Updates *"/etc/resolv.conf"* so the system uses its own *DNS* service
* Makes sure everything works

## Usage
`./autoconfiguredns.sh <IN_IP_ADDRESS> <FQDN>`

## Example
If my Internet IP is '*10.10.10.51*' and my FQDN is '*test.com*', I would run:

`./autoconfiguredns 10.10.10.51 test.com`
