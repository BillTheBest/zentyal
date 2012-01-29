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

package EBox::CGI::RemoteServices::Backup::DownloadRemoteBackup;
use base qw(EBox::CGI::ClientBase);

use strict;
use warnings;

use EBox::RemoteServices::Backup;
use EBox::Gettext;
use EBox::Exceptions::Internal;
use EBox::Exceptions::External;


sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new( @_);
	$self->{errorchain} = "RemoteServices/Backup/Index";
	bless($self, $class);
	return $self;
}

# Method: _print
#
#      Print directly the file to download
#
# Overrides:
#
#      <EBox::CGI::Base::_print>
#
sub _print
{
    my ($self) = @_;
    if ( $self->{error} ) {
        $self->SUPER::_print;
        return;
    }

    my $name   = $self->param('name');
    my $backup = new EBox::RemoteServices::Backup();

    print($self->cgi()->header(
        -type       => 'application/x-tar',
        -attachment => "$name.tar",
       ));
    $backup->downloadRemoteBackup($name, \*STDOUT);
}

sub requiredParameters
{
  return [qw(name)];
}

1;
