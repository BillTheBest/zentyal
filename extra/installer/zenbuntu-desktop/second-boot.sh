#!/bin/sh

# If Zentyal is already installed...
if ! [ -f '/var/lib/zentyal/.first' ]
then
    # Disable auto login once installation is done
    sed -i "s/.*autologin=.*/# autologin=nobody/" /etc/lxdm/default.conf

    # Remove temporal local repository
    sed -i "/deb file.*zentyal-packages/d" /etc/apt/sources.list

    # Restore default rc.local
    cp /usr/share/zenbuntu-desktop/rc.local /etc/rc.local
fi

initctl emit zentyal-lxdm

exit 0
