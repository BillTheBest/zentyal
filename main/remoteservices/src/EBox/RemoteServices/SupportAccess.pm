# Copyright (C) 2010-2012 eBox Technologies S.L.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package EBox::RemoteServices::SupportAccess;

use strict;
use warnings;

use EBox::Config;
use EBox::Sudo;
use EBox::Exceptions::External;
use EBox::Gettext;
use EBox::Module::Base;
use EBox::NetWrappers;
use File::Slurp;
use EBox::Module::Base;

use constant USER_NAME => 'ebox-remote-support';
use constant USER_COMMENT => 'user for Zentyal remote support';
use constant SCREEN_BIN => '/usr/bin/screen';
use constant SCREEN_RUN_DIR => '/var/run/screen';
use constant STD_SSH_PORT => 22;
use constant LISTEN_ALL => '0.0.0.0';
use constant ROUTEUP_SCRIPT => EBox::Config::scripts('remoteservices') . 'route-up-support-access';

sub setEnabled
{
    my ($self, $enable, $allowFromAnyAddress) = @_;

    my $user = remoteAccessUser();
    my $keysFile = EBox::Config::share() .
                   'zentyal-remoteservices/' .
                       'remote-support.keys';


    # suid neccesary for multiscreen mode
    $self->_setScreenSUID($enable);


    if (not $self->userExists($user)) {
        if (not $enable) {
            return;
        } else {
            my $cmd = "useradd $user --create-home " .
                      q{--comment '} . USER_COMMENT . q{'};
            EBox::Sudo::root($cmd);

        }
    }

    $self->userCheck();

    if ($enable) {
        my $restrictedAddress = undef;
        if (not $allowFromAnyAddress) {
            $restrictedAddress = $self->remoteAccessUserAddress();
            if (not defined $restrictedAddress) {
                throw EBox::Exceptions::External(
__('Cannot get the restricted addresses for remote support. '
   . 'Check VPN logs for details')
                                                );
            }
        }

        $self->_createSshFiles($user, $keysFile, $restrictedAddress);
        $self->_writeScreenConf($user);
    } else {
        my $rmCmd = "deluser --remove-home --quiet $user";
        EBox::Sudo::root("$rmCmd");
    }

}

sub remoteAccessUser
{
    return USER_NAME;
}

