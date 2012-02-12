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

package EBox::SysInfo;

use strict;
use warnings;

use base qw(EBox::GConfModule EBox::Report::DiskUsageProvider
            EBox::Model::ModelProvider);

use HTML::Mason;
use HTML::Entities;
use Sys::Hostname;
use Sys::CpuLoad;
use File::Slurp qw(read_file);
use Filesys::Df;
use List::Util qw(sum);
use Error qw(:try);

use EBox::Config;
use EBox::Gettext;
use EBox::Global;
use EBox::Dashboard::Widget;
use EBox::Dashboard::Section;
use EBox::Dashboard::List;
use EBox::Dashboard::Value;
use EBox::Dashboard::HTML;
use EBox::Menu::Item;
use EBox::Menu::Folder;
use EBox::Report::DiskUsage;
use EBox::Report::RAID;
use EBox::Util::Version;
use EBox::Util::Software;

use constant LATEST_VERSION => '/var/lib/zentyal/latestversion';

sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'sysinfo',
                                      printableName => __n('System Information'),
                                      @_);
    bless($self, $class);
    return $self;
}

# Method: initialSetup
#
# Overrides:
#   EBox::Module::Base::initialSetup
#
sub initialSetup
{
    my ($self, $version) = @_;

    # Import timezone only if installing the first time
    unless ($version) {
        $self->importTimezone();
    }
}

sub _facilitiesForDiskUsage
{
    my ($self, @params) = @_;
    return EBox::Backup->_facilitiesForDiskUsage(@params);
}

sub modulesWidget
{
    my ($self, $widget) = @_;
    my $section = new EBox::Dashboard::Section('status');
    $widget->add($section);

    my $global = EBox::Global->getInstance();
    my $typeClass = 'EBox::Module::Service';
    my %moduleStatus;
    my $numModules = 0;
    for my $class (@{$global->modInstancesOfType($typeClass)}) {
        $class->addModuleStatus($section);
        $numModules++;
    }
    $widget->{size} = $numModules * 0.15;
}

sub generalWidget
{
    my ($self, $widget) = @_;
    my $section = new EBox::Dashboard::Section('info');
    $widget->add($section);
    my $time_command = "LC_TIME=" . EBox::locale() . " /bin/date";
    my $time = `$time_command`;

    my $version = $self->version();

    my $qaUpdates = 0;
    my $url = 'http://update.zentyal.org/updates';
    if (EBox::Global->modExists('remoteservices')) {
        my $rs = EBox::Global->modInstance('remoteservices');
        $qaUpdates = $rs->subscriptionLevel() > 0;
    }

    unless (EBox::Config::boolean('widget_ignore_updates')) {
        my $lastVersion;
        open (my $fh, LATEST_VERSION);
        read ($fh, $lastVersion, 16);
        chomp($lastVersion);
        close ($fh);

        if (EBox::Util::Version::compare($lastVersion, $version) == 1) {
            unless ($qaUpdates) {
                my $available = __('available');
                $version .=
                    " (<a target='_blank' href='$url'>$lastVersion $available</a>)";
            }
        }
    }

    my $updatesStr  = __('No updates');
    my $updatesType = 'good';
    if ($qaUpdates) {
        my $msg = $self->_secureMsg();
        $updatesStr = qq{<a title="$msg">$updatesStr</a>};
    } else {
        my $onlyComp = 0;
        # [ updates, sec_updates]
        my $updates = EBox::Util::Software::upgradablePkgsNum();
        if ( $updates->[1] > 0 ) {
            $updatesType = 'error';
            $updatesStr = __x('{n} security updates', n => $updates->[1]);
        } elsif ( $updates->[0] > 0 ) {
            $updatesType = 'warning';
            $updatesStr = __x('{n} system updates', n => $updates->[0]);
            my $pkgsToUpgrade = EBox::Util::Software::upgradablePkgs();
            my $nonCompNum = grep { $_ !~ /^zentyal-/ } @{$pkgsToUpgrade};
            if ( $nonCompNum == 0 ) {
                # Only components, then show components
                $updatesStr = __x('{n} component updates', n => $updates->[0]);
                $onlyComp = 1;
            }
        }
        my $href = $url;
        if (EBox::Global->modExists('software')) {
            if ( $onlyComp ) {
                $href = '/Software/EBox#update';
            } else {
                $href = '/Software/Updates';
            }
        }
        unless ($ignore) {
            my $msg = $self->_commercialMsg();
            $updatesStr = qq{<a href="$href" title="$msg">$updatesStr</a>};
        }
    }

    my $uptime_output=`uptime`;
    my ($uptime, $users, $la1, $la2, $la3) = $uptime_output =~ /.*up  *(.*),  (.*)users?,  load average: (.*), (.*), (.*)/;

    $section->add(new EBox::Dashboard::Value(__('Time'), $time));
    $section->add(new EBox::Dashboard::Value(__('Hostname'), hostname));
    $section->add(new EBox::Dashboard::Value(__('Core version'), $version));
    $section->add(new EBox::Dashboard::Value(__('Software'), $updatesStr, $updatesType));
    $section->add(new EBox::Dashboard::Value(
        __("System load"), join(', ', Sys::CpuLoad::load)));
    $section->add(new EBox::Dashboard::Value(__("Uptime"), $uptime));
    $section->add(new EBox::Dashboard::Value(__("Users"), $users));
}

