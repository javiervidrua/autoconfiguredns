#! /usr/bin/env bash

# autoconfiguredns version 0.5.0

# Creates iptables rules to allow bind9 go though
# allowBind9iptables <LOCAL_IP_ADDRESS>
allowBind9iptables(){ # Implement this
    echo '[*] Creating iptables rules to allow the service to do its job'
    # Allow outgoing client requests to other servers
    iptables -A OUTPUT -p udp -s $1 --sport 1024:65535 --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A INPUT -p udp --sport 53 -d $1 --dport 1024:65535 -m state --state ESTABLISHED -j ACCEPT
    iptables -A OUTPUT -p tcp -s $1 --sport 1024:65535 --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A INPUT -p tcp --sport 53 -d $1 --dport 1024:65535 -m state --state ESTABLISHED -j ACCEPT

    #Allow incoming DNS queries to the server on port 53
    #Do not allow TCP so no zone transfers allowed
    iptables -A OUTPUT -p udp -s $1 --sport 53 -d 0/0 --dport 1024:65535 -m state --state ESTABLISHED -j ACCEPT
    iptables -A INPUT -p udp -s 0/0 --sport 1024:65535 -d $1 --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A OUTPUT -p udp -s $1 --sport 53 -d 0/0 --dport 53 -m state --state ESTABLISHED -j ACCEPT
    iptables -A INPUT -p udp -s 0/0 --sport 53 -d $1 --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
}

