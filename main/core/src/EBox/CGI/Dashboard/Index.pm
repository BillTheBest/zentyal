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

package EBox::CGI::Dashboard::Index;

use strict;
use warnings;

use base 'EBox::CGI::ClientBase';

use EBox::Gettext;
use EBox::Global;
use EBox::Dashboard::Widget;
use EBox::Dashboard::Item;
use POSIX qw(INT_MAX);
use List::Util qw(sum);
use Error qw(:try);

# TODO: Currently we can't have more than two dashboards because of
# the design of the interface, but this could be incremented in the future
my $NUM_DASHBOARDS = 2;

sub new # (error=?, msg=?, cgi=?)
{
	my $class = shift;
	my $self = $class->SUPER::new(@_, title => __('Dashboard'),
                    'template' => '/dashboard/index.mas');
	bless($self, $class);
	return $self;
}

my $widgetsToHide = undef;

# Method: masonParameters
#
# Overrides:
#
#   <EBox::CGI::Base::masonParameters>
#
sub masonParameters
{
    my ($self) = @_;

    # Delete first install file if it exists
    EBox::Global->deleteFirst();

    unless (defined $widgetsToHide) {
        $widgetsToHide = {
            map { $_ => 1 } split (/,/, EBox::Config::configkey('widgets_to_hide'))
        };
    }

    my $global = EBox::Global->getInstance(1);
    my $sysinfo = $global->modInstance('sysinfo');
    my @modNames = @{$global->modNames()};
    my $widgets = {};
    foreach my $name (@modNames) {
        my $mod = $global->modInstance($name);
        my $wnames = $mod->widgets();
        for my $wname (keys (%{$wnames})) {
            my $fullname = "$name:$wname";
            next if exists $widgetsToHide->{$fullname};
            $widgets->{$fullname} = $wnames->{$wname};
        }
    }

    # put the widgets in the dashboards according to the last configuration
    my @dashboards;
    for my $i (1 .. $NUM_DASHBOARDS) {
        my @dashboard;
        for my $wname (@{$sysinfo->getDashboard("dashboard$i")}) {
            if (delete $widgets->{$wname}) {
                my ($module, $name) = split (/:/, $wname);

                my $mod = EBox::Global->modInstance($module);
                next unless defined ($mod);

                my $widget = $mod->widget($name);
                next unless defined ($widget);

                push (@dashboard, $widget);
            }
        }
        $dashboards[$i - 1] = \@dashboard;
    }

    my @orderedWidgets =
        sort { $widgets->{$a}->{order} <=> $widgets->{$b}->{order} }
        keys %{$widgets};

    # put the remaining widgets in the dashboards trying to balance them
    foreach my $wname (@orderedWidgets) {
        next if $sysinfo->isWidgetKnown($wname);

        $sysinfo->addKnownWidget($wname);
        my $winfo = delete $widgets->{$wname};
        next unless (defined ($winfo) and $winfo->{default});

        my ($module, $name) = split (/:/, $wname);

        my $mod = EBox::Global->modInstance($module);
        next unless defined ($mod);

        my $widget = $mod->widget($name);
        next unless defined ($widget);

        # Find the dashboard with less items and add the widget to it
        my $minValue = INT_MAX;
        my $minIndex = 0;
        for my $i (1 .. $NUM_DASHBOARDS) {
            my $size_i = sum(map { $_->{size} } @{$dashboards[$i - 1]});
            if ($size_i < $minValue) {
                $minValue = $size_i;
                $minIndex = $i - 1;
            }
        }
        push (@{$dashboards[$minIndex]}, $widget);
    }

    my @params;
    for my $i (1 .. $NUM_DASHBOARDS) {
        #save the current state
        my @dash_widgets = map { $_->{'module'} . ":" . $_->{'name'} } @{$dashboards[$i-1]};
        $sysinfo->setDashboard("dashboard$i", \@dash_widgets);

        push(@params, "dashboard$i" => \@{$dashboards[$i-1]});
    }
    push(@params, 'toggled' => $sysinfo->toggledElements());

    push(@params, 'brokenPackages' => $global->brokenPackages());
    if (EBox::Global->modExists('software')) {
        push(@params, 'softwareInstalled' => 1);
    }

    return \@params;
}

1;