sub processesWidget
{
    my ($self, $widget) = @_;
    my $section = new EBox::Dashboard::Section('foo');
    $widget->add($section);
    my $titles = ['PID','Name'];
    my $ids = [];
    my @processes = `ps ax | grep -v PID| awk '{ print \$1, \$5 }'`;
    my $rows = {};
    for my $p (@processes) {
        chomp($p);
        my ($pid, $name) = split(' ', $p);
        encode_entities($name);
        my $foopid = 'a' . $pid;
        push(@{$ids}, $foopid);
        $rows->{$foopid} = [$pid,$name];
    }
    $section->add(new EBox::Dashboard::List(undef, $titles, $ids, $rows));
}

sub linksWidget
{
    my ($self, $widget) = @_;
    my $section = new EBox::Dashboard::Section('links');
    $widget->add($section);

    # Write the links widget using mason
    my $html;
    my $interp = new HTML::Mason::Interp(comp_root  => EBox::Config::templates(),
                                         out_method => sub { $html .= $_[0] });
    my $component = $interp->make_component(
        comp_file => EBox::Config::templates() . 'links-widget.mas'
       );
    $interp->exec($component, ());

    $section->add(new EBox::Dashboard::HTML($html));
}

#
# Method: widgets
#
#   Overriden method that returns the widgets offered by this module
#
# Overrides:
#
#       <EBox::Module::widgets>
#
sub widgets
{
    my $widgets = {
        'modules' => {
            'title' => __("Module Status"),
            'widget' => \&modulesWidget,
            'order' => 6,
            'default' => 1
        },
        'general' => {
            'title' => __("General Information"),
            'widget' => \&generalWidget,
            'order' => 1,
            'default' => 1
        },
        'processes' => {
            'title' => __("Process List"),
            'widget' => \&processesWidget
        },
    };

    unless (EBox::Config::boolean('disable_links_widget')) {
        $widgets->{'links'} = {
            'title' => __("Resources & Services"),
            'widget' => \&linksWidget,
            'order' => 2,
            'default' => 1
        };
    }

    return $widgets;
}

# Method: modelClasses
#
#       Override <EBox::Model::ModelProvider::modelClasses>
#
sub modelClasses
{
    return [
        'EBox::SysInfo::Model::Halt',
    ];
}

