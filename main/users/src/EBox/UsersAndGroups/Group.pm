#!/usr/bin/perl -w

# Copyright (C) 2012 eBox Technologies S.L.
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

# Class: EBox::UsersAndGroups::Group
#
#   Zentyal group, stored in LDAP
#

package EBox::UsersAndGroups::Group;

use strict;
use warnings;

use EBox::Config;
use EBox::Global;
use EBox::Gettext;
use EBox::UsersAndGroups::User;

use EBox::Exceptions::External;
use EBox::Exceptions::MissingArgument;
use EBox::Exceptions::InvalidData;

use constant SYSMINGID      => 1900;
use constant MINUID         => 2000;
use constant MINGID         => 2000;
use constant MAXGROUPLENGTH => 128;
use constant CORE_ATTRS     => ('member');

use Perl6::Junction qw(any);

use base 'EBox::UsersAndGroups::LdapObject';

sub new
{
    my $class = shift;
    my %opts = @_;
    my $self = $class->SUPER::new(@_);
    bless($self, $class);
    return $self;
}


# Method: name
#
#   Return group name
#
sub name
{
    my ($self) = @_;
    return $self->_entry->get('cn');
}


# Method: addMember
#
#   Adds the given user as a member
#
# Parameters:
#
#   user - User object
#
sub addMember
{
    my ($self, $user, $lazy) = @_;

    my @members = $self->_entry->get('member');
    push (@members, $user->dn());

    $self->set('member', \@members, $lazy);
}


# Method: removeMember
#
#   Removes the given user as a member
#
# Parameters:
#
#   user - User object
#
sub removeMember
{
    my ($self, $user, $lazy) = @_;

    my @members;
    foreach my $dn ($self->_entry->get('member')) {
        push (@members, $dn) if ($dn ne $user->dn());
    }

    $self->set('member', \@members, $lazy);
}


# Method: users
#
#   Return the list of members for this group
#
# Returns:
#
#   arrary ref of members (EBox::UsersAndGroups::User)
#
sub users
{
    my ($self, $system) = @_;

    my @members = $self->_entry->get('member');
    @members = map { new EBox::UsersAndGroups::User(dn => $_) } @members;

    unless ($system) {
        @members = grep { not $_->system() } @members;
    }

    return \@members;
}


# Method: usersNotIn
#
#   Users that don't belong to this group
#
#   Returns:
#
#       array ref of EBox::UsersAndGroups::Group objects
#
sub usersNotIn
{
    my ($self, $system) = @_;

    my %attrs = (
            base => $self->_ldap->dn(),
            filter => "(&(objectclass=posixAccount)(!(memberof=$self->{dn})))",
            scope => 'sub',
            );

    my $result = $self->_ldap->search(\%attrs);

    my @users;
    if ($result->count > 0)
    {
        foreach my $entry ($result->sorted('uid'))
        {
            push (@users, new EBox::UsersAndGroups::User(entry => $entry));
        }
    }
    unless ($system) {
        @users = grep { not $_->system() } @users;
    }
    return \@users;
}


# Catch some of the set ops which need special actions
sub set
{
    my ($self, $attr, $value) = @_;

    # remember changes in core attributes (notify LDAP user base modules)
    if ($attr eq any CORE_ATTRS) {
        $self->{core_changed} = 1;
    }

    shift @_;
    $self->SUPER::set(@_);
}



# Method: deleteObject
#
#   Delete the user
#
sub deleteObject
{
    my ($self, $ignore_mods) = @_;


    # Notify group deletion to modules
    my $users = EBox::Global->modInstance('users');
    $users->notifyModsLdapUserBase('delGroup', $self, $ignore_mods);

    # Call super implementation
    shift @_;
    $self->SUPER::deleteObject(@_);
}




sub save
{
    my ($self, $ignore_mods) = @_;

    shift @_;
    $self->SUPER::save(@_);

    if ($self->{core_changed}) {
        delete $self->{core_changed};

        my $users = EBox::Global->modInstance('users');
        $users->notifyModsLdapUserBase('modifyGroup', $self, $ignore_mods);
    }
}

# GROUP CREATION METHODS


