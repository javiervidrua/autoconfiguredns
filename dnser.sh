#! /usr/bin/env bash


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
        sudo /etc/init.d/named restart
        service named status > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo '[*] The bind9 server is now running.'
            return 0
        else
            echo '[-] Error: Could not start the Bind9 server. Try to do it youself by runnining this command:'
            echo ''
            echo 'sudo /etc/init.d/named restart'
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
        sudo ufw allow bind9
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

# Configures everything
configureAll(){
    sudo install
    if [ $? -eq 1 ]; then
        return 1
    fi
    sudo checkServerWorks
    if [ $? -eq 1 ]; then
        return 1
    fi
    sudo checkFirewallInstalled
    if [ $? -eq 1 ]; then
        return 1
    fi
    sudo configureNamedConfOptions $1
    if [ $? -eq 1 ]; then
        return 1
    fi
    sudo /etc/init.d/named restart
    if [ $? -eq 1 ]; then
        return 1
    fi

    return 0
}

# Configures /etc/bind/named.conf.options so it listens on the specified interface
# sudo configureNamedConfOptions <IP_ADDRESS>
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
    echo "        // forwarders {" >> /etc/bind/named.conf.options
    echo "        //      0.0.0.0;" >> /etc/bind/named.conf.options
    echo "        // };" >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        //========================================================================" >> /etc/bind/named.conf.options
    echo "        // If BIND logs error messages about the root key being expired," >> /etc/bind/named.conf.options
    echo "        // you will need to update your keys.  See https://www.isc.org/bind-keys" >> /etc/bind/named.conf.options
    echo "        //========================================================================" >> /etc/bind/named.conf.options
    echo "        dnssec-validation auto;" >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        listen-on-v6 { any; };" >> /etc/bind/named.conf.options
    echo "        listen-on {" >> /etc/bind/named.conf.options
    echo "        $1;" >> /etc/bind/named.conf.options
    echo "        127.0.0.1" >> /etc/bind/named.conf.options
    echo "        };" >> /etc/bind/named.conf.options
    echo "" >> /etc/bind/named.conf.options
    echo "        allow-query { any; };" >> /etc/bind/named.conf.options
    echo "        forwarders {" >> /etc/bind/named.conf.options
    echo "        8.8.8.8;" >> /etc/bind/named.conf.options
    echo "        8.8.4.4;" >> /etc/bind/named.conf.options
    echo "        };" >> /etc/bind/named.conf.options
    echo "};" >> /etc/bind/named.conf.options

    named-checkconf
    if [ $? -eq 0 ];then
         echo '[*] named.conf.options file configured successfully'
         return 0
    else
        echo '[-] Error: named.conf.options file misconfigurated'
        echo '[*] Restaurating default file'
        mv /etc/bind/named.conf.options.old /etc/bind/named.conf.options
        named-checkconf
        if [ $? -eq 0 ];then
            echo '[*] named.conf.options file restaurated successfully'
            return 0
        else
            echo '[-] Error: Restaured named.conf.options file has errors. Please check it and fix those errors.'
            return 1
        fi
    fi
}

# Updates the system and tries to install bind9
install(){
    echo '[*] Updating your system and installing Bind9'
    sudo apt update && sudo apt install bind9 -y
    if [ $? -eq 0 ]; then
        echo '[*] System updated and bind9 installed successfully'
        return 0
    else
        echo '[-] Error: Could not install bind9 on your system'
        return 1
    fi
}

# Prints the usage
usage(){
    echo 'USAGE: ./dnser.sh <NETWORK_INTERFACE_TO_LET_BIND9_LISTEN>'
    echo ''
    echo 'EXAMPLE: If my network address is 192.168.1.11, I will run: ./dnser.sh 192.168.1.11'
}

# MAIN
checkArguments $@ # $@ is an array with all the arguments passed to the program
if [ $? -ne 0 ]; then
    exit 1
fi
configureAll
