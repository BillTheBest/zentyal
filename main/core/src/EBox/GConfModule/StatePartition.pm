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

package EBox::GConfModule::StatePartition;
#
use strict;
use warnings;

use base 'EBox::GConfModule::Partition';



sub new
{
  my ($class, $base, $fullModule) = @_;

  my $self = $class->SUPER::new($base, $fullModule);
  bless $self, $class;

  return $self;
}

sub _checkBaseDirExists
{
  my ($class, $fullModule, $base) = @_;
  return $fullModule->st_dir_exists($base);
}


sub _fullModuleMethod
{
  my ($self, $method, @params) = @_;
  $method = 'st_' . $method; # to convert methods in state methods
  return $self->fullModule->$method(@params);
}


1;
