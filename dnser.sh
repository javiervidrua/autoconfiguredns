#! /usr/bin/env bash

# dnser version 0.1

# Creates iptables rules to allow bind9 go though
allowBind9iptables(){ # Implement this
    return 1
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
        /etc/init.d/named restart
        service named status > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo '[*] The bind9 server is now running.'
            return 0
        else
            echo '[-] Error: Could not start the Bind9 server. Try to do it youself by runnining this command:'
            echo ''
            echo '/etc/init.d/named restart'
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
    which ufw >/dev/null 2>1
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
            echo '[*] Bind9 is allowed through the firewall'
            return 0
        else
            echo '[-] Error: Could not allow Bind9 through the firewall'
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
# configureAll <LOCAL_IP_ADDRESS> <FULL_DOMAIN_NAME> <IP_OF_ONE_DNS_SERVER_ALLOWED_TO_ZONE_TRANSFER>
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
    createZone $2 $3
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
    restartService
    if [ $? -eq 1 ]; then
        return 1
    fi

    echo '[*] Looks like everything went well!'
    echo '[*] Try to query the server and see if it works!'
    return 0
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
    echo "        // dnser" >> /etc/bind/named.conf.options
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
    echo "" >> /etc/bind/named.conf.options
    echo "        listen-on-v6 { any; };" >> /etc/bind/named.conf.options
    echo "};" >> /etc/bind/named.conf.options

    named-checkconf
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

# Configures the new zone file /etc/bind/db.<FULL_DOMAIN_NAME>
# configureZone <LOCAL_IP_ADDRESS> <FULL_DOMAIN_NAME>
configureZone(){
    echo '[*] Creating and configuring the zone file /etc/bind/db.$2'
    echo '' >/etc/bind/db.$2
    
    echo "; dnser" >> /etc/bind/db.$2
    echo '$ORIGIN $2' >> /etc/bind/db.$2
    echo '$TTL 86400' >> /etc/bind/db.$2
    echo "@     IN      SOA     $2.    hostmaster.$2. (" >> /etc/bind/db.$2
    echo "                      2       ; serial" >> /etc/bind/db.$2
    echo "                      21600   ; refresh after 6 hours" >> /etc/bind/db.$2
    echo "                      3600    ; retry after 1 hour" >> /etc/bind/db.$2
    echo "                      604800  ; expire after 1 week" >> /etc/bind/db.$2
    echo "                      86400 ) ; minimum TTL of 1 day" >> /etc/bind/db.$2
    echo ";" >> /etc/bind/db.$2
    echo "      IN      A       $1" >> /etc/bind/db.$2
    echo "@     IN      NS      localhost" >> /etc/bind/db.$2
    #echo "@     IN     TXT    google-site-verification=6tTalLzrBXBO4Gy9700TAbpg2QTKzGYEuZ_Ls69jle8 ;Google verification code" >> /etc/bind/db.$2
    #echo ";" >> /etc/bind/db.$2
    #echo "      IN     NS     $(hostname)" >> /etc/bind/db.$2
    #echo ";" >> /etc/bind/db.$2
    #echo "      IN     MX     10     mail.$2. ; 10 is a number of preference ; lower means more preference" >> /etc/bind/db.$2
    #echo "      IN     MX     20     mail2.$2. ; 20 is a number of preference ; this has lower preference that the previous one" >> /etc/bind/db.$2
    #echo ";" >> /etc/bind/db.$2
    #echo "$(hostname)         IN     A       127.0.0.1" >> /etc/bind/db.$2
    #echo "server1      IN     A       127.0.0.1" >> /etc/bind/db.$2
    #echo "$(hostname)         IN     AAAA    ::1" >> /etc/bind/db.$2
    #echo "ftp          IN     CNAME   server1" >> /etc/bind/db.$2
    #echo "mail         IN     CNAME   server1" >> /etc/bind/db.$2
    #echo "mail2        IN     CNAME   server1" >> /etc/bind/db.$2
    #echo "www          IN     CNAME   server1" >> /etc/bind/db.$2
    return 0
}

# Configures /etc/bind/named.conf.local to create the new zone
# createZone <FULL_DOMAIN_NAME>
createZone(){
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
    echo "// dnser" >> /etc/bind/named.conf.local
    echo "zone "$1" {" >> /etc/bind/named.conf.local
    echo "      type master;" >> /etc/bind/named.conf.local
    echo "      file "'"'"/etc/bind/db.$1"'"'";" >> /etc/bind/named.conf.local
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

# Updates the system and tries to install bind9
installBind(){
    echo '[*] Updating your system and installing Bind9'
    apt update && apt install bind9 -y
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
    /etc/init.d/named restart
}

# Prints the usage
usage(){
    echo 'USAGE: ./dnser.sh <IP_ADDRESS (not 127.0.0.1)> <FULL_DOMAIN_NAME>'
    echo ''
    echo 'EXAMPLE: If my network address is 192.168.1.11 and my FQDN is test.com, I will run: ./dnser.sh 192.168.1.11 test.com'
}

# MAIN
checkArguments $@ # $@ is an array with all the arguments passed to the program
if [ $? -ne 0 ]; then
    exit 1
fi
checkRoot
if [ $? -ne 0 ]; then
    echo '[-] YOU MUST RUN THIS SCRIPT AS ROOT'
    exit 1
fi
configureAll $@ && exit 0
