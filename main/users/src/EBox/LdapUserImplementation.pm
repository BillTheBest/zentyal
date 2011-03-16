# Copyright (C) 2008-2010 eBox Technologies S.L.
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

package EBox::LdapUserImplementation;

use strict;
use warnings;

use base qw(EBox::LdapUserBase);

use EBox::Global;
use EBox::Gettext;


sub _create {
	my $class = shift;
	my $self = {};
	bless($self, $class);
	return $self;
}


sub _delGroupWarning($$) {
        my $self = shift;
        my $group = shift;

	my $users = EBox::Global->modInstance('users');

	unless ($users->_groupIsEmpty($group)) {
		return (__('This group contains users'));
	}

	return undef;
}

sub schemas
{
    return [
        EBox::Config::share() . '/zentyal-users/passwords.ldif',
        EBox::Config::share() . '/zentyal-users/master.ldif',
        EBox::Config::share() . '/zentyal-users/slaves.ldif',
        EBox::Config::share() . '/zentyal-users/quota.ldif',
    ];
}

sub acls
{
    my $users = EBox::Global->modInstance('users');
    return [ "to attrs=" . join(',',
            @{EBox::UsersAndGroups::Passwords::allPasswordFieldNames()}) . " " .
            "by dn=\"" . $users->ldap()->rootDn() . "\" write by self write " .
            "by * none" ];
}

sub indexes
{
    return [
        'uid', 'uidNumber', 'memberUid', 'cn', 'gidNumber', 'uniqueMember'
    ];
}

1;
