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


package EBox::Mail::Model::RetrievalServices;
use base 'EBox::Model::DataForm';

use strict;
use warnings;

use EBox::Global;
use EBox::Gettext;
use EBox::Validate qw(:all);
use EBox::Types::Boolean;
use EBox::Types::Select;
use EBox::Exceptions::External;


# XXX TODO: disable ssl options when no service is enabled
sub new
{
    my $class = shift @_ ;

    my $self = $class->SUPER::new(@_);
    bless($self, $class);

    return $self;
}


# Method:  _table
#
# This method overrides <EBox::Model::DataTable::_table> to return
# a table model description.
#
# This table is composed of two fields:
#
#   domain (<EBox::Types::Text>)
#   enabled (EBox::Types::Boolean>)
#
# The only avaiable action is edit and only makes sense for 'enabled'.
#
sub _table
{
    my @tableDesc =
        (
         new EBox::Types::Boolean(
                                  fieldName => 'pop3',
                                  printableName => __('POP3 service enabled'),
                                  editable => 1,
                                  defaultValue => 1,
                                 ),
         new EBox::Types::Boolean(
                                  fieldName => 'pop3s',
                                  printableName => __('Secure POP3S service enabled'),
                                  editable => 1,
                                  defaultValue => 1,
                                 ),
         new EBox::Types::Boolean(
                                  fieldName => 'imap',
                                  printableName => __('IMAP service enabled'),
                                  editable => 1,
                                  defaultValue => 1,
                                 ),
         new EBox::Types::Boolean(
                                  fieldName => 'imaps',
                                  printableName => __('Secure IMAPS service enabled'),
                                  editable => 1,
                                  defaultValue => 1,
                                 ),
         new EBox::Types::Boolean(
                                  fieldName => 'fetchmail',
                                  printableName => __('Retrieve mail for external accounts'),
                                  help =>
 __(q{This allow users to retrieve mail for external accounts, the mail would be delivered to their local account. External account can be configured in the user's corner.} ),
                                  editable => 1,
                                 ),
         new EBox::Types::Boolean(
                                  fieldName => 'managesieve',
                                  printableName => __('Manage Sieve scripts'),
                                  help =>
 __(q{This service allows to a user to manage his Sieve mail filtering scripts from a local client which speaks the ManageSieve protocol} ),
                                  editable => 1,
                                  defaultValue => 1,
                                 ),
        );

      my $dataForm = {
                      tableName          => __PACKAGE__->nameFromClass(),
                      printableTableName => __('Mail retrieval services'),
                      modelDomain        => 'Mail',
                      defaultActions     => [ 'editField', 'changeView' ],
                      tableDescription   => \@tableDesc,

                     };

    return $dataForm;
}


sub activeProtocols
{
    my ($self) = @_;
    my @protocols;

    if ($self->pop3Value()) {
        push @protocols, 'pop3';
    }

    if ($self->pop3sValue()) {
        push @protocols, 'pop3s';
    }

    if ($self->imapValue()) {
        push @protocols, 'imap';
    }

    if ($self->imapsValue()) {
        push @protocols, 'imaps';
    }

    if ($self->managesieveValue()) {
        push @protocols, 'managesieve';
    }

    return \@protocols;
}



sub validateTypedRow
{
    my ($self, $action, $params_r, $actual_r) = @_;

    my $global = EBox::Global->getInstance();

    my $pop3 = exists $params_r->{pop3} ? $params_r->{pop3}->value() :
                                          $actual_r->{pop3}->value();
    my $pop3s = exists $params_r->{pop3s} ? $params_r->{pop3s}->value() :
                                          $actual_r->{pop3s}->value();
    my $imap = exists $params_r->{imap} ? $params_r->{imap}->value() :
                                          $actual_r->{imap}->value();
    my $imaps = exists $params_r->{imaps} ? $params_r->{imaps}->value() :
                                          $actual_r->{imaps}->value();

    if ($global->modExists('zarafa')) {
        my $zarafa = $global->modInstance('zarafa');
        my $gws = $zarafa->model('Gateways');

        my $serviceConflict = undef;

        if ($pop3 and $gws->pop3Value()) {
            $serviceConflict = 'POP3';
        } elsif ($pop3s and $gws->pop3sValue()) {
            $serviceConflict = 'POP3S';
        } elsif ($imap and $gws->imapValue()) {
            $serviceConflict = 'IMAP';
        } elsif ($imaps and $gws->imapsValue()) {
            $serviceConflict = 'IMAPS';
        }

        if (defined $serviceConflict) {
            throw EBox::Exceptions::External(__x('To enable {service} mail retrieval service you must disable {service} gateway for Zarafa. You can do it at {ohref}Zarafa gateways configuration settings{chref}.',
            service => $serviceConflict,
            ohref => q{<a href='/zentyal/Zarafa/Composite/General/'>},
            chref => q{</a>}));
        }
    }

    # validate IMAP services changes
    if ((not exists $params_r->{imap}) and (not exists $params_r->{imaps})) {
        return;
    }

    foreach my $mod (@{ $global->modInstances() }) {
        if ($mod->can('validateIMAPChanges') and $mod->isEnabled()) {
            $mod->validateIMAPChanges($imap, $imaps);
        }
    }
}

1;
