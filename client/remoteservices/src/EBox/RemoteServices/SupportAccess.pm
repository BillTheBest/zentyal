# Copyright (C) 2009 EBox Technologies S.L.
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
use constant USER_COMMENT => 'user for eBox remote support';


sub setEnabled
{
    my ($self, $enable, $allowFromAnyAddress) = @_;

    my $user = remoteAccessUser();
    my $keysFile = EBox::Config::share() . 
                   'ebox-remoteservices/' .                  
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
__('Cannot ger a the estricted addresses for remote support')
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


sub remoteAccessUserAddress
{
    my $vpnInterface = EBox::Global->modInstance('remoteservices')->ifaceVPN();
    defined $vpnInterface or
        return undef;
    EBox::NetWrappers::iface_exists($vpnInterface) or
          return undef;
    EBox::NetWrappers::iface_is_up($vpnInterface) or
          return undef;
    my $netmaskByAddr = EBox::NetWrappers::iface_addresses_with_netmask($vpnInterface);
    # we assume that is only one address/netmask
    my ($address, $netmask) = each %{ $netmaskByAddr };
    my $network = EBox::NetWrappers::ip_network($address, $netmask);
    $network =~ s/(\.0)+$/.*/;

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
'There exists already a user {u} and it does not seem created by eBox. Until this user is renamed or removed it would be impossible to set up remote support access',
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
    $conf .= q{caption always 'eBox support - %H'};
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
    EBox::Sudo::root("chsh -s /usr/bin/screen $user");

}


sub _setScreenSUID
{
    my ($self, $active) = @_;
    if ($active) {
        EBox::Sudo::root("chmod u+s /usr/bin/screen");
        EBox::Sudo::root("chmod 755 /var/run/screen");
    } else {
        EBox::Sudo::root("chmod u-s /usr/bin/screen");
        EBox::Sudo::root("chmod 775 /var/run/screen");        
    }
}



1;
