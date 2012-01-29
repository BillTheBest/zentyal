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

package EBox::Virt;

use strict;
use warnings;

use base qw(EBox::Module::Service
            EBox::Model::ModelProvider
            EBox::Model::CompositeProvider
            EBox::Report::DiskUsageProvider);
use EBox;
use EBox::Config;
use EBox::Gettext;
use EBox::Service;
use EBox::Menu::Item;
use EBox::Menu::Folder;
use EBox::Sudo;
use EBox::Util::Version;
use EBox::Dashboard::Section;
use EBox::Virt::Dashboard::VMStatus;
use EBox::Virt::Model::NetworkSettings;
use EBox::Virt::Model::DeviceSettings;
use Error qw(:try);
use String::ShellQuote;
use File::Slurp;

use constant DEFAULT_VNC_PORT => 5900;
use constant LIBVIRT_BIN => '/usr/bin/virsh';
use constant DEFAULT_VIRT_USER => 'ebox';
use constant VNC_PASSWD_FILE => '/var/lib/zentyal/conf/vnc-passwd';

my $UPSTART_PATH = '/etc/init/';
my $WWW_PATH = EBox::Config::www();


sub _create
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'virt',
                                      printableName => __('Virtual Machines'),
                                      @_);
    bless($self, $class);

    # Autodetect which virtualization suite is installed,
    # libvirt has priority if both are installed
    if (-x LIBVIRT_BIN) {
        eval 'use EBox::Virt::Libvirt';
        $self->{backend} = new EBox::Virt::Libvirt();
    } else {
        eval 'use EBox::Virt::VBox';
        $self->{backend} = new EBox::Virt::VBox();
    }

    my $user = EBox::Config::configkey('vm_user');
    unless ($user) {
        $user = DEFAULT_VIRT_USER;
    }
    $self->{vmUser} = $user;

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

    if ($version) {
        if (EBox::Util::Version::compare($version, '2.2.3') < 0) {
            # Only when upgrading from <= 2.2.2
            $self->_importCurrentVNCPorts();
        }
    } else {
        # Create default service only if installing the first time
        my $services = EBox::Global->modInstance('services');

        my $serviceName = 'vnc-virt';
        unless ($services->serviceExists(name => $serviceName)) {
            $services->addMultipleService(
                'name' => $serviceName,
                'description' => __('VNC connections for VMs'),
                'internal' => 1,
                'readOnly' => 1,
                'services' => [
                                { protocol => 'tcp',
                                  sourcePort => 'any',
                                  destinationPort => DEFAULT_VNC_PORT },
                                { protocol => 'tcp',
                                  sourcePort => 'any',
                                  destinationPort => DEFAULT_VNC_PORT + 1000 }
                              ],
            );
        }

        my $firewall = EBox::Global->modInstance('firewall');
        $firewall->setExternalService($serviceName, 'deny');
        $firewall->setInternalService($serviceName, 'accept');

        $firewall->saveConfigRecursive();
    }
}

sub modelClasses
{
    return [
        'EBox::Virt::Model::VirtualMachines',
        'EBox::Virt::Model::SystemSettings',
        'EBox::Virt::Model::NetworkSettings',
        'EBox::Virt::Model::DeviceSettings',
        'EBox::Virt::Model::DeletedDisks',
    ];
}

sub compositeClasses
{
    return [ 'EBox::Virt::Composite::VMSettings' ];
}

# Method: menu
#
#       Overrides EBox::Module method.
#
sub menu
{
    my ($self, $root) = @_;

    $root->add(new EBox::Menu::Item('url' => 'Virt/View/VirtualMachines',
                                    'text' => $self->printableName(),
                                    'separator' => 'Infrastructure',
                                    'order' => 445));
}

sub _preSetConf
{
    my ($self) = @_;

    my $disabled = not $self->isEnabled();

    # The try is needed because this is also executed before
    # the upstart files for the machines are created, if
    # we made this code more intelligent probably it won't
    # be needed.
    try {
        my $vms = $self->model('VirtualMachines');
        foreach my $vmId (@{$vms->ids()}) {
            if ($disabled or $self->needsRewrite($vmId)) {
                my $vm = $vms->row($vmId);
                my $name = $vm->valueByName('name');
                if ($self->vmRunning($name)) {
                    $self->stopVM($name);
                }
            }
        }

        $self->_stopService();
    } otherwise {};
}