sub addKnownWidget()
{
    my ($self,$wname) = @_;
    my $list = $self->st_get_list("known/widgets");
    push(@{$list},$wname);
    $self->st_set_list("known/widgets", "string", $list);
}

sub isWidgetKnown()
{
    my ($self, $wname) = @_;
    my $list = $self->st_get_list("known/widgets");
    my @results = grep(/^$wname$/,@{$list});
    if(@results) {
        return 1;
    } else {
        return undef;
    }
}

sub getDashboard()
{
    my ($self,$dashboard) = @_;
    return $self->st_get_list("$dashboard/widgets");
}

sub setDashboard()
{
    my ($self,$dashboard,$widgets) = @_;
    $self->st_set_list("$dashboard/widgets", "string", $widgets);
}

sub toggleElement()
{
    my ($self,$element) = @_;
    my $toggled = $self->st_get_bool("toggled/$element");
    $self->st_set_bool("toggled/$element",!$toggled);
}

sub toggledElements()
{
    my ($self) = @_;
    return $self->st_hash_from_dir("toggled");
}

# Method: setNewTimeZone
#
#   Sets the system's time zone
#
# Parameters:
#
#   continent
#   country
#
sub setNewTimeZone
{
    my ($self, $continent, $country) = @_;

    $self->set_string('continent', $continent);
    $self->set_string('country', $country);
    EBox::Sudo::root("echo $continent/$country > /etc/timezone");
    EBox::Sudo::root("cp -f /usr/share/zoneinfo/$continent/$country /etc/localtime");
}

# Method: menu
#
#   Overriden method that returns the core menu entries:
#
#   - Summary
#   - Save/Cancel
#   - Logout
#   - SysInfo/General
#   - SysInfo/Backup
#   - SysInfo/Halt
#
sub menu
{
    my ($self, $root) = @_;

    $root->add(new EBox::Menu::Item('url' => 'Dashboard/Index',
                    'text' => __('Dashboard'),
                    'separator' => 'Core',
                    'order' => 10));

    $root->add(new EBox::Menu::Item('url' => 'ServiceModule/StatusView',
                    'text' => __('Module Status'),
                    'separator' => 'Core',
                    'order' => 20));


    my $system = new EBox::Menu::Folder('name' => 'SysInfo',
                        'text' => __('System'),
                        'order' => 30);

    $system->add(new EBox::Menu::Item('url' => 'SysInfo/General',
                      'order' => 10,
                      'text' => __('General')));

    $system->add(new EBox::Menu::Item('url' => 'SysInfo/Backup',
                      'order' => 50,
                      'text' => __('Import/Export Configuration')));

    $system->add(new EBox::Menu::Item('url' => 'SysInfo/View/Halt',
                      'order' => 60,
                      'text' => __('Halt/Reboot')));

    $root->add($system);

    my $maint = new EBox::Menu::Folder('name' => 'Maintenance',
                                        'text' => __('Maintenance'),
                                        'separator' => 'Core',
                                        'order' => 70);

    $maint->add(new EBox::Menu::Item('url' => 'Report/DiskUsage',
                                     'order' => 40,
                                     'text' => __('Disk Usage')));

    $maint->add(new EBox::Menu::Item('url' => 'Report/RAID',
                                     'order' => 50,
                                     'text' => __('RAID')));
    $root->add($maint);
}

sub logReportInfo
{
    my ($self) = @_;

    my @data;

    my $fileSysS = EBox::Report::DiskUsage::partitionsFileSystems();
    foreach my $fileSys (keys %{$fileSysS}) {
        my $entry = {};
        $entry->{'table'} = 'sysinfo_disk_usage';
        $entry->{'values'} = {};
        my $mount = $fileSysS->{$fileSys}->{mountPoint};
        $entry->{'values'}->{'mountpoint'} = $mount;
        my $info = df($mount, 1);
        $entry->{'values'}->{'used'} = $info->{'used'};
        $entry->{'values'}->{'free'} = $info->{'bavail'};
        push(@data, $entry)
    }

    # Add the total disk usage column
    my $totalEntry = {};
    $totalEntry->{'table'} = 'sysinfo_disk_usage';
    $totalEntry->{'values'} = {};
    $totalEntry->{'values'}->{'mountpoint'} = 'total';
    $totalEntry->{'values'}->{'used'} = sum(map { $_->{'values'}->{'used'} } @data);
    $totalEntry->{'values'}->{'free'} = sum(map { $_->{'values'}->{'free'} } @data);
    unshift(@data, $totalEntry);

    return \@data;
}

