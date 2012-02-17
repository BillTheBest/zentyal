# Copyright (C) 2008-2011 eBox Technologies S.L.
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

package EBox::JabberLdapUser;

use base qw(EBox::LdapUserBase);

use strict;
use warnings;

use EBox::Gettext;
use EBox::Global;
use EBox::Config;
use EBox::Ldap;
use EBox::UsersAndGroups;
use EBox::UsersAndGroups::User;
use EBox::Model::ModelManager;

sub new
{
    my $class = shift;
    my $self  = {};
    $self->{ldap} = EBox::Ldap->instance();
    $self->{jabber} = EBox::Global->modInstance('jabber');
    bless($self, $class);
    return $self;
}

sub _userAddOns
{
    my ($self, $user) = @_;

    return unless ($self->{jabber}->configured());

    my $active = 'no';
    $active = 'yes' if ($self->hasAccount($user));

    my $is_admin = 0;
    $is_admin = 1 if ($self->isAdmin($user));

    my @args;
    my $args = {
            'user'     => $user,
            'active'   => $active,
            'is_admin' => $is_admin,
            'service'  => $self->{jabber}->isEnabled(),
           };

    return { path => '/jabber/jabber.mas', params => $args };
}

sub schemas
{
    return [ EBox::Config::share() . 'zentyal-jabber/jabber.ldif' ]
}

sub isAdmin
{
    my ($self, $user) = @_;

    return ($user->get('jabberAdmin') eq 'TRUE');
}

sub setIsAdmin
{
    my ($self, $user, $option) = @_;

    if ($option){
        $user->set('jabberAdmin', 'TRUE');
    } else {
        $user->set('jabberAdmin', 'FALSE');
    }
    my $global = EBox::Global->getInstance();
    $global->modChange('jabber');

    return 0;
}

sub hasAccount
{
    my ($self, $user) = @_;

    if ($user->get('jabberUid')) {
        return 1;
    }
    return 0;
}

sub setHasAccount
{
    my ($self, $user, $option) = @_;

    if ($self->hasAccount($user) and not $option) {
        my @objectclasses = $user->get('objectClass');
        @objectclasses = grep { $_ ne 'userJabberAccount' } @objectclasses;

        $user->delete('jabberUid');
        $user->delete('jabberAdmin');
        $user->set('objectClass',\@objectclasses, 1);
        $user->save();
    }
    elsif (not $self->hasAccount($user) and $option) {
        my @objectclasses = $user->get('objectClass');
        push (@objectclasses, 'userJabberAccount');

        $user->set('jabberUid', $user->name(), 1);
        $user->set('jabberAdmin', 'FALSE', 1);
        $user->set('objectClass', \@objectclasses, 1);
        $user->save();
    }

    return 0;
}

sub getJabberAdmins
{
    my $self = shift;

    my $global = EBox::Global->getInstance();
    my $users = $global->modInstance('users');
    my $dn = $users->usersDn;
    my @admins = ();

    $users->{ldap}->ldapCon;
    my $ldap = $users->{ldap};

    my %args = (base => $dn, filter => 'jabberAdmin=TRUE');
    my $mesg = $ldap->search(\%args);

    foreach my $entry ($mesg->entries) {
        push (@admins, new EBox::UsersAndGroups::User(entry => $entry));
    }

    return \@admins;
}


sub _addUser
{
   my ($self, $user, $password) = @_;

   unless ($self->{jabber}->configured()) {
       return;
   }
   my $model = EBox::Model::ModelManager::instance()->model('jabber/JabberUser');
   $self->setHasAccount($user, $model->enabledValue());
}


sub _delUserWarning
{
    my ($self, $user) = @_;

    return unless ($self->{jabber}->configured());

    $self->hasAccount($user) or return;

    my $txt = __('This user has a jabber account. If the user currently connected it will continue connected until jabber authorization is again required.');

    return $txt;
}

# Method: defaultUserModel
#
#   Overrides <EBox::UsersAndGrops::LdapUserBase::defaultUserModel>
#   to return our default user template
#
sub defaultUserModel
{
    return 'jabber/JabberUser';
}

1;