sub _setConf
{
    my ($self) = @_;

    my $backend = $self->{backend};

    # Clean all upstart and novnc files, the current ones will be regenerated
    EBox::Sudo::silentRoot("rm -rf $UPSTART_PATH/zentyal-virt.*.conf",
                           "rm -rf $WWW_PATH/vncviewer-*.html");

    my %currentVMs;

    my %vncPasswords;
    # Syntax of the vnc passwords file:
    # machinename:password
    my @lines;
    if (-f VNC_PASSWD_FILE) {
        @lines = read_file(VNC_PASSWD_FILE);
        chomp(@lines);
        foreach my $line (@lines) {
            my ($machine, $pass) = split(/:/, $line);
            next unless ($machine and $pass);
            $vncPasswords{$machine} = $pass;
        }
    }

    $backend->initInternalNetworks();

    my $updateFwService = 0;

    my $vms = $self->model('VirtualMachines');
    foreach my $vmId (@{$vms->ids()}) {
        my $vm = $vms->row($vmId);
        my $name = $vm->valueByName('name');
        $currentVMs{$name} = 1;

        my $vncport = $vm->valueByName('vncport');
        unless ($vncport) {
            $vncport = $self->firstFreeVNCPort();
            $vm->elementByName('vncport')->setValue($vncport);
            $vm->store();
            $updateFwService = 1;
        }

        my $rewrite = 1;
        if ($self->usingVBox()) {
            $rewrite = $self->needsRewrite($vmId);
        }

        my $settings = $vm->subModel('settings');
        my $system = $settings->componentByName('SystemSettings')->row();

        unless (exists $vncPasswords{$name}) {
            $vncPasswords{$name} = _randPassVNC();
        }

        if ($rewrite) {
            $self->_createMachine($name, $system);
            $self->_setNetworkConf($name, $settings);
            $self->_setDevicesConf($name, $settings);
        }
        $self->_writeMachineConf($name, $vncport, $vncPasswords{$name});
        $backend->writeConf($name);
    }
    $backend->createInternalNetworks();

    if ($updateFwService) {
        $self->updateFirewallService();
    }

    # Delete non-referenced VMs
    my $existingVMs = $backend->listVMs();
    my @toDelete = grep { not exists $currentVMs{$_} } @{$existingVMs};
    foreach my $machine (@toDelete) {
        $backend->deleteVM($machine);
        delete $vncPasswords{$machine};
    }

    # Update vnc passwords file
    @lines = map { "$_:$vncPasswords{$_}\n" } keys %vncPasswords;
    write_file(VNC_PASSWD_FILE, @lines);
    chmod (0600, VNC_PASSWD_FILE);
}

sub updateFirewallService
{
    my ($self) = @_;

    my @vncservices;

    my $vms = $self->model('VirtualMachines');
    foreach my $vmId (@{$vms->ids()}) {
        my $vm = $vms->row($vmId);
        my $vncport = $vm->valueByName('vncport');
        foreach my $vncport ($vncport, $vncport + 1000) {
            push (@vncservices, { protocol => 'tcp',
                                  sourcePort => 'any',
                                  destinationPort => $vncport });
        }
    }

    my $servMod = EBox::Global->modInstance('services');
    $servMod->setMultipleService(name => 'vnc-virt',
                                 description => __('VNC connections for VMs'),
                                 allowEmpty => 1,
                                 internal => 1,
                                 services => \@vncservices);
}

sub machineDaemon
{
    my ($self, $name) = @_;

    return "zentyal-virt.$name";
}

sub vncDaemon
{
    my ($self, $name) = @_;

    return "zentyal-virt.vnc.$name";
}

sub vmRunning
{
    my ($self, $name) = @_;

    return $self->{backend}->vmRunning($name);
}

sub vmPaused
{
    my ($self, $name) = @_;

    return $self->{backend}->vmPaused($name);
}