sub consolidateReportInfoQueries
{
    return [
        {
            'target_table' => 'sysinfo_disk_usage_report',
            'query' => {
                'select' => 'mountpoint, used, free',
                'from' => 'sysinfo_disk_usage',
                'key' => 'mountpoint'
            }
        }
    ];
}

# Method: report
#
# Overrides:
#   <EBox::Module::Base::report>
sub report
{
    my ($self, $beg, $end, $options) = @_;

    my $report = {};

    $report->{'disk_usage'} = $self->runMonthlyQuery($beg, $end, {
        'select' => 'mountpoint, used, free',
        'from' => 'sysinfo_disk_usage_report',
    }, { 'key' => 'mountpoint' });

    if ( keys %{$report->{'disk_usage'}} == 2 ) {
        # Only total + /, so we return only total
        delete($report->{'disk_usage'}->{'/'});
    }

    return $report;
}

# Method: setNewDate
#
#   Sets the system date
#
# Parameters:
#
#   day
#   month
#   year
#   hour
#   minute
#   second
#
sub setNewDate
{
    my ($self, $day, $month, $year, $hour, $minute, $second) = @_;

    my $newdate = "$year-$month-$day $hour:$minute:$second";
    my $command = "/bin/date --set \"$newdate\"";
    EBox::Sudo::root($command);

    my $global = EBox::Global->getInstance(1);
    $self->_restartAllServices;
}

sub _restartAllServices
{
    my ($self) = @_;

    my $global = EBox::Global->getInstance();
    my $failed = '';
    EBox::info('Restarting all modules');
    foreach my $mod (@{$global->modInstancesOfType('EBox::Module::Service')}) {
        my $name = $mod->name();
        next if ($name eq 'network') or
                ($name eq 'firewall');
        try {
            $mod->restartService();
        } catch EBox::Exceptions::Internal with {
            $failed .= "$name ";
        };
    }
    if ($failed ne "") {
        throw EBox::Exceptions::Internal("The following modules " .
            "failed while being restarted, their state is " .
            "unknown: $failed");
    }

    EBox::info('Restarting system logs');
    try {
        EBox::Sudo::root('service rsyslog restart',
                         'service cron restart');
    } catch EBox::Exceptions::Internal with {
    };
}

# Method: importTimezone
#
#   Reads timezone from /etc/timezone and saves it into the module config
#
sub importTimezone
{
    my ($self) = @_;

    my $timezone = `cat /etc/timezone`;
    chomp($timezone);

    my ($continent, $country) = split ('/', $timezone);

    $self->set_string('continent', $continent);
    $self->set_string('country', $country);
}

# Return commercial message for QA updates
sub _commercialMsg
{
    return __s('Warning: The updates are community based and there is no guarantee that your '
               . 'server will work properly after applying them. Quality Assured Updates are '
               . 'only included in commercial subscriptions and they guarantee that all the '
               . 'upgrades, bugfixes and security updates '
               . "are extensively tested by the Zentyal Development Team and you won't "
               . 'be introducing any regressions on your already working system. '
               . 'Purchase a Professional or Enterprise Server Subscription to gain access '
               . 'to QA updates.');

}

sub _secureMsg
{
    return __s('As your server has a commercial server subscription, these updates are '
               . 'quality assured and automatically applied to your system.');
}

1;
