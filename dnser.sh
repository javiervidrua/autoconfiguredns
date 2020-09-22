#! /usr/bin/env bash


# Creates iptables rules to allow bind9 go though
allowBind9iptables(){ # Implement this
    return 1
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
