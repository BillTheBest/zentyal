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

package EBox::CGI::UsersAndGroups::ModifyGroup;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Global;
use EBox::UsersAndGroups;
use EBox::UsersAndGroups::Group;
use EBox::Gettext;
use EBox::Exceptions::External;

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new('title' => 'Users and Groups',
                      @_);
    bless($self, $class);
    return $self;
}

sub _process
{
    my $self = shift;

    $self->_requireParam('groupname', __('group name'));
    my $group = $self->unsafeParam('groupname');

    $self->{errorchain} = "UsersAndGroups/Group";

    $self->cgi()->param(-name=>'group', -value=>$group);
    $self->keepParam('group');

    $self->_requireParamAllowEmpty('comment', __('comment'));

    my $group = new EBox::UsersAndGroups::Group(dn => $group);
    $group->set('description', $self->param('comment'));

    $self->{redirect} = 'UsersAndGroups/Group?group=' . $group->dn();
}

1;
