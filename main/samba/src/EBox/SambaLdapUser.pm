# Copyright (C) 2008-2012 eBox Technologies S.L.
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

package EBox::SambaLdapUser;

use strict;
use warnings;

use EBox::Sudo;
use EBox::Global;
use EBox::Model::ModelManager;
use EBox::Network;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::Internal;
use EBox::Exceptions::DataExists;
use EBox::Exceptions::DataMissing;

use EBox::Gettext;

use Perl6::Junction qw(any all);
use Error qw(:try);

use Crypt::SmbHash qw(nthash ntlmgen);

# Default values for samba user
use constant SMBLOGONTIME       => '0';
use constant SMBLOGOFFTIME      => '2147483647';
use constant SMBKICKOFFTIME     => '2147483647';
use constant SMBPWDCANCHANGE    => '0';
use constant SMBPWDMUSTCHANGE   => '2147483647';
use constant SMBGROUP           => '513';
use constant SMBACCTFLAGS       => '[U]';
use constant SMBACCTFLAGSDISABLED       => '[UD]';
use constant USERGROUP          => 513;
# Home path for users and groups
use constant BASEPATH           => '/home/samba';
use constant USERSPATH          => '/home';
use constant GROUPSPATH         => BASEPATH . '/groups';
use constant PROFILESPATH       => BASEPATH . '/profiles';

BEGIN
{
    use Exporter ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    @ISA = qw(Exporter);
    @EXPORT = qw{ USERSPATH GROUPSPATH PROFILESPATH };
    %EXPORT_TAGS = ( DEFAULT => \@EXPORT );
    @EXPORT_OK = qw();
    $VERSION = EBox::Config::version;
}

use base qw(EBox::LdapUserBase);

sub new
{
    my $class = shift;
    my $self  = {};
    $self->{ldap} = EBox::Global->modInstance('users')->ldap();
    $self->{samba} = EBox::Global->modInstance('samba');
    bless($self, $class);
    return $self;
}

sub _smbHomes
{
    my $samba = EBox::Global->modInstance('samba');
    return "\\\\" . $samba->netbios() . "\\homes\\";
}

sub _smbProfiles
{
    my $samba = EBox::Global->modInstance('samba');
    return "\\\\" . $samba->netbios() . "\\profiles\\";
}

# FIXME Implement userInGroup function in UsersAndGroups
sub _domainUser
{
    my ($self, $user) = @_;

    ($user) or return;
    my $usermod = EBox::Global->modInstance('users');

    my @domainUsers;

    @domainUsers = @{$usermod->usersInGroup('Domain Users')};
    foreach my $u (@domainUsers) {
        return 1 if ($u eq $user);
    }
    return undef;
}

sub _userCommonLdapAttrs
{
    my ($self) = @_;

    my $defaultFlags;
    my $model =
        EBox::Model::ModelManager::instance()->model('samba/SambaUser');
    if ($model->enabledValue()) {
        $defaultFlags = SMBACCTFLAGS;
    } else {
        $defaultFlags = SMBACCTFLAGSDISABLED;
    }

    my $attrs = {
        sambaLogonTime       => SMBLOGONTIME,
        sambaLogoffTime      => SMBLOGOFFTIME,
        sambaKickoffTime     => SMBKICKOFFTIME,
        sambaPwdCanChange    => SMBPWDCANCHANGE,
        sambaPwdMustChange   => SMBPWDMUSTCHANGE,

        sambaPasswordHistory => '0' x56,
        sambaPwdLastSet      => time(),

        sambaAcctFlags       => $defaultFlags,
    };

    return $attrs;
}