sub diskFile
{
    my ($self, $vmName, $diskName) = @_;

    return $self->{backend}->diskFile($diskName, $vmName);
}

sub startVM
{
    my ($self, $name) = @_;

    $self->_manageVM($name, 'start');
}

sub stopVM
{
    my ($self, $name) = @_;

    $self->_manageVM($name, 'stop');
}

sub _manageVM
{
    my ($self, $name, $action) = @_;

    my $vncDaemon = $self->vncDaemon($name);
    my $currentStatus = EBox::Service::running($vncDaemon) ? 'start' : 'stop';
    if ($action ne $currentStatus) {
        EBox::Service::manage($vncDaemon, $action);
    }

    my $manageScript = $self->manageScript($name);
    $manageScript = shell_quote($manageScript);
    EBox::Sudo::root("$manageScript $action");
}

sub pauseVM
{
    my ($self, $name) = @_;

    return $self->{backend}->pauseVM($name);
}

sub resumeVM
{
    my ($self, $name) = @_;

    return $self->{backend}->resumeVM($name);
}

sub systemTypes
{
    my ($self) = @_;

    return $self->{backend}->systemTypes();
}

sub ifaces
{
    my ($self) = @_;

    return $self->{backend}->ifaces();
}

sub manageScript
{
    my ($self, $name) = @_;

    return $self->{backend}->manageScript($name);
}

my $needRewriteVMs;

sub needsRewrite
{
    my ($self, $vmId) = @_;

    return $needRewriteVMs->{$vmId};
}

sub _saveConfig
{
    my ($self) = @_;

    $needRewriteVMs = {};
    my $vms = $self->model('VirtualMachines');
    foreach my $vmId (@{$vms->ids()}) {
        if ($self->usingVBox()) {
            my $vm = $vms->row($vmId);
            my $settings = $vm->subModel('settings');
            my $system = $settings->componentByName('SystemSettings')->row();

            if ($system->valueByName('manageonly')) {
                $needRewriteVMs->{$vmId} = 0;
                next;
            }
        }
        $needRewriteVMs->{$vmId} = $vms->vmChanged($vmId);
    }

    $self->SUPER::_saveConfig();
}

sub _daemons
{
    my ($self) = @_;

    my @daemons;

    # Add virtualizer-specific daemons to manage, if any
    # Currently this is only the case of libvirt-bin
    push (@daemons, @{$self->{backend}->daemons()});

    return \@daemons;
}

sub _enforceServiceState
{
    my ($self) = @_;

    return unless $self->isEnabled();

    $self->_startService();

    $self->{backend}->createInternalNetworks();

    # Start machines marked as autostart
    my $vms = $self->model('VirtualMachines');
    foreach my $vmId (@{$vms->findAll('autostart' => 1)}) {
        my $vm = $vms->row($vmId);
        my $name = $vm->valueByName('name');
        unless ($self->vmRunning($name)) {
            $self->startVM($name);
        }
    }
}

sub _createMachine
{
    my ($self, $name, $system) = @_;

    my $backend = $self->{backend};
    my $memory = $system->valueByName('memory');
    my $os = $system->valueByName('os');

    $backend->createVM(name => $name);

    $backend->setOS($name, $os);
    $backend->setMemory($name, $memory);
}

sub _setNetworkConf
{
    my ($self, $name, $settings) = @_;

    my $backend = $self->{backend};
    my $ifaceNumber = 1;

    my $ifaces = $settings->componentByName('NetworkSettings');
    foreach my $ifaceId (@{$ifaces->ids()}) {
        my $iface = $ifaces->row($ifaceId);
        my $enabled = $iface->valueByName('enabled');

        my $type = 'none';
        my $arg = undef;
        if ($enabled) {
            $type = $iface->valueByName('type');
            if ($type eq 'bridged') {
                $arg = $iface->valueByName('iface');
            } elsif ($type eq 'internal') {
                $arg = $iface->valueByName('name');
            }
        }
        my $mac;
        if (EBox::Config::configkey('custom_mac_addresses') eq 'yes') {
            if ($iface->elementExists('mac')) {
                $mac = $iface->valueByName('mac');
            }
        }

        $backend->setIface(name => $name, iface => $ifaceNumber++,
                           type => $type, arg => $arg, mac => $mac);
    }

    # Unset the rest of the interfaces to prevent they stay from an old conf
    while ($ifaceNumber <= EBox::Virt::Model::NetworkSettings::MAX_IFACES()) {
        $backend->setIface(name => $name, iface => $ifaceNumber++,
                           type => 'none');
    }
}

