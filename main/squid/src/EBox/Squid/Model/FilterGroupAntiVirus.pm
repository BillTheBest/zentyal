# Copyright (C) 2009-2012 eBox Technologies S.L.
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



package EBox::Squid::Model::FilterGroupAntiVirus;
use base 'EBox::Squid::Model::AntiVirusBase';

use strict;
use warnings;

use EBox::Global;
use EBox::Gettext;




use EBox::Exceptions::External;

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

#
sub _table
{
    my ($self) = @_;

    my $tableDescription = $self->_tableDescription();


    my $dataForm = {
        tableName          => 'FilterGroupAntiVirus',
        printableTableName => __('Filter virus'),
        modelDomain        => 'Squid',
        defaultActions     => [ 'editField', 'changeView' ],
        tableDescription   => $tableDescription,
        class              => 'dataForm',
    };



    return $dataForm;
}

# Method: viewCustomizer
#
#   Overrides <EBox::Model::DataTable::viewCustomizer>
#   to show breadcrumbs
sub viewCustomizer
{
        my ($self) = @_;

        my $custom =  $self->SUPER::viewCustomizer();
        $custom->setHTMLTitle([ ]);

        return $custom;
}

1;