sub _addUserLdapAttrs
{
    my ($self, $user, $unixuid, $password) = @_;

    my $ldap = $self->{ldap};
    my $users = EBox::Global->modInstance('users');

    my $dn = "uid=$user," .  $users->usersDn;
    my $rid = 2 * $unixuid + 1000;

    my $sid      = alwaysGetSID();
    my $sambaSID = $sid . '-' .  $rid;
    my $userinfo = $users->userInfo($user);

    my ($lm ,$nt);
    if (not defined($password) or EBox::UsersAndGroups::isHashed($password)) {
        $lm = $userinfo->{extra_passwords}->{'lm'};
        $nt = $userinfo->{extra_passwords}->{'nt'};
    } else {
        ($lm, $nt) = ntlmgen($password);
    }
    my %userCommonAttrs =   %{ $self->_userCommonLdapAttrs() };

    unless ($self->_isSambaObject('sambaSamAccount', $dn)) {
        my %attrs = (
            changes => [
                    add => [
                        objectClass         => 'sambaSamAccount',
                        %userCommonAttrs,

                        sambaHomePath        => _smbHomes() . $user,

                        sambaPrimaryGroupSID => $sid . '-' . SMBGROUP,
                        sambaLMPassword      => $lm,
                        sambaNTPassword      => $nt,

                        sambaSID             => $sambaSID,
                    ],
            ]
        );

        my $add = $ldap->modify($dn, \%attrs );
    }
    else {
        # upgrade from previous versions
        # XXX currently only the user common attributes are upgraded
        my %searchParams = (base => $dn,
                            attrs => [keys %userCommonAttrs],
                            filter => "(objectclass=*)",
                            scope =>'base');
        my $result = $ldap->search(\%searchParams);

        my $entry = $result->pop_entry();
        defined $entry or
            throw EBox::Exceptions::Internal("Cannot retrieve user with DN= $dn");

        my $changed = 0;
        while (my ($attr, $defaultValue) = each %userCommonAttrs) {
            my $value = $entry->get_value($attr);
            if (not defined $value) {
                $entry->add($attr, $defaultValue);
                $changed = 1;
            }
        }

        if ($changed) {
            $entry->update($ldap->ldapCon);
        }
    }
}

# Implements LdapUserBase interface
sub _addUser
{
    my ($self, $userName, $password) = @_;

    return unless ($self->{samba}->configured());

    my $users = EBox::Global->modInstance('users');
    my $userInfo = $users->userInfo($userName);
    my $unixuid = $userInfo->{uid};

    $self->_addUserLdapAttrs($userName, $unixuid, $password);

    # Add user to Domain Users group
    unless ($self->_domainUser($userName)) {
        $users->addUserToGroup($userName, 'Domain Users');
    }

    $self->_createDir(PROFILESPATH . "/$userName",
        $unixuid, USERGROUP, '0700');
    $self->_createDir(PROFILESPATH . "/$userName.V2",
        $unixuid, USERGROUP, '0700');
}

sub _modifyUser
{
    my ($self, $user, $password) = @_;

    return unless ($self->{samba}->configured());

    my $users = EBox::Global->modInstance('users');
    my $userInfo = $users->userInfo($user);
    my $dn = "uid=$user," .  $users->usersDn;
    my $ldap = $self->{ldap};

    my $curNT =  $userInfo->{extra_passwords}->{nt};
    my $curLM =  $userInfo->{extra_passwords}->{lm};

    my %attrs = (
            base   => $dn,
            filter => "(objectclass=*)",
            attrs  => [ 'sambaNTPassword', 'sambaLMPassword'],
            scope  => 'base'
            );

    my $result = $ldap->search(\%attrs);

    my $entry = $result->pop_entry();
    $entry->replace( sambaNTPassword => $curNT, sambaLMPassword => $curLM );
    $entry->update($ldap->ldapCon);
}

sub _delUser
{
    my ($self, $user) = @_;

    return unless ($self->{samba}->configured());

    my @cmds;
    if (-d BASEPATH . "/profiles/$user") {
        push (@cmds, "rm -rf \'" .  BASEPATH . "/profiles/$user\'");
    }
    if (-d BASEPATH . "/profiles/$user.V2") {
        push (@cmds, "rm -rf \'" .  BASEPATH . "/profiles/$user.V2\'");
    }
    EBox::Sudo::root(@cmds) if (@cmds);

    # Remove user from printers
    my $samba = EBox::Global->modInstance('samba');
    $samba->setPrintersForUser($user, []);
}

sub _delUserWarning
{
    my ($self, $user) = @_;

    return unless ($self->{samba}->configured());

    my $path = BASEPATH . "/users/$user";

    my $txt = __('This user has a sharing directory associated ' .
                 'which contains data.');
    unless ($self->_directoryEmpty($path)) {
        return ($txt);
    }

    return undef;
}

sub _addGroup
{
    my ($self, $group) = @_;
    return unless ($self->{samba}->configured());

    $self->addGroupLdapAttrs($group);
}