sub _setDevicesConf
{
    my ($self, $name, $settings) = @_;

    my $backend = $self->{backend};

    # Clean all devices first (only needed for vbox)
    $backend->initDeviceNumbers();
    for (1 .. $backend->attachedDevices($name, 'cd')) {
        $backend->attachDevice(name => $name, type => 'cd', file => 'none');
    }
    for (1 .. $backend->attachedDevices($name, 'hd')) {
        $backend->attachDevice(name => $name, type => 'hd', file => 'none');
    }
    $self->_cleanupDeletedDisks();

    $backend->initDeviceNumbers();
    my $devices = $settings->componentByName('DeviceSettings');
    foreach my $deviceId (@{$devices->enabledRows()}) {
        my $device = $devices->row($deviceId);
        my $file;
        my $type = $device->valueByName('type');
        my $disk_action;
        if ($type eq 'hd') {
            $disk_action = $device->valueByName('disk_action');
        }

        if (defined ($disk_action) and ($disk_action eq 'create')) {
            my $disk_name = $device->valueByName('name');
            my $size = $device->valueByName('size');
            $file = $backend->diskFile($disk_name, $name);
            unless (-f $file) {
                $backend->createDisk(file => $file, size => $size);
            }
        } else {
            $file = $device->valueByName('path');
        }

        $backend->attachDevice(name => $name, type => $type, file => $file);
    }
}

sub _writeMachineConf
{
    my ($self, $name, $vncport, $vncpass) = @_;

    my $backend = $self->{backend};

    my $start = $backend->startVMCommand(name => $name, port => $vncport, pass => $vncpass);
    my $stop = $backend->shutdownVMCommand($name);
    my $listenport = $vncport + 1000;

    EBox::Module::Base::writeConfFileNoCheck(
            "$UPSTART_PATH/" . $self->machineDaemon($name) . '.conf',
            '/virt/upstart.mas',
            [ startCmd => $start, stopCmd => $stop, user => $self->{vmUser} ],
            { uid => 0, gid => 0, mode => '0644' }
    );

    EBox::Module::Base::writeConfFileNoCheck(
            "$UPSTART_PATH/" . $self->vncDaemon($name) . '.conf',
            '/virt/vncproxy.mas',
            [ vncport => $vncport, listenport => $listenport ],
            { uid => 0, gid => 0, mode => '0644' }
    );

    my $width = $self->consoleWidth();
    my $height = $self->consoleHeight();
    my $gid = getgrnam('ebox'); # The Zentyal apache needs to read it
    EBox::Module::Base::writeConfFileNoCheck(
            EBox::Config::www() . "/vncviewer-$name.html",
            '/virt/vncviewer.html.mas',
            [ port => $listenport, password => $vncpass, width => $width, height => $height ],
            { uid => 0, gid => $gid, mode => '0640' }
    );
}

sub _cleanupDeletedDisks
{
    my ($self) = @_;

    my $deletedDisks = $self->model('DeletedDisks');

    foreach my $id (@{$deletedDisks->ids()}) {
        my $row = $deletedDisks->row($id);
        my $file = $row->valueByName('file');
        EBox::Sudo::root("rm -f $file");
    }

    $deletedDisks->removeAll(1);

    # mark as saved to avoid red button
    EBox::Global->getInstance()->modRestarted('virt');
}

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
    return {
        'machines' => {
            'title' => __('Virtual Machines'),
            'widget' => \&_vmWidget,
            'order' => 12,
            'default' => 1
        },
    };
}

sub firstVNCPort
{
    my ($self) = @_;

    my $vncport = EBox::Config::configkey('first_vnc_port');
    return $vncport ? $vncport : DEFAULT_VNC_PORT;
}

