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

package EBox::CGI::SysInfo::Log;

use strict;
use warnings;

use EBox;
use EBox::Config;
use EBox::Gettext;
use EBox::Util::BugReport;

use base 'EBox::CGI::ClientBase';

sub new # (cgi=?)
{

    my $class = shift;
    my $self = $class->SUPER::new(@_);
    bless($self, $class);
    return $self;
}

sub actuate
{
    my ($self) = @_;

    $self->{downfilename} = 'zentyal.log';
}

sub _print
{
    my ($self) = @_;

    if ($self->{error}) {
        $self->SUPER::_print;
        return;
    }

    print ($self->cgi()->header(-type=>'application/octet-stream',
                                -attachment=>$self->{downfilename}));

    print EBox::Util::BugReport::dumpLog();
}

1;