# Returns the restricted network to access from
sub remoteAccessUserAddress
{
    my $rs = EBox::Global->modInstance('remoteservices');

    my $network;

    # we assume that is only one address/netmask
    my $vpnSI = $rs->confKey('vpnSIAddress');
    if ( defined($vpnSI) ) {
        ($network) = split(/\//, $vpnSI);
        $network =~ s/(\.0)+$/.*/;
    } else {
        # Backwards compatible. Get the data from dnsServer key
        my $dnsServer = $rs->confKey('dnsServer');
        defined($dnsServer) or return undef;

        $network = $dnsServer;
        $network =~ s:\.([0-9])+?$:.*:;
    }

    return $network;
}



sub userExists
{
    my ($class, $user) = @_;
    my $exists = getpwnam($user);
    return $exists;
}

sub userCheck
{
    my ($self) = @_;
    my $user = $self->remoteAccessUser();
    if (not $self->userExists($user)) {
        # nothing to check...
        return;
    }

    my ($name,$passwd,$uid,$gid,  $quota,$comment,$gcos,) = getpwnam($user);

    if ($gcos ne USER_COMMENT) {
        throw EBox::Exceptions::External(__x(
'There exists already a user {u} and it does not seem created by Zentyal. Until this user is renamed or removed it would be impossible to set up remote support access',
                                    u => $user ));
    }
}

sub _createSshFiles
{
    my ($self, $user, $keyFile, $restrictedAddress) = @_;
    my $sshDir = $self->_sshDir($user);
    my $authKeysFile = "$sshDir/authorized_keys";

    EBox::Sudo::root("mkdir -p --mode=0700 $sshDir");
    if (not $restrictedAddress) {
        EBox::Sudo::root("cp $keyFile $authKeysFile");
    } else {
        my $contents = File::Slurp::read_file($keyFile);
        $contents =~ s/^ssh-/from="$restrictedAddress" ssh-/;
        EBox::Module::Base::writeFile($authKeysFile, $contents);
    }

    EBox::Sudo::root("chmod 0600 $authKeysFile");
    EBox::Sudo::root("chown -R $user.$user $sshDir");
}


sub _sshDir
{
    my ($self, $user) = @_;
    my $homedir = $self->_homedir($user);
    my $path = $homedir . '/.ssh';
    return $path;
}


sub _screenRc
{
    my ($self, $user) = @_;
    my $homedir = $self->_homedir($user);
    return "$homedir/.screenrc";

}

sub _homedir
{
    my ($self, $user) = @_;
    my ($name,$passwd,$uid,$gid,
        $quota,$comment,$gcos,$homedir,$shell,$expire) = getpwnam($user);
    return $homedir;
}


sub _writeScreenConf
{
    my ($self, $user) = @_;

    my $conf = 'multiuser on';


    my $eboxUser = EBox::Config::user();
    my @parts = getgrnam('adm');
    my $memberStr = $parts[3];

    my @users = grep {
        $_ ne $eboxUser
    } split '\s', $memberStr;

    if (not @users) {
        EBox::error("No users for the adm group!, Cannot create screen then");
        return;
    }


    my $logFile = $self->_homedir($user) . "/support.log";

    my $userStr = join ',', @users;
    $conf .= "\n";
    $conf .= qq{aclchg $userStr -w "#"\n};
    $conf .= "defwritelock on\n";
    $conf .= q{caption always 'Zentyal support - %H'};
    $conf .= "\n";
    $conf .= "screen\n";
    $conf .= "logfile $logFile\n";
    $conf .= "log on\n";



    my $screenRc = $self->_screenRc($user);
    EBox::Module::Base::writeFile(
                                  $screenRc,
                                  $conf,
                                 );
    EBox::Sudo::root("chown $user.$user $screenRc");
    EBox::Sudo::root('chsh -s ' . SCREEN_BIN . " $user");

}


sub _setScreenSUID
{
    my ($self, $active) = @_;
    if ($active) {
        EBox::Sudo::root('chmod u+s ' . SCREEN_BIN);
        if ( EBox::Sudo::fileTest('-e', SCREEN_RUN_DIR) ) {
            EBox::Sudo::root('chmod 755 ' . SCREEN_RUN_DIR);
        }
    } else {
        EBox::Sudo::root('chmod u-s ' . SCREEN_BIN);
        if ( EBox::Sudo::fileTest('-e', SCREEN_RUN_DIR) ) {
            EBox::Sudo::root('chmod 775 ' . SCREEN_RUN_DIR);
        }
    }
}

sub sshListening
{
    my ($self) = @_;

    my @sshd;
    # TODO: Can't we use a faster way?
    my $netstatLines = EBox::Sudo::root('netstat -tlnp');
    foreach my $line (@{ $netstatLines }) {
        if ($line =~ m{\/sshd\s*$}) {
            my @parts = split '\s+', $line;
            if ($parts[0] eq 'tcp6') {
                # no tcp6 support
                next;
            }

            my $local = $parts[3];
            my ($addr, $port) = split ':', $local;
            push (@sshd, { address => $addr, port => $port });
        }
    }

    return \@sshd;
}

sub sshRedirect
{
    my ($self) = @_;
    my ($sshAddr, $sshPort);
    my @sshListening = @{ $self->sshListening };
    foreach my $ssh (@sshListening) {
        my $addr = $ssh->{address};
        my $port = $ssh->{port};
        if (($addr eq LISTEN_ALL) and ($port == STD_SSH_PORT)) {
            # standard port and address, no redirection needed
            return undef;
        }
        if (not $sshAddr or ($sshAddr ne LISTEN_ALL)) {
            $sshAddr = $addr;
            $sshPort = $port;
        }
    }

    if (not $sshAddr) {
        # no ssh servers
        return undef;
    }

    return {address => $sshAddr, port => $sshPort  };
}

# Method: setClientRouteUp
#
#      Set the route-up script for the VPN client
#
# Parameters:
#
#      supportAccess - Boolean indicating if the support access is
#                      enabled or not to set default route-up script
#                      or disable it
#
#      vpnClient - <EBox::OpenVPN::Client> the VPN client to configure
#                  the route-up script
#
sub setClientRouteUp
{
    my ($self, $supportAccess, $vpnClient)  = @_;
    my $routeUpCmd = '';
    if ($supportAccess) {
        $routeUpCmd = ROUTEUP_SCRIPT;
    }

    if ($vpnClient->routeUpCmd() eq $routeUpCmd) {
        return;
    }

    $vpnClient->setRouteUpCmd($routeUpCmd);
    my $openvpnMod = EBox::Global->modInstance('openvpn');
    $openvpnMod->save();
}

1;