# Method: create
#
#       Adds a new group
#
# Parameters:
#
#   group - group name
#   comment - comment's group
#   system - boolan: if true it adds the group as system group,
#   otherwise as normal group
#   ignore_mods - ldap modules to be ignored on addUser notify
#
sub create
{
    my ($self, $group, $comment, $system, %params) = @_;

    my $users = EBox::Global->modInstance('users');
    my $dn = $users->groupDn($group);

    if (length($group) > MAXGROUPLENGTH) {
        throw EBox::Exceptions::External(
            __x("Groupname must not be longer than {maxGroupLength} characters",
                maxGroupLength => MAXGROUPLENGTH));
    }

    unless (_checkName($group)) {
        throw EBox::Exceptions::InvalidData(
            'data' => __('group name'),
            'value' => $group);
    }

    # Verify group exists
    if (new EBox::UsersAndGroups::Group(dn => $dn)->exists()) {
        throw EBox::Exceptions::DataExists(
            'data' => __('group'),
            'value' => $group);
    }

    my $gid = exists $params{gidNumber} ?
                     $params{gidNumber} :
                     $self->_gidForNewGroup($system);

    $self->_checkGid($gid, $system);

    my %args = (
        attr => [
            'cn'          => $group,
            'gidNumber'   => $gid,
            'objectclass' => ['posixGroup', 'zentyalGroup'],
        ]
    );
    push (@{$args{attr}}, 'description' => $comment) if ($comment);

    my $r = $self->_ldap->add($dn, \%args);

    my $res = new EBox::UsersAndGroups::Group(dn => $dn);

    unless ($system) {
        # Call modules initialization
        $users->notifyModsLdapUserBase('addGroup', $res, $params{ignore_mods});
    }

    return $res;
}


sub _checkName
{
    my ($name) = @_;

    if ($name =~ /^([a-zA-Z\d\s_-]+\.)*[a-zA-Z\d\s_-]+$/) {
        return 1;
    } else {
        return undef;
    }
}


sub system
{
    my ($self) = @_;

    return ($self->get('gidNumber') < MINGID);
}


sub _gidForNewGroup
{
    my ($self, $system) = @_;

    my $gid;
    if ($system) {
        $gid = $self->lastGid(1) + 1;
        if ($gid == MINGID) {
            throw EBox::Exceptions::Internal(
                __('Maximum number of groups reached'));
        }
    } else {
        $gid = $self->lastGid + 1;
    }

    return $gid;
}



# Method: lastGid
#
#       Returns the last gid used.
#
# Parameters:
#
#       system - boolan: if true, it returns the last gid for system users,
#       otherwise the last gid for normal users
#
# Returns:
#
#       string - last gid
#
sub lastGid # (gid)
{
    my ($self, $system) = @_;

    my %args = (
        base => $self->_ldap->dn(),
        filter => '(objectclass=posixGroup)',
        scope => 'one',
        attrs => ['gidNumber']
    );

    my $result = $self->_ldap->search(\%args);
    my @users = $result->sorted('gidNumber');

    my $gid = -1;
    foreach my $user (@users) {
        my $currgid = $user->get_value('gidNumber');
        if ($system) {
            last if ($currgid > MINGID);
        } else {
            next if ($currgid < MINGID);
        }

        if ( $currgid > $gid){
            $gid = $currgid;
        }
    }

    if ($system) {
        return ($gid < SYSMINGID ?  SYSMINGID : $gid);
    } else {
        return ($gid < MINGID ?  MINGID : $gid);
    }
}


sub _checkGid
{
    my ($self, $gid, $system) = @_;

    if ($gid < MINGID) {
        if (not $system) {
            throw EBox::Exceptions::External(
                 __x('Incorrect GID {gid} for a group . GID must be equal or greater than {min}',
                     gid => $gid,
                     min => MINGID,
                    )
                );
        }
    }
    else {
        if ($system) {
            throw EBox::Exceptions::External(
               __x('Incorrect GID {gid} for a system group . GID must be lesser than {max}',
                    gid => $gid,
                    max => MINGID,
                   )
               );
        }
    }
}


1;
