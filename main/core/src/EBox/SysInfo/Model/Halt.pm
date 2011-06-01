# Copyright (C) 2011 eBox Technologies S.L.
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

package EBox::SysInfo::Model::Halt;

use strict;
use warnings;

use base 'EBox::Model::DataForm';

use EBox::Global;
use EBox::Gettext;
use EBox::Types::Action;

sub new
{
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    bless ( $self, $class );

    return $self;
}

sub _table
{
    my ($self) = @_;

    my $customActions = [
        new EBox::Types::Action(
            name => 'halt',
            printableValue => __('Halt'),
            model => $self,
            handler => \&_doHalt,
            message => __('Zentyal is going down for halt'),
        ),
        new EBox::Types::Action(
            name => 'reboot',
            printableValue => __('Reboot'),
            model => $self,
            handler => \&_doReboot,
            message => __("Zentyal is going down for reboot"),
        ),
    ];

    my $form = {
        tableName => 'Halt',
        modelDomain => 'SysInfo',
        pageTitle => __('Halt or Reboot'),
        defaultActions => [],
        customActions => $customActions,
        tableDescription => [],
        message =>  __('You might lose your Internet connection if this machine is halted.'),
        messageClass => 'warning',
    };
    return $form;
}

# Method: popMessage
#
#     Get the message to show. Overrided to not delete the current message,
#     messages of this model are permanent (till reboot) by default.
#
# Overrides:
#
#     EBox::SysInfo::Model::DataTable::popMessage
sub popMessage
{
    my ($self) = @_;
    return $self->message();
}

sub _doHalt
{
    my ($self, $action, %params) = @_;
    EBox::Sudo::root('/sbin/halt');
    $self->setMessage($action->message(), 'note');
    $self->{customActions} = {};
}

sub _doReboot
{
    my ($self, $action, %params) = @_;
    EBox::Sudo::root("/sbin/reboot");
    $self->setMessage($action->message(), 'note');
    $self->{customActions} = {};
}

1;
