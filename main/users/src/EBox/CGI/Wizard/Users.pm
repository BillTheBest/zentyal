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

package EBox::CGI::UsersAndGroups::Wizard::Users;

use strict;
use warnings;

use base 'EBox::CGI::WizardPage';

use EBox::Global;
use EBox::Gettext;
use EBox::Validate;
use Error qw(:try);

sub new # (cgi=?)
{
    my $class = shift;
    my $self = $class->SUPER::new('template' => 'users/wizard/users.mas',
                                  @_);
    bless($self, $class);
    return $self;
}


sub _processWizard
{
    my ($self) = @_;

    if ( $self->param('standalone') ) {
        EBox::info('enabling usersandgroups module');
        my $mgr = EBox::ServiceManager->new();
        my $global = EBox::Global->getInstance();

        my $module = $global->modInstance('users');

        # don't enable if already configured
        return if ($module->configured());

        $module->setConfigured(1);
        $module->enableService(1);
        try {
            $module->enableActions();
        } otherwise {
            my ($ex) = @_;
            my $err = $ex->text();
            $module->setConfigured(0);
            $module->enableService(0);
            EBox::debug("Failed to enable module usersandgroups: $err");
        };
    }
}

1;
