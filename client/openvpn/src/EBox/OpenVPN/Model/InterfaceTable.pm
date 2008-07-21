# Copyright (C) 2008 Warp Networks S.L.
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

package EBox::OpenVPN::Model::InterfaceTable;


use strict;
use warnings;

use EBox::Types::Text;
use EBox::Types::Int;



sub new
{
    throw EBox::Exceptions::Internal('Cannot be instantiated');
}

sub interfaceFields
{
    my @fields = (
                  new EBox::Types::Text
                  (
                   'fieldName' => 'interfaceType',
                   'hidden'    => 1,
                   'editable'  => 0,
                   'defaultValue' => 'tap',
                  ),
                  new EBox::Types::Int
                  (
                   'fieldName' => 'interfaceNumber',
                   'hidden' => 1,
                   'editable' => 0,
                   'min'      => -1,
                   'defaultValue' => -1,
                   # no unique bz it will not be until we call updateInterfaces
                  ),
                 );
    return @fields;
}

sub initializeInterfaces
{
    my ($self) = @_;

    foreach my $row ( @{ $self->rows() }) {
        my $interfaceNumber = $row->elementByName('interfaceNumber');
        next if $interfaceNumber->value() != -1;

        my $interfaceType = $row->elementByName('interfaceType');
        $interfaceType->setValue('tap');


        my $number = $self->_nextInterfaceNumber();
        $interfaceNumber->setValue($number);

        $row->store();
    }

}


sub _nextInterfaceNumber
{
    my ($self) = @_;


    # get all initializaed ifaces
    my @initializedIfaces = grep {
        my $number = $_->elementByName('interfaceNumber')->value();
        $number  >= 0;
    }  @{ $self->rows() };

    # get the ordererd number list
    my @numbers = sort map {
        my $number = $_->elementByName('interfaceNumber')->value();
        $number
    }  @initializedIfaces;

    EBox::debug("NUMBERS @numbers");


    my $lastNumber = -1;
    # search for holes in the numbers
    foreach my $number (@numbers) {
        my $expectedNumber = $lastNumber + 1;
        if ($number != $expectedNumber) {
            return $expectedNumber;
        }
        
        $lastNumber = $number;
    }

    # no holes founds we use last number +1
    return $lastNumber + 1;
}





1;