sub _importCurrentVNCPorts
{
    my ($self) = @_;

    # We only can know the currently used ports when using libvirt
    return if $self->usingVBox();

    my $base = $self->firstVNCPort();

    my $updateFwService = 0;

    my @unassigned;
    my $vms = $self->model('VirtualMachines');
    foreach my $vmId (@{$vms->ids()}) {
        my $vm = $vms->row($vmId);
        my $name = $vm->valueByName('name');
        my $vncport = $self->{backend}->vncdisplay($name);
        unless (defined ($vncport)) {
            push (@unassigned, $vm);
            next;
        }
        $vm->elementByName('vncport')->setValue($base + $vncport);
        $vm->store();
        $updateFwService = 1;
    }
    foreach my $vm (@unassigned) {
        $vm->elementByName('vncport')->setValue($self->firstFreeVNCPort());
        $vm->store();
        $updateFwService = 1;
    }

    if ($updateFwService) {
        $self->updateFirewallService();
        my $firewall = EBox::Global->modInstance('firewall');
        $firewall->saveConfigRecursive();
    }

}

sub firstFreeVNCPort
{
    my ($self) = @_;

    my $maxPortUsed = 0;

    my $vms = $self->model('VirtualMachines');
    foreach my $vmId (@{$vms->ids()}) {
        my $vm = $vms->row($vmId);
        my $vncport = $vm->valueByName('vncport');
        if ($vncport and ($vncport > $maxPortUsed)) {
            $maxPortUsed = $vncport;
        }
    }

    return $maxPortUsed ? $maxPortUsed + 1 : $self->firstVNCPort();
}

sub consoleWidth
{
    my ($self) = @_;

    my $vncport = EBox::Config::configkey('view_console_width');
    return $vncport ? $vncport : 800;
}

sub consoleHeight
{
    my ($self) = @_;

    my $vncport = EBox::Config::configkey('view_console_height');
    return $vncport ? $vncport : 600;
}

sub usingVBox
{
    my ($self) = @_;

    return $self->{backend}->isa('EBox::Virt::VBox');
}

sub backupDomains
{
    my $name = 'machines';
    my %attrs  = (
                  printableName => __('Virtual Machines'),
                  description   => __(q{Disk images of the virtual machines}),
                 );

    return ($name, \%attrs);
}

sub backupDomainsFileSelection
{
    my ($self, %enabled) = @_;

    return {} unless $enabled{machines};

    my @files;
    my $vms = $self->model('VirtualMachines');
    foreach my $vmId (@{$vms->ids()}) {
        my $vm = $vms->row($vmId);
        my $name = $vm->valueByName('name');
        my $settings = $vm->subModel('settings');
        my $devices = $settings->componentByName('DeviceSettings');
        foreach my $deviceId (@{$devices->enabledRows()}) {
            my $device = $devices->row($deviceId);
            my $file = $device->valueByName('path');
            unless ($file) {
                my $disk_name = $device->valueByName('name');
                next unless ($disk_name);
                $file = $self->{backend}->diskFile($disk_name, $name);
            }
            push (@files, $file);
        }
    }

    return { includes => \@files };
}

sub _facilitiesForDiskUsage
{
    my ($self) = @_;

    my $name  = __('Virtual Machines');
    my $vmsPath = $self->{backend}->vmsPath();

    return { $name => [ $vmsPath ] };
}

sub _vmWidget
{
    my ($self, $widget) = @_;

    my $backend = $self->{backend};

    my $section = new EBox::Dashboard::Section('status');
    $widget->add($section);

    my $vms = $self->model('VirtualMachines');
    foreach my $vmId (@{$vms->ids()}) {
        my $vm = $vms->row($vmId);
        my $name = $vm->valueByName('name');
        my $running = $backend->vmRunning($name);

        $section->add(new EBox::Virt::Dashboard::VMStatus(
                            id => $vmId,
                            model => $vms,
                            name => $name,
                            running => $running
                      )
        );
    }
}

sub _randPassVNC
{
    return join ('', map +(0..9,'a'..'z','A'..'Z')[rand(10+26*2)], 1..8);
}

1;