sub addGroupLdapAttrs
{
    my ($self, $group, %params) = @_;

    my $sambaSID = delete $params{SID};

    my $ldap  = $self->{ldap};
    my $users = EBox::Global->modInstance('users');
    my $groupInfo = $users->groupInfo($group);
    my $unixgid = $groupInfo->{gid};

    my $rid = 2 * $unixgid + 1001;

    if (not defined $sambaSID) {
        my $baseSid = alwaysGetSID();
        $sambaSID = $baseSid . '-' .  $rid;
    }

    my $dn = "cn=$group," .  $users->groupsDn;

    unless ($self->_isSambaObject('sambaGroupMapping', $dn)) {
        my %attrs = (
             changes => [
                         add => [
                                 objectClass    => 'sambaGroupMapping',
                                 objectClass    => 'eboxGroup',
                                 sambaSID       => $sambaSID,
                                 sambaGroupType => '2',
                                 displayName    => $group,
                                ]
                        ]
                    );
        $ldap->modify($dn, \%attrs);
    }
}

sub setUserSID
{
    my ($self, $user, $sid) = @_;

    checkSID($sid) or
    throw EBox::Exceptions::External(__('Incorrect SID: {s}', 's' => $sid));

    my $users = EBox::Global->modInstance('users');
    $users->userExists($user)  or
    throw EBox::Exceptions::External(__x('User {u} does not exists', 'u' => $user));

    my $dn =  $users->userDn($user);
    $self->_isSambaObject('sambaSamAccount', $dn) or
    throw EBox::Exceptions::External(__x('User {u} is not a samba user', 'u' => $user));

    $self->_setSID($dn, $sid);
}

sub setGroupSID
{
    my ($self, $group, $sid) = @_;

    checkSID($sid) or
    throw EBox::Exceptions::External(__('Incorrect SID: {s}', 's' => $sid));

    my $users = EBox::Global->modInstance('users');
    $users->groupExists($group)  or
    throw EBox::Exceptions::External(__x('Group {g} does not exists', 'g' => $group));

    my $dn = $users->groupDn($group);
    $self->_isSambaObject('sambaGroupMapping', $dn) or
    throw EBox::Exceptions::External(__x('Group {g} is not a samba group', 'g' => $group));

    $self->_setSID($dn, $sid);
}

sub _setSID
{
    my ($self, $dn, $sambaSID) = @_;

    my %attrs = (
             changes => [
                 replace => [
                             sambaSID       => $sambaSID,
                            ]
                        ]
                );
    $self->{ldap}->modify($dn, \%attrs);
}

sub _delGroup
{
    my ($self, $group) = @_;

    return unless ($self->{samba}->configured());

    if (-d BASEPATH . "/groups/$group") {
        EBox::Sudo::root("rm -rf \'" .  BASEPATH . "/groups/$group\'");
    }

    # Remove group from printers
    my $samba = EBox::Global->modInstance('samba');
    $samba->setPrintersForGroup($group, []);
}

sub _delGroupWarning
{
    my ($self, $group) = @_;

    return unless ($self->{samba}->configured());

    my $path = BASEPATH . "/groups/$group";
    my $txt = __('This group has a sharing directory associated ' .
                 'that contains data.');

    unless ($self->_directoryEmpty($path)) {
        return ($txt);
    }

    return undef;
}

sub _userAddOns
{
    my ($self, $username) = @_;

    return unless ($self->{samba}->configured());

    my $users = EBox::Global->modInstance('users');
    my $samba = EBox::Global->modInstance('samba');

    my @args;
    my $share = $self->_userSharing($username) ? "yes" : "no";
    my $printers = $samba->_printersForUser($username);
    my $args =  {
        'username' => $username,
        'share'    => $share,
        'is_admin' => $samba->adminUser($username),
        'service'  => $samba->isEnabled,

        'printers' => $printers,
        'printerService' => $samba->printerService,
    };

    return { path => '/samba/samba.mas', params => $args };
}

sub _groupAddOns
{
    my ($self, $groupname) = @_;

    return unless ($self->{samba}->configured());

    my $samba = EBox::Global->modInstance('samba');

    my @args;
    my $share = $self->_groupSharing($groupname) ? "yes" : "no";
    my $printers = $samba->_printersForGroup($groupname);
    my $args =  {
        'groupname' => $groupname,
        'share'     => $share,
        'sharename' => $self->sharingName($groupname),
        'service'   => $samba->isEnabled,

        'printers' => $printers,
        'printerService' => $samba->printerService,
    };

    return { path => '/samba/samba.mas', params => $args };
}

