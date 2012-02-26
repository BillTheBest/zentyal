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

package EBox::CGI::UsersAndGroups::AddUser;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::UsersAndGroups;
use EBox::Gettext;
use EBox::Exceptions::External;

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new('title' => 'Users and Groups', @_);
    bless($self, $class);
    $self->{errorchain} = 'UsersAndGroups/Users';
    return $self;
}


sub _process
{
    my $self = shift;
    my @args = ();

    $self->_requireParam('username', __('user name'));
    $self->_requireParam('surname', __('last name'));
    $self->_requireParamAllowEmpty('comment', __('comment'));

    my $user;
    $user->{'user'} = $self->param('username');
    $user->{'name'} = $self->param('name');
    $user->{'surname'} = $self->param('surname');
    if ($user->{'name'}) {
        $user->{'fullname'} = $user->{'name'} . ' ' . $user->{'surname'};
        $user->{'givenname'} = $user->{'name'};
    } else {
        $user->{'fullname'} = $user->{'surname'};
        $user->{'givenname'} = '';
    }
    $user->{'password'} = $self->unsafeParam('password');
    $user->{'repassword'} = $self->unsafeParam('repassword');
    $user->{'group'} = $self->unsafeParam('group');
    $user->{'comment'} = $self->param('comment');

    for my $field (qw/password repassword/) {
        unless (defined($user->{$field}) and $user->{$field} ne "") {
            throw EBox::Exceptions::DataMissing('data' => __($field));
        }
    }

    if ($user->{'password'} ne $user->{'repassword'}){
         throw EBox::Exceptions::External(__('Passwords do not match.'));
    }

    my %params;
    if (EBox::Config::configkey('multiple_ous')) {
        $params{ou} = $self->unsafeParam('ou');
    }

    my $newUser = EBox::UsersAndGroups::User->create($user, 0, %params);
    if ($user->{'group'}) {
        $newUser->addGroup(new EBox::UsersAndGroups::Group(dn => $user->{'group'}));
    }

    if ($self->param('addAndEdit')) {
            $self->{redirect} = "UsersAndGroups/User?user=" . $newUser->dn();
    } else {
            $self->{redirect} = "UsersAndGroups/Users";
    }
}

1;
