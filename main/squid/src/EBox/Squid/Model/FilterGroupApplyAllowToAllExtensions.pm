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


package EBox::Squid::Model::FilterGroupApplyAllowToAllExtensions;
#
use strict;
use warnings;

use base 'EBox::Squid::Model::ApplyAllowToAllBase';

use EBox::Global;
use EBox::Gettext;


sub new
{
      my ($class, @params) = @_;

      my $self = $class->SUPER::new(@params);
      bless( $self, $class );

      return $self;
}


sub elementsPrintableName
{
  my ($class) = @_;
  return __('extensions');
}


sub printableTableName
{
  my ($class) = @_;
  return __('Set policy for all extensions');
}


sub listModel
{
  my $squid = EBox::Global->modInstance('squid');
  return $squid->model('FilterGroupExtensionFilter');
}


sub precondition
{
    my ($self) = @_;

    my $parentComposite = $self->topParentComposite();
    my $useDefault = $parentComposite->componentByName('UseDefaultExtensionFilter', 1);

    return not $useDefault->useDefaultValue();
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
