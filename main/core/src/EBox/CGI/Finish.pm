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

package EBox::CGI::Finish;

use strict;
use warnings;

use base qw(EBox::CGI::ClientBase EBox::CGI::ProgressClient);

use EBox::Config;
use EBox::Global;
use EBox::Gettext;
use EBox::ServiceManager;
use Error qw(:try);

sub new # (error=?, msg=?, cgi=?)
{
    my $class = shift;
    my $self = $class->SUPER::new('title' => __('Save configuration'),
            'template' => '/finish.mas',
            @_);
    bless($self, $class);
    return $self;
}

sub _process
{
    my $self = shift;

    my $global = EBox::Global->getInstance();

    if (defined($self->param('save'))) {
        $self->saveAllModulesAction();
    } elsif (defined($self->param('cancel'))) {
        $self->revokeAllModulesAction();
    } else {
        if ($global->unsaved) {
            my $manager = new EBox::ServiceManager();
            my $askPermission = defined @{$manager->checkFiles()};
            my @array = ();
            push(@array, 'unsaved' => 'yes');
            push(@array, 'askPermission' => $askPermission);
            push(@array, 'disabledModules' => _disabledModules());
            push(@array, 'actions' => _pendingActions());
            $self->{params} = \@array;
        }
    }
}

sub _pendingActions
{
    my $global = EBox::Global->getInstance(1);
    my $audit = EBox::Global->modInstance('audit');
    my $ret = $audit->queryPending();

    my $actions = [];
    foreach my $action (@{$ret}) {
        my $modname = $action->{'module'};
        my $model = $action->{'model'};
        my $rowName;
        if($global->modExists($modname)) {
            my $mod = EBox::Global->modInstance($modname);
            $action->{'modtitle'} = $mod->title();
            try {
                my $modelInstance = $mod->model($model);
                $action->{'modeltitle'} = $modelInstance->printableName();
                $rowName = $modelInstance->printableRowName();
            } otherwise {
                $action->{'modeltitle'} = $action->{'model'};
            };
        } else {
            $action->{'modtitle'} = $modname;
        }
        my $event = $action->{'event'};
        my $id = $action->{'id'};
        my $value = $action->{'value'};
        my $oldvalue = $action->{'oldvalue'};
        unless ($rowName) {
            $rowName = __('row');
        }
        my $message;
        if ($event eq 'del') {
            $message = __x('The {rowName} "{r}" has been deleted',
                           rowName => $rowName, r => $id);
        } elsif ($event eq 'move') {
            $message = __x('The {rowName} "{r}" has been moved from {x} to {y} position',
                           rowName => $rowName, r => $id, x => $oldvalue, y => $value);
        } elsif ($event eq 'action') {
            my $action = $value ? "$id($value)" : $id;
            $message = __x('The action "{a}" has been executed', a => $action);
        } else {
            my ($parent, $row, $field) = split (/\//, $id);
            if (defined ($parent) and defined ($row)) {
                if (defined ($field)) {
                    $row = "$parent/$row";
                } else {
                    ($row, $field) = ($parent, $row);
                }
                if ($event eq 'add') {
                    $message = __x('A new {rowName} "{r}" has been added with "{f}" set to "{x}"',
                                   f => $field, rowName => $rowName, r => $row, x => $value);
                } elsif ($event eq 'set') {
                    $message = __x('The field "{f}" in the {rowName} "{r}" has been changed from "{x}" to "{y}"',
                                   f => $field, rowName => $rowName, r => $row, x => $oldvalue, y => $value);
                }
            } else {
                if (($event eq 'set') and defined ($oldvalue)) {
                    $message = __x('The value of "{id}" has been changed from "{x}" to "{y}"',
                                   id => $id, x => $oldvalue, y => $value);
                } else {
                    $message = __x('The value of "{id}" has been set to "{x}"', id => $id, x => $oldvalue);
                }
            }
        }
        $action->{'message'} = $message;
        push(@{$actions}, $action);
    }
    return $actions;
}

sub saveAllModulesAction
{
    my ($self) = @_;

    $self->{redirect} = "/Dashboard/Index";

    my $global = EBox::Global->getInstance();
    my $progressIndicator = $global->prepareSaveAllModules();

    $self->showProgress(
        progressIndicator  => $progressIndicator,
        title              => __('Saving changes'),
        text               => __('Saving changes in modules'),
        currentItemCaption => __("Current operation"),
        itemsLeftMessage   => __('operations performed'),
        endNote            => __('Changes saved'),
        errorNote          => __x('Some modules reported error when saving changes '
                                  . '. More information on the logs in {dir}',
                                  dir => EBox::Config->log()),
        reloadInterval  => 2,
       );
}


sub revokeAllModulesAction
{
    my ($self) = @_;

    $self->{redirect} = "/Dashboard/Index";

    my $global = EBox::Global->getInstance();
    my $progressIndicator = $global->prepareRevokeAllModules();

    $self->showProgress(
        progressIndicator => $progressIndicator,
        title    => __('Revoking changes'),
        text     => __('Revoking changes in modules'),
        currentItemCaption  =>  __("Current module"),
        itemsLeftMessage  => __('modules revoked'),
        endNote  =>  __('Changes revoked'),
        errorNote => __x('Some modules reported error when discarding changes '
                           . '. More information on the logs in {dir}',
                         dir => EBox::Config->log()),
        reloadInterval  => 2,
       );
}

# Method: _disabledModules
#
#   Return those modules with unsaved changes that are disabled
sub _disabledModules
{
    my $global = EBox::Global->getInstance();
    my @modules;
    for my $modName (@{$global->modifiedModules('save')}) {
        my $modInstance = $global->modInstance($modName);
        next unless ($modInstance->isa('EBox::Module::Service'));
        next if ($modInstance->isEnabled());
        next unless ($modInstance->showModuleStatus());
        push (@modules, $modInstance->printableName());
    }
    return \@modules;
}
1;
