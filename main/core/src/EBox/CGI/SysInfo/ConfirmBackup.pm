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

package EBox::CGI::SysInfo::ConfirmBackup;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Config;
use EBox::Backup;
use EBox::Gettext;
use EBox::Exceptions::Internal;
use EBox::Exceptions::External;
use Error qw(:try);

sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new('title' => __('Configuration Backup'),
				      'template' => '/confirm-backup.mas',
				      @_);
	bless($self, $class);

	$self->{errorchain} = "SysInfo/Backup";

	return $self;
}


sub requiredParameters
{
  my ($self) = @_;

  if ($self->param('download.x')) {
    return [qw(id download.x download.y)];
  }
  elsif ($self->param('delete.x')) {
    return [qw(id delete.x delete.y)];
  }
  elsif ($self->param('restoreFromId.x')) {
    return [qw(restoreFromId.x restoreFromId.y id)];
  }
  elsif ($self->param('restoreFromFile')) {
    return [qw(restoreFromFile backupfile)];
  }

  return [];
}


sub optionalParameters
{
    return ['download', 'delete', 'restoreFromId'];
}


sub actuate
{
  my ($self) = @_;

  if (defined($self->param('download.x'))) {
    $self->{chain} = 'SysInfo/Backup';
    return;
  }

  foreach my $actionParam (qw(delete restoreFromId restoreFromFile )) {
    if ($self->param($actionParam)) {
      my $actionSub = $self->can($actionParam . 'Action');
      my ($backupAction, $backupActionText, $backupDetails) = $actionSub->($self);
      $self->{params} = [action => $backupAction, actiontext => $backupActionText, backup => $backupDetails];
      return;
    }
  }


  # otherwise...
  $self->{redirect} = "SysInfo/Backup";
  return;
}


sub masonParameters
{
  my ($self) = @_;

  if (exists $self->{params}) {
    return $self->{params};
  }

  return [];
}

sub deleteAction
{
  my ($self) = @_;

  $self->{msg} = __('Please confirm that you want to delete the following backup file:');

  return ('delete', __('Delete'), $self->backupDetailsFromId());
}

sub  restoreFromIdAction
{
  my ($self) = @_;

  $self->{msg} = __('Please confirm that you want to restore using this backup file:');

  return ('restoreFromId', __('Restore'), $self->backupDetailsFromId());
}




sub  restoreFromFileAction
{
  my ($self) = @_;

  my $filename = $self->upload('backupfile');

  my $details = $self->backupDetailsFromFile($filename);

  $self->{msg} = __('Please confirm that you want to restore using this backup file:');

  return ('restoreFromFile', __('Restore'), $details);
}





sub backupDetailsFromId
{
  my ($self) = @_;
  my $backup = new EBox::Backup;

  my $id = $self->param('id');
  if ($id =~ m{[./]}) {
    throw EBox::Exceptions::External(
				     __("The input contains invalid characters"));
  }

  my $details =  $backup->backupDetails($id);
  $self->setPrintabletype($details);

  return $details;
}


sub backupDetailsFromFile
{
  my ($self, $filename) = @_;
  my $details = EBox::Backup->backupDetailsFromArchive($filename);

  $self->setPrintabletype($details);

  return $details;
}


sub setPrintabletype
{
  my ($self, $details_r) = @_;

  my $type = $details_r->{type};
  my $printableType;

  if ($type eq $EBox::Backup::CONFIGURATION_BACKUP_ID) {
    $printableType = __('Configuration backup');
  }
  elsif ($type eq $EBox::Backup::FULL_BACKUP_ID) {
    $printableType = __('Full data and configuration backup');
  }
  elsif ($type eq $EBox::Backup::BUGREPORT_BACKUP_ID) {
    $printableType = __('Bug-report configuration dump');
  }


  $details_r->{printableType} = $printableType;
  return $details_r;
}


1;
