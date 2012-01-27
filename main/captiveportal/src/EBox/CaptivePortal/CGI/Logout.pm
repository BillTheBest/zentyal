# Copyright (C) 2011-2012 eBox Technologies S.L.
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

package EBox::CaptivePortal::CGI::Logout;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use Apache2::RequestUtil;

sub new
{
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	bless($self, $class);
	return $self;
}

sub _process
{
	my ($self) = @_;

	my $r = Apache2::RequestUtil->request;
	my $auth_type = $r->auth_type;


	$self->{redirect} = "/Login";
	$self->{errorchain} = "/Logout";

	# Delete the cookie
	$auth_type->logout($r);
}

1;
