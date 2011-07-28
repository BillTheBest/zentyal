# Copyright (C) 2010-2011 eBox Technologies S.L.
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

package EBox::CGI::Mail::Wizard::VirtualDomain;

use strict;
use warnings;

use base 'EBox::CGI::WizardPage';

use EBox::Global;
use EBox::Gettext;
use EBox::Exceptions;
use EBox::Validate;
use Error qw(:try);

sub new # (cgi=?)
{
    my $class = shift;
    my $self = $class->SUPER::new('template' => 'mail/wizard/virtualdomain.mas',
                                  @_);
    bless($self, $class);
    return $self;
}

sub _processWizard
{
    my ($self) = @_;

    $self->_requireParam('vdomain', __('Mail virtual domain'));
    my $domain = $self->param('vdomain');

    unless ( EBox::Validate::_checkDomainName($domain) ) {
        throw EBox::Exceptions::External(__('Invalid virtual mail domain'));
    }

    my $global = EBox::Global->getInstance();
    my $mail = $global->modInstance('mail');
    my $model = $mail->model('VDomains');

    $model->addRow(vdomain => $domain, aliases => []);

    if ($global->modExists('egroupware')) {
        my $egw = $global->modInstance('egroupware');
        my $model = $egw->model('VMailDomain');

        my $row = $model->row();
        $row->elementByName('vdomain')->setValue($domain);
        $row->store();
    }
}

1;