sub _createDir
{
    my ($self, $path, $uid, $gid, $chmod) = @_;

    if (EBox::Sudo::fileTest('-d', $path)) {
        return;
    }

    my @cmds;

    push (@cmds, "/bin/mkdir \'$path\'");
    push (@cmds, "/bin/chown $uid:$gid \'$path\'");

    if ($chmod) {
        push (@cmds, "/bin/chmod $chmod \'$path\'");
    }

    EBox::Sudo::root(@cmds);
}

sub _directoryEmpty
{
    my ($self, $path) = @_;

    opendir(DIR, $path) or return 1;
    my @ent = readdir(DIR);

    return ($#ent == 1);
}

sub migrateUsers
{
    my ($self) = @_;

    my $users  = EBox::Global->modInstance('users');
    my $samba  = EBox::Global->modInstance('samba');

    # update users
    foreach my $user ($users->users) {
        my $username = $user->{'username'};
        $self->_addUser($username);

        # check if we have old administrator rights
        try {
            $samba->adminUser($username);
        }
        catch EBox::Exceptions::Internal with {
            my $ex = shift @_;
            if (  $user ne all @{$users->usersInGroup('Administrators')} ) {
                $users->addUserToGroup($username, 'Administrators');
                # to be sure that isn't another error...
                $samba->adminUser($username);
            }
            else {
                $ex->throw();
            }
        };
    }

    # update groups
    foreach my $group ($users->groups) {
        my $groupname = $group->{'account'};
        $self->_addGroup($groupname);
    }
}

sub checkDomainSID
{
    my ($sid) = @_;

    defined $sid or return 0;

    my @parts = split '-', $sid;
    if (@parts < 7) {
        return 0;
    }

    return 1;
}

sub checkSID
{
    # we do not discrimintae now etween domainSID and a element SID
    return checkDomainSID(@_);
}

sub getSID
{
    my $samba  = EBox::Global->modInstance('samba');
    if (not defined $samba) {  # this method can't be called in package
                               # postinstallation when samba module is not fully installed

        die 'cannot get samba module';
        # return undef;
        return generateSID();
    }

    my $domain = $samba->workgroup();

    # FIXME wtf
    my $res = `sudo net getlocalsid $domain 2>&1 `;
    if ($? != 0) {
        # return undef;
        return generateSID();
    }

    chomp $res;
    my @parts = split '\s', $res;

    my $sid = pop @parts;

    if (not checkDomainSID($sid)) {
        # return undef;
        # return generateSID();
        throw EBox::Exceptions::Internal("Bad net getlocalsid output: @parts");
    }

    return $sid;
}

sub alwaysGetSID
{
    my $sid;
    $sid = getSID();
    defined $sid or $sid = generateSID();
    return $sid;
}

sub generateSID
{
    # FIXME: Hardcore SID for testing purposes
    return 'S-1-5-21-3818554400-921237426-3143208535';
}

sub getGroupSID
{
    my ($self, $group) = @_;

    my $usersAndGroups = EBox::Global->modInstance('users');
    $usersAndGroups->groupExists($group) or
        throw EBox::Exceptions::External(__x('{g} group does not exist',
            'g' => $group));
    my $sidAttr = 'sambaSID';

    my $ldap    = $self->{ldap};

    my %searchArgs = (
            base => $usersAndGroups->groupsDn,
            filter => "&(objectclass=eboxGroup)(cn=$group)",
            scope => 'sub',
            attrs => [$sidAttr],
            );

    my $result = $ldap->search(\%searchArgs);
    my $groupEntry = $result->entry(0);

    return $groupEntry->get_value($sidAttr);
}

sub _groupSharing
{
    my ($self, $group) = @_;

    return $self->sharingName($group) ? 1 : undef;
}

# Checks if a resource name exists
sub _sharingResourceExists
{
    my ($self, $name)  = @_;

    my $ldap  = $self->{ldap};
    my $users = EBox::Global->modInstance('users');

    my $dn =  $users->groupsDn;
    my %attrs = (
        base   => $dn,
        filter => "(&(objectclass=eboxGroup) " .
                  "(displayResource=$name))",
        scope  => 'one'
            );
    my $result = $ldap->search(\%attrs);

    return ($result->count == 1)
}


# TODO Find another name more self-explanatory, this one is crap
sub userShareDirectories
{
    my ($self) = @_;

    my $ldap  = $self->{ldap};
    my $users = EBox::Global->modInstance('users');

    my $dn =  $users->usersDn;
    my %attrs = (
        base   => $dn,
        filter => '(&(objectclass=posixAccount) (objectclass=sambaSamAccount))',
        attrs  => [ 'uid', 'homedirectory'],
        scope  => 'one'
            );
    my $result = $ldap->search(\%attrs);

    my @share;
    foreach my $entry ($result->entries) {
        my $user = $entry->get_value('uid');
        my $home = $entry->get_value('homeDirectory');
        push (@share, { path      => $home,
                        username => $user,
                        sharename => $user
                  });
    }
    return \@share;
}

# TODO Find another name more self-explanatory, this one is  crap
sub groupShareDirectories
{
    my ($self) = @_;

    my $ldap  = $self->{ldap};
    my $users = EBox::Global->modInstance('users');

    my $dn =  $users->groupsDn;
    my %attrs = (
        base   => $dn,
        filter => '(&(objectclass=posixGroup) (objectclass=eboxGroup))',
        attrs  => [ 'cn', 'displayResource', 'description' ],
        scope  => 'one'
            );
    my $result = $ldap->search(\%attrs);

    my @share;
    foreach my $entry ($result->entries) {
        my $group = $entry->get_value('cn');
        my $name  = $entry->get_value('displayResource');
        my $comment = $entry->get_value('description');
        ($name) or next;
        push (@share, { path      => BASEPATH . "/groups/$group",
                        groupname => $group,
                        sharename => $name,
                        groupcomment => $comment,
                  });
    }
    return \@share;
}

sub sharingName
{
    my ($self, $group) = @_;

    my $ldap  = $self->{ldap};
    my $users = EBox::Global->modInstance('users');

    unless ($users->groupExists($group)) {
        throw EBox::Exceptions::DataNotFound('data' => __('group name'),
                'value' => $group);
    }

    my $dn =  "cn=$group," . $users->groupsDn;
    my %attrs = (
            base   => $dn,
            filter => "(objectclass=eboxGroup)",
            attrs  => ['displayResource'],
            scope  => 'base'
            );

    my $result = $ldap->search(\%attrs);

    my $entry = $result->entry(0);
    my $value = $entry->get_value('displayResource');

    return $value ? $value : "";
}

# Sets the name for a sharing resource in a group
sub setSharingName
{
    my ($self, $group, $name)  = @_;

    my $users = EBox::Global->modInstance('users');

    unless ($users->groupExists($group)) {
        throw EBox::Exceptions::DataNotFound('data' => __('group name'),
                'value' => $group);
    }

    if ((not defined $name) or ( $name =~ /^\s*$/)) {
        throw EBox::Exceptions::External(__("A name should be provided for the share."));
    }

    my $oldname = $self->sharingName($group);
    return if ($oldname and $oldname eq $name);

    if ($self->_sharingResourceExists($name)) {
        throw EBox::Exceptions::DataExists(
                'data'  => __('sharing resource'),
                'value' => $name);
    }

    my $dn = "cn=$group," .  $users->groupsDn;
    my %attrs;
    if ($self->_groupSharing($group)) {
        %attrs = ( changes =>
                    [ replace => [ displayResource => $name ]]);
    } else {
        %attrs = ( changes =>
                    [ add => [ displayResource => $name ]]);
    }
    my $add = $self->{ldap}->modify($dn, \%attrs);

    # we need to set the module as changed to regenConfig when saving
    # Above stuff is stored in ldap so global has no idea its conf
    # has changed.
    my $global = EBox::Global->modInstance('global');
    $global->modChange('samba');

    unless ( -d BASEPATH . "/groups/$group"){
        my $uid = getpwnam(EBox::Config::user);
        my $gid = $users->groupGid($group);
        $self->_createDir(BASEPATH . "/groups/$group",
                          $uid, $gid, "g+w");
    }
}

sub removeSharingName
{
    my ($self, $group) = @_;

    my $users = EBox::Global->modInstance('users');

    unless ($users->groupExists($group)) {
        throw EBox::Exceptions::DataNotFound('data' => __('group name'),
                'value' => $group);
    }

    my $dn = "cn=$group," .  $users->groupsDn;
    my %attrs = ( changes => [ delete => [ displayResource => [] ]]);
    $self->{ldap}->modify($dn, \%attrs);

    # we need to set the module as changed to regenConfig when saving
    # Above stuff is stored in ldap so global has no idea its conf
    # has changed.
    my $global = EBox::Global->modInstance('global');
    $global->modChange('samba');
}

sub _pwdChanged
{
    my ($self, $entry, $newPassword) = @_;

    my $ntpwd = $entry->get_value('sambaNTPassword');

    return ($ntpwd ne nthash($newPassword));
}

sub _getAccountFlags
{
    my ($self, $username) = @_;

    my $ldap  = $self->{ldap};
    my $users = EBox::Global->modInstance('users');

    my $dn = "uid=$username," .  $users->usersDn;

    my %attrs = (
            base   => $dn,
                        filter => "(objectclass=*)",
                        attrs  => [ 'sambaAcctFlags'],
                        scope  => 'base'
            );

    my $result = $ldap->search(\%attrs);

    my $entry = $result->entry(0);
    return  $entry->get_value('sambaAcctFlags');
}

sub _userSharing
{
    my ($self, $username) = @_;

    my $flags = $self->_getAccountFlags($username);
    return (not ($flags =~ /D/));
}

sub setUserSharing
{
    my ($self, $username, $share) = @_;

    my $ldap  = $self->{ldap};
    my $users = EBox::Global->modInstance('users');

    unless ($users->userExists($username)){
        throw EBox::Exceptions::DataNotFound(
                'data'  => __('group'),
                'value' => $username);
    }
    my $dn = "uid=$username," .  $users->usersDn;

    my $flags;
    if ($share eq 'yes') {
        return  if $self->_userSharing($username);
        $flags = $self->_getAccountFlags($username);
        $flags =~ s/D//g;
    } else {
        return  unless $self->_userSharing($username);
        $flags = $self->_getAccountFlags($username);
        $flags =~ s/U/UD/g;
    }

    my %attrs = ( replace => { 'sambaAcctFlags' => $flags });
    $ldap->modify($dn, \%attrs );
}

# Method: sambaDomainName
#
#   Fetch the samba domain name
#
# Returns:
#
#   string - samba domain name
#
sub sambaDomainName
{
	my ($self) = @_;
	my $ldap = $self->{ldap};
	my %attrs = (
			base => $ldap->dn(),
			filter => "(objectclass=sambaDomain)",
			scope => "sub"
	);
    my $entry = $ldap->search(\%attrs)->pop_entry();

    if ($entry) {
        return $entry->get_value('sambaDomainName');
    } else {
        return undef;
    }
}

# Method: setSambaDomainName
#
#   Set the samba domain name. The entry is created if it does not
#   exits
#
# Parameters:
#
#   name - string containing the domain name
#
# Throws:
#
#   InvalidData - wrong domain name
sub setSambaDomainName
{
    my ($self, $domain) = @_;

    my $ldap = $self->{ldap};
    my $sid  = getSID();

    my %domainAttrs = %{$self->_fetchDomainAttrs($domain)};
    $self->deleteSambaDomainNameAttrs();
    $self->deleteSambaDomains();

    my $users = EBox::Global->modInstance('users');
    my %attrs = (
        attr => [
            'sambaDomainName'   => $domain,
            'sambaSID'      => $sid,
            'uidNumber'     => $users->lastUid,
            'gidNumber'     => $users->lastGid,
            'objectClass'       => ['sambaDomain',
                            'sambaUnixidPool'],
            %domainAttrs
            ]
        );

    my $dn = "sambaDomainName=$domain," . $ldap->dn();
    $ldap->add($dn, \%attrs);
}

sub _fetchDomainAttrs
{
    my ($self, $domain) = @_;

    my $ldap = $self->{ldap};

    my @attrs = qw/sambaPwdHistoryLength sambaMaxPwdAge
                  sambaMinPwdLength sambaLockoutThreshold/;
    my $result = $ldap->search(
            {
            base => $ldap->dn(),
            filter => "sambaDomainName=$domain",
            scope => 'sub',
            attrs => [@attrs],
            }
            );

    my $entry = $result->pop_entry();
    return {} unless defined($entry);
    my %attributes;
    for my $attr (@attrs) {
       my $value = $entry->get_value($attr);
       if (defined($value)) {
               $attributes{$attr} = $value;
       }
    }
    return \%attributes;
}

sub deleteSambaDomainNameAttrs
{
    my ($self) = @_;

    my $ldap = $self->{ldap};

    my $attr = 'sambaDomainName';

    my $result = $ldap->search(
            {
            base => $ldap->dn(),
            filter => "$attr=*",
            scope => 'sub',
            attrs => [$attr],
            }
            );

    foreach my $entry ($result->entries()) {
        my @values = $entry->get_value($attr);
        @values or
            next;

        $entry->delete( $attr => \@values );
        $entry->update($ldap->ldapCon);
    }

#   my $ldap = $self->{ldap};
#   my %searchParams = (
#				base => $ldap->dn(),
#				filter => "(sambaDomainName=*)",
#				attrs => ['sambaDomainName'],
#				scope => "sub"
#		    );

#   foreach my $entry ($ldap->search(\%searchParams)->entries()) {
#     my $dn = 'sambaDomainName=' .
#       $entry->get_value('sambaDomainName') . ',' . $ldap->dn();
#     $ldap->delete($dn);
#   }
}

sub deleteSambaDomains
{
    my ($self) = @_;

    my $ldap = $self->{ldap};
    my %searchParams = (
            base => $ldap->dn(),
            filter => "objectClass=sambaDomain",
            scope => "sub"
            );

    foreach my $entry ($ldap->search(\%searchParams)->entries()) {
        $entry->delete;
        $entry->update($ldap->ldapCon);
    }
}

# Method: setSambaDomain
#
#   Set the samba domain name. The entry is created if it does not
#   exits
#
# Parameters:
#
#   name - string containing the domain name
#
# Throws:
#
#   InvalidData - wrong domain name
# sub setSambaDomains
# {
#   my ($self) = @_;
#   my $users = EBox::Global->modInstance('users');
#   my $lastUid = $users->lastUid;
#   my $lastGid = $users->lastGid;
#   my $modifyParams = {
#               replace => {
#                   uidNumber => $lastUid,
#                   gidNumber => $lastGid,
#                      },
#              };
#   my $ldap = $self->{ldap};
#   my %attrs = (
#               base => $ldap->dn,
#               filter => "objectClass=sambaDomain",
#               scope => "sub"
#           );
#   my @sambaDomains = $ldap->search(\%attrs)->entries();
#   if (not @sambaDomains) {
#     return 0;
#   }
#   foreach my $entry (@sambaDomains) {
#     my $dn = $entry->dn;
#     if (not $ldap->isObjectClass($dn, 'sambaUnixIdPool')) {
#       $ldap->modify($dn,
#             { add => {
#                   objectClass => 'sambaUnixIdPool',
#                   uidNumber => $lastUid,
#                   gidNumber => $lastGid,
#                  }
#             }
#            );
#     }
#     else {
#       $ldap->modify($dn, $modifyParams);
#     }
#   }
#   return 1;
# }

# Method: updateNetbiosName
#
#   Update in LDAP all those attributes which contain the netbios name
#
# Parameters:
#
#   netbios - string containing the new netbios name
#
# Throws:
#
#   InvalidData - wrong domain name
sub updateNetbiosName
{
    my ($self, $netbios) = @_;

    my $users = EBox::Global->modInstance('users');
    my $ldap = $self->{'ldap'};

    my %attrs = (
        base   => $users->usersDn(),
        filter => "(objectclass=sambaSamAccount)",
        attrs => ['uid'],
        scope  => 'sub'
    );

    for my $entry ($ldap->search(\%attrs)->entries()) {
        my $dn = $entry->dn();
        my $username = $entry->get_value('uid');

        $ldap->modifyAttribute($dn, 'sambaHomePath',
                "\\\\$netbios\\homes\\$username");
        # XXX Check if we have to add or not, instead of
        # add + [ delete ]
        $ldap->modifyAttribute($dn, 'sambaProfilePath',
                "\\\\$netbios\\profiles\\$username");
        unless ($self->{samba}->roamingProfiles()) {
            my %attrs = ( changes => [ delete =>
                    [ sambaProfilePath => [] ]]);
            $ldap->modify($dn, \%attrs);
        }
    }
}

# Method: updateSIDEntries
#
#       Check and correct if there's any user or group with a wrong SID. Note
#       that depending on when the user/group is created the SID might change.
#       This method should be run in regenConfig
#
sub updateSIDEntries
{
    my ($self) = @_;

    my $users = EBox::Global->modInstance('users');
    my $ldap = $self->{'ldap'};
    my $userDN = $users->usersDn();
    my $sid = uc(getSID());
    $sid = uc($sid);

    my %attrs = (
            base   => $userDN,
            filter => "(&(objectclass=sambaSamAccount)(!(sambaSID=$sid*)))",
            attrs  => ['sambaSID', 'sambaPrimaryGroupSID', 'dn'],
            scope  => 'sub'
            );

    my $result = $ldap->search(\%attrs);

    for my $entry ($result->entries()) {
        my $oldSID = $entry->get_value('sambaSID');
        my $oldGroupSID = $entry->get_value('sambaPrimaryGroupSID');
        my ($lastNumbers) = $oldSID =~ /.*-(\d+)$/;
        my $newSID = "$sid-$lastNumbers";
        my ($lastNumbersGroup) = $oldGroupSID =~ /.*-(\d+)$/;
        my $newGroupSID = "$sid-$lastNumbersGroup";
        $ldap->modifyAttribute($entry->dn(), 'sambaSID', $newSID);
        $ldap->modifyAttribute($entry->dn(),
                'sambaPrimaryGroupSID',
                $newGroupSID);
    }

    my $groupDN = $users->groupsDn();
    %attrs = (
            base   => $groupDN,
            filter => "(&(objectclass=sambaGroupMapping)(!(sambaSID=$sid*)))",
            attrs  => ['sambaSID', 'cn'],
            scope  => 'sub'
            );

    $result = $ldap->search(\%attrs);
    my %groupsToSkip = ('Administrators' => 1,
                        'Account Operators' => 1,
                        'Print Operators' => 1,
                        'Backup Operators' => 1,
                        'Replicators' => 1);

    for my $entry ($result->entries()) {
        next if $groupsToSkip{$entry->get_value('cn')};
        my $oldSID = $entry->get_value('sambaSID');
        my ($lastNumbers) = $oldSID =~ /.*-(\d+)$/;
        my $newSID = "$sid-$lastNumbers";
        $ldap->modifyAttribute($entry->dn(), 'sambaSID', $newSID);
    }
}

sub _isSambaObject
{
    my ($self, $object, $dn) = @_;

    my $ldap = $self->{ldap};

    my %attrs = (
            base   => $dn,
            filter => "(objectclass=$object)",
            attrs  => [ 'objectClass'],
            scope  => 'base'
            );

    my $ret;
    try {
        my $result = $ldap->search(\%attrs);
        if ($result->count ==  1) {
            $ret = 1;
        }
    } otherwise {};

    return $ret;
}

# return a ref to a list of the paths of all (users and group) shared directories
sub sharedDirectories
{
    my ($self) = @_;

    my @dirs;
    @dirs = map {
        $_->{path}
    } @{ $self->groupShareDirectories() };

    my $users = EBox::Global->modInstance('users');
    defined $users or throw EBox::Exceptions::Internal('Cannot get users and groups module');

    my @homedirs = map {  $_->{homeDirectory}} $users->users();
    push @dirs, @homedirs;

    return \@dirs;
}

sub basePath
{
    return BASEPATH;
}

sub  usersPath
{
    return USERSPATH;
}

sub groupsPath
{
    return GROUPSPATH;
}

sub schemas
{
    return [
        EBox::Config::share() . "zentyal-samba/samba.ldif",
        EBox::Config::share() . "zentyal-samba/ebox.ldif",
    ];
}

sub indexes
{
    return ['sambaSID', 'sambaGroupType', 'sambaSIDList', 'sambaDomainName'];
}

sub acls
{
    my ($self) = @_;

    return [ "to attrs=sambaNTPassword,sambaLMPassword " .
            "by dn=\"" . $self->{ldap}->rootDn() . "\" write by self write " .
            "by * none" ];
}

# Method: defaultUserModel
#
#   Overrides <EBox::UsersAndGrops::LdapUserBase::defaultUserModel>
#   to return our default user template
sub defaultUserModel
{
    return 'samba/SambaUser';
}

1;