# Checks the arguments passed to the script
checkArguments(){
    if [ $# -ne 2 ]; then
        usage
        return 1
    fi
}

# Checks if the server is running and if not, tries to start it.
checkServerWorks(){
    echo '[*] Checking if the server is working'
    nslookup google.com 127.0.0.1 >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo '[-] Error: Bind9 server not working. Trying to start the service...'
        /etc/init.d/bind9 restart
        service bind9 status > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo '[*] The bind9 server is now running.'
            return 0
        else
            echo '[-] Error: Could not start the Bind9 server. Try to do it youself by runnining this command:'
            echo ''
            echo '/etc/init.d/bind9 restart'
            echo ''
            echo '[-] Then, relaunch this script.'
            return 1
        fi
    else
        return 0
    fi
}

# Checks if there is ufw installed, if it is, tries to allow Bind9 through it, and if not, calls allowBind9UsingIptables()
checkFirewallInstalled(){
    which ufw >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        # ufw installed
        ufw allow bind9
        if [ $? -eq 0 ]; then
            echo '[*] Bind9 is allowed through the firewall'
            return 0
        else
            echo '[-] Error: Could not allow Bind9 through the firewall'
            return 1
        fi
    else
        # ufw not installed, allow through iptables
        allowBind9iptables()
        if [ $? -eq 0 ]; then
            echo '[*] Bind9 is allowed through iptables'
            return 0
        else
            echo '[-] Error: Could not allow Bind9 through iptables'
            return 1
        fi
    fi
}

# Checks if script was run as root
checkRoot(){
    if [ $EUID -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Configures everything
# configureAll <LOCAL_IP_ADDRESS> <FULL_DOMAIN_NAME>
configureAll(){
    installBind
    if [ $? -eq 1 ]; then
        return 1
    fi
    checkServerWorks
    if [ $? -eq 1 ]; then
        return 1
    fi
    checkFirewallInstalled
    if [ $? -eq 1 ]; then
        return 1
    fi
    configureNamedConfOptions $1
    if [ $? -eq 1 ]; then
        return 1
    fi
    restartService
    if [ $? -eq 1 ]; then
        return 1
    fi
    configureConfLocal $1 $2
    if [ $? -eq 1 ]; then
        return 1
    fi
    restartService
    if [ $? -eq 1 ]; then
        return 1
    fi
    configureZone $1 $2
    if [ $? -eq 1 ]; then
        return 1
    fi
    configureReverseZone $1 $2
    if [ $? -eq 1 ]; then
        return 1
    fi
    restartService
    if [ $? -eq 1 ]; then
        return 1
    fi
    updateResolvConf $1 $2
    if [ $? -eq 1 ]; then
        return 1
    fi
    host ns1.$2
    if [ $? -eq 0 ]; then
        echo '[*] Looks like everything went well!'
        echo '[*] Try to query the server and see if it works!'
        return 0
    else
        echo '[-] Error: Looks like the DNS is not working!'
        echo '[-] Check the config directory and restart the service'
        return 1
    fi
}

# Configures /etc/bind/named.conf.local to create the new zone
# configureConfLocal <LOCAL_IP_ADDRESS> <FULL_DOMAIN_NAME>
configureConfLocal(){
    echo '[*] Creating a new zone in the /etc/bind/named.conf.local file'
    mv /etc/bind/named.conf.local /etc/bind/named.conf.local.old
    echo "//" >> /etc/bind/named.conf.local
    echo "// Do any local configuration here" >> /etc/bind/named.conf.local
    echo "//" >> /etc/bind/named.conf.local
    echo "" >> /etc/bind/named.conf.local
    echo "// Consider adding the 1918 zones here, if they are not used in your" >> /etc/bind/named.conf.local
    echo "// organization" >> /etc/bind/named.conf.local
    echo "//include "'"'"/etc/bind/zones.rfc1918"'"'";" >> /etc/bind/named.conf.local
    echo "" >> /etc/bind/named.conf.local
    echo "// autoconfiguredns" >> /etc/bind/named.conf.local
    echo "zone "'"'$2'"'" {" >> /etc/bind/named.conf.local
    echo "      type master;" >> /etc/bind/named.conf.local
    echo "      file "'"'"/etc/bind/forward.$2"'"'";" >> /etc/bind/named.conf.local
    echo "};" >> /etc/bind/named.conf.local
    FIRST=`echo $1 | cut -d. -f1`
    SECOND=`echo $1 | cut -d. -f2`
    THIRD=`echo $1 | cut -d. -f3`
    FOURTH=`echo $1 | cut -d. -f4`
    echo "zone "'"'$FOURTH.$THIRD.$SECOND.$FIRST.in-addr-arpa'"'" {" >> /etc/bind/named.conf.local
    echo "      type master;" >> /etc/bind/named.conf.local
    echo "      file "'"'"/etc/bind/reverse.$1"'"'";" >> /etc/bind/named.conf.local
    echo "};" >> /etc/bind/named.conf.local

    named-checkconf
    if [ $? -eq 0 ];then
         echo '[*] named.conf.local file configured successfully'
         return 0
    else
        echo '[-] Error: named.conf.local file misconfigurated'
        echo '[*] Restoring default file'
        mv /etc/bind/named.conf.local.old /etc/bind/named.conf.local
        named-checkconf
        if [ $? -eq 0 ];then
            echo '[*] named.conf.local file restored successfully'
            return 0
        else
            echo '[-] Error: Restored named.conf.local file has errors. Please check it and fix those errors.'
            return 1
        fi
    fi
}

# Configures /etc/bind/named.conf.options so it listens on the specified interface
# configureNamedConfOptions <LOCAL_IP_ADDRESS>
configureNamedConfOptions(){
    echo '[*] Configuring /etc/bind/named.conf.options file for your IP'
    # Configure named.conf.options
    mv /etc/bind/named.conf.options /etc/bind/named.conf.options.old
    echo "options {" >> /etc/bind/named.conf.options
    echo "        directory "'"'"/var/cache/bind"'"'";" >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        // If there is a firewall between you and nameservers you want" >> /etc/bind/named.conf.options
    echo "        // to talk to, you may need to fix the firewall to allow multiple" >> /etc/bind/named.conf.options
    echo "        // ports to talk.  See http://www.kb.cert.org/vuls/id/800113" >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        // If your ISP provided one or more IP addresses for stable" >> /etc/bind/named.conf.options
    echo "        // nameservers, you probably want to use them as forwarders." >> /etc/bind/named.conf.options
    echo "        // Uncomment the following block, and insert the addresses replacing" >> /etc/bind/named.conf.options
    echo "        // the all-0's placeholder." >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        // autoconfiguredns" >> /etc/bind/named.conf.options
    echo "        forwarders {" >> /etc/bind/named.conf.options
    echo "             8.8.8.8;" >> /etc/bind/named.conf.options
    echo "             8.8.4.4;" >> /etc/bind/named.conf.options
    echo "        };" >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        //========================================================================" >> /etc/bind/named.conf.options
    echo "        // If BIND logs error messages about the root key being expired," >> /etc/bind/named.conf.options
    echo "        // you will need to update your keys.  See https://www.isc.org/bind-keys" >> /etc/bind/named.conf.options
    echo "        //========================================================================" >> /etc/bind/named.conf.options
    echo "        dnssec-validation auto;" >> /etc/bind/named.conf.options
    echo "        auth-nxdomain no;" >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        listen-on-v6 { any; };" >> /etc/bind/named.conf.options
    echo "        listen-on port 53 { any; };" >> /etc/bind/named.conf.options
    echo "        allow-query { any; };" >> /etc/bind/named.conf.options
    echo "        recursion yes;" >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        // hide version number from clients for security reasons." >> /etc/bind/named.conf.options
    echo "        version "'"'"not currently available"'"'";" >> /etc/bind/named.conf.options
    echo "        // to check -> dig -c CH -t txt version.bind @localhost" >> /etc/bind/named.conf.options
    echo "        // enable the query log" >> /etc/bind/named.conf.options
    echo "        querylog yes;" >> /etc/bind/named.conf.options
    echo "        // disallow zone transfer" >> /etc/bind/named.conf.options
    echo "        allow-transfer { none; };" >> /etc/bind/named.conf.options
    echo "};" >> /etc/bind/named.conf.options

    named-checkconf /etc/bind/named.conf.options
    if [ $? -eq 0 ];then
         echo '[*] named.conf.options file configured successfully'
         return 0
    else
        echo '[-] Error: named.conf.options file misconfigurated'
        echo '[*] Restoring default file'
        mv /etc/bind/named.conf.options.old /etc/bind/named.conf.options
        named-checkconf
        if [ $? -eq 0 ];then
            echo '[*] named.conf.options file restored successfully'
            return 0
        else
            echo '[-] Error: Restored named.conf.options file has errors. Please check it and fix those errors.'
            return 1
        fi
    fi
}

# Configures the new zone file /etc/bind/forward.<FULL_DOMAIN_NAME>
# configureZone <LOCAL_IP_ADDRESS> <FULL_DOMAIN_NAME>
configureZone(){
    echo '[*] Creating and configuring the zone file /etc/bind/forward.$2'
    echo '' >/etc/bind/forward.$2
    
    echo "; autoconfiguredns" >> /etc/bind/forward.$2
    echo '$TTL 86400' >> /etc/bind/forward.$2
    echo "@     IN      SOA     ns1.$2.     root.ns1.$2. (" >> /etc/bind/forward.$2
    echo "                      2           ; serial" >> /etc/bind/forward.$2
    echo "                      21600       ; refresh after 6 hours" >> /etc/bind/forward.$2
    echo "                      3600        ; retry after 1 hour" >> /etc/bind/forward.$2
    echo "                      604800      ; expire after 1 week" >> /etc/bind/forward.$2
    echo "                      86400 )     ; minimum TTL of 1 day" >> /etc/bind/forward.$2
    echo ";" >> /etc/bind/forward.$2
    echo "@     IN      NS      ns1.$2." >> /etc/bind/forward.$2
    echo ";" >> /etc/bind/forward.$2
    echo "ns1   IN      A       $1" >> /etc/bind/forward.$2
    echo "$2.   IN      A       $1" >> /etc/bind/forward.$2

    named-checkzone $2 /etc/bind/forward.$2
    if [ $? -eq 0 ];then
         echo "[*] /etc/bind/forward.$2 file configured successfully"
         return 0
    else
        echo "[-] Error: /etc/bind/forward.$2 file has errors. Please check it and fix those errors."
        return 1
    fi
}

# Configures the new reverse zone file /etc/bind/reverse.<FULL_DOMAIN_NAME>
# configureReverseZone <LOCAL_IP_ADDRESS> <FULL_DOMAIN_NAME>
configureReverseZone(){
    echo '[*] Creating and configuring the zone file /etc/bind/reverse.$2'
    echo '' >/etc/bind/reverse.$2
    
    echo "; autoconfiguredns" >> /etc/bind/reverse.$2
    echo '$TTL 86400' >> /etc/bind/reverse.$2
    echo "@     IN      SOA     $2.         root.$2. (" >> /etc/bind/reverse.$2
    echo "                      2           ; serial" >> /etc/bind/reverse.$2
    echo "                      21600       ; refresh after 6 hours" >> /etc/bind/reverse.$2
    echo "                      3600        ; retry after 1 hour" >> /etc/bind/reverse.$2
    echo "                      604800      ; expire after 1 week" >> /etc/bind/reverse.$2
    echo "                      86400 )     ; minimum TTL of 1 day" >> /etc/bind/reverse.$2
    echo ";" >> /etc/bind/reverse.$2
    echo "@     IN      NS      ns1.$2." >> /etc/bind/reverse.$2
    echo "ns1   IN      A       $1" >> /etc/bind/reverse.$2
    echo ";" >> /etc/bind/reverse.$2
    FOURTH=`echo $1 | cut -d. -f4`
    echo "$FOURTH   IN      PTR     ns1.$2." >> /etc/bind/reverse.$2

    named-checkzone $2 /etc/bind/reverse.$2
    if [ $? -eq 0 ];then
         echo "[*] /etc/bind/reverse.$2 file configured successfully"
         return 0
    else
        echo "[-] Error: /etc/bind/reverse.$2 file has errors. Please check it and fix those errors."
        return 1
    fi
}

# Updates the system and tries to install bind9
installBind(){
    echo '[*] Updating your system and installing Bind9'
    apt update && apt install bind9 bind9utils dnsutils -y
    if [ $? -eq 0 ]; then
        echo '[*] System updated and bind9 installed successfully'
        return 0
    else
        echo '[-] Error: Could not install bind9 on your system'
        return 1
    fi
}

# Alias for restarting the service
restartService(){
    echo '[*] Restarting the nameserver'
    if [ -e /etc/init.d/named ]; then
        /etc/init.d/named restart
        if [ $? -eq 1 ]; then
            return 1
        fi
        return 0
    elif [ -e /etc/init.d/bind9 ]; then
        /etc/init.d/bind9 restart
        if [ $? -eq 1 ]; then
            return 1
        fi
        return 0
    fi
}

# Updates the file /etc/resolv.conf
# updateResolvConf <LOCAL_IP_ADDRESS> <FULL_DOMAIN_NAME>
updateResolvConf(){
    echo '[*] Updating /etc/resolv.conf to use the new DNS server'
    echo "" > /etc/resolv.conf
    echo "search $2" >> /etc/resolv.conf
    echo "nameserver $1" >> /etc/resolv.conf
    return 0
}

# Prints the usage
usage(){
    echo 'Usage: ./autoconfiguredns.sh <IN_IP_ADDRESS> <FQDN>'
    echo ''
    echo 'EXAMPLE: If the IP address of my network card is 10.1.2.3 and my FQDN is test.com, I will run: ./autoconfiguredns.sh 10.1.2.3 test.com'
    return 0
}

# MAIN
checkArguments $@ # $@ is an array with all the arguments passed to the program
if [ $? -ne 0 ]; then
    exit 1
fi
checkRoot
if [ $? -ne 0 ]; then
    echo '[-] You must run this script as root.'
    exit 1
fi
configureAll $@ && exit 0
