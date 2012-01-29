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

# Class: EBox::CGI::Controller::Downloader::Base
#
#   This is the base cgi to implement controllers to download files
#
package EBox::CGI::Controller::Downloader::Base;

use strict;
use warnings;

use base 'EBox::CGI::ClientRawBase';

use EBox::Gettext;
use EBox::Global;
use EBox::Exceptions::NotImplemented;

# Core modules
use File::Basename;
use Error qw(:try);

# Dependencies
use File::MMagic;

# Group: Public methods

# Constructor: new
#
#      Create a <EBox::CGI::Controller::Downloader::Base>
#
#
sub new # (cgi=?)
{
    my ($class, %params) = @_;
    my $self = $class->SUPER::new(@_);
    bless($self, $class);
    return  $self;
}

# Group: Protected methods

# Method: _path
#
#   This method must be overriden by subclasses to return the path
#   of the file to download
#
# Exceptions:
#
#      <EBox::Exceptions::NotImplemented> - thrown if this method
#      is not implemented by the subclass
sub _path
{
    throw EBox::Exceptions::NotImplemented;
}

# Method: _process
#
# Overrides:
#
#      <EBox::CGI::ClientRawBase::_process>
#
# Exceptions:
#
#      <EBox::Exceptions::Internal> - thrown if the field name is not
#      contained in the given model
#
sub _process
{
    my ($self) = @_;

    my $path = $self->_path();

    # Setting the file
    $self->{downfile} = $path;
    # Setting the file name
    $self->{downfilename} = fileparse($path);
}

# Method: _print
#
# Overrides:
#
#     <EBox::CGI::ClientRawBase::_print>
#
sub _print
{
    my ($self) = @_;

    if ( $self->{error} or not defined($self->{downfile})) {
        $self->SUPER::_print();
        return;
    }

    my $file =  $self->{downfile};
    if (-r $file) {
        my $mm = new File::MMagic();
        my $mimeType = $mm->checktype_filename($file);
        my $size = -s $file;
        $self->_printHeader($mimeType, $size);

        open( my $downFile, '<', $file) or
            throw EBox::Exceptions::Internal('Could open file ' .
                                                 $self->{downfile} . " $!");

        # Efficient way to print a whole file
        print do { local $/; <$downFile> };

        close($downFile);
    } else {
            throw EBox::Exceptions::Internal('File does not exists or is of a special type: ' .
                                                 $file);
    }
}

sub _printHeader
{
    my ($self, $mimeType, $size) = @_;
    print($self->cgi()->header(-type => $mimeType,
                               -attachment => $self->{downfilename},
                               -Content_length => (-s $self->{downfile})),
         );
}

1;
