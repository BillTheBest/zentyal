# Copyright (C) 2008-2011 eBox Technologies S.L.
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

package EBox::GlobalImpl;

use strict;
use warnings;

use base qw(EBox::GConfModule Apache::Singleton::Process);

use EBox;
use EBox::Exceptions::Command;
use EBox::Exceptions::InvalidData;
use EBox::Exceptions::DataNotFound;
use EBox::Exceptions::Internal;
use EBox::Exceptions::MissingArgument;
use EBox::Exceptions::DataExists;
use Error qw(:try);
use EBox::Config;
use EBox::Gettext;
use EBox::ProgressIndicator;
use EBox::ProgressIndicator::Dummy;
use EBox::Sudo;
use EBox::Validate qw( :all );
use File::Basename;
use File::Glob;
use YAML::XS;
use Log::Log4perl;
use POSIX qw(setuid setgid setlocale LC_ALL);
use Perl6::Junction qw(any all);
use EBox::Util::GPG;

use Digest::MD5;
use AptPkg::Cache;
use File::stat;

# Constants
use constant {
    PRESAVE_SUBDIR  => EBox::Config::etc() . 'pre-save',
    POSTSAVE_SUBDIR => EBox::Config::etc() . 'post-save',
    TIMESTAMP_KEY   => 'saved_timestamp',
    FIRST_FILE => '/var/lib/zentyal/.first',
    DPKG_RUNNING_FILE => '/var/lib/zentyal/dpkg_running',
};

use constant CORE_MODULES => qw(sysinfo apache events global logs audit);

my $lastDpkgStatusMtime = undef;
my $_cache = undef;
my $_brokenPackages = {};
my $_installedPackages = {};

#redefine inherited method to create own constructor
#for Singleton pattern
sub _new_instance
{
    my $class = shift;
    my $self = $class->SUPER::_create(name => 'global',
                                      printableName => 'global',
                                      @_);
    bless($self, $class);
    $self->{'mod_instances_rw'} = {};
    $self->{'mod_instances_ro'} = {};

    # Messages produced during save changes process
    $self->{save_messages} = [];
    return $self;
}

#Method: readModInfo
#
#   Static method which returns the information found in the module's yaml file
#
sub readModInfo # (module)
{
    my ($self, $name) = @_;

    my $yaml;
    try {
        ($yaml) = YAML::XS::LoadFile(EBox::Config::modules() . "$name.yaml");
    } otherwise {
        $yaml = undef;
    };
    return $yaml;
}

#Method: theme
#
#   Returns the information found in custom.theme if exists
#   exists or default.theme if not.
#
sub theme
{
    my ($self) = @_;

    unless (defined $self->{theme}) {
        $self->{theme} = _readTheme();
    }

    return $self->{theme};
}

sub _readTheme
{
    my $path = EBox::Config::share() . 'zentyal/www';
    my $theme = "$path/default.theme";
    my $custom = "$path/custom.theme";
    if (-f $custom) {
        # Check theme's signature
        if (EBox::Util::GPG::checkSignature($custom)) {
            $theme = $custom;
            EBox::info('Using custom default.theme');
        } else {
            EBox::warn('Invalid signature in custom.theme, fallbacking to default.theme');
        }
    }
    my ($yaml) = YAML::XS::LoadFile($theme);
    return $yaml;
}

sub _className
{
    my ($self, $name) = @_;
    my $info = $self->readModInfo($name);
    defined($info) or return undef;
    return $info->{'class'};
}

# Method: modExists
#
#      Check if a module exists
#
# Parameters:
#
#       module -  module's name to check
#
# Returns:
#
#       boolean - True if the module exists, otherwise false
#
sub modExists
{
    my ($self, $name) = @_;

    # is dpkg command running?
    my $DPKG_RUNNING = 0;
    if (-f DPKG_RUNNING_FILE) {
        $DPKG_RUNNING = 1 ;
    }

    unless ($DPKG_RUNNING) {
        if ($ENV{DPKG_RUNNING_VERSION}) {
            EBox::Sudo::command('touch ' . DPKG_RUNNING_FILE);
            $DPKG_RUNNING = 1;
        }
    }

    # Check if module package is properly installed
    #
    # No need to check core modules because if
    # zentyal-core package is not properly installed
    # nothing of this is going to work at all.
    #
    if ($name eq any((CORE_MODULES))) {
        return 1;
    } elsif ($DPKG_RUNNING) {
        return defined($self->_className($name));
    } else {
        return _packageInstalled("zentyal-$name");
    }
}

# Method: modEnabled
#
#      Check if a module exists and it's enabled
#
# Parameters:
#
#       module -  module's name to check
#
# Returns:
#
#       boolean - True if the module is enabled, otherwise false
#
sub modEnabled
{
    my ($self, $ro, $name) = @_;

    unless ($self->modExists($name)) {
        return 0;
    }
    my $mod = $self->modInstance($ro, $name);
    return $mod->isEnabled();
}

# Method: modIsChanged
#
#      Check if the module config has changed
#
#      GlobalImpl module is considered always unchanged
#
# Parameters:
#
#       module -  module's name to check
#
# Returns:
#
#       boolean - True if the module config has changed , otherwise false
#
sub modIsChanged
{
    my ($self, $name) = @_;

    defined($name) or return undef;
    ($name ne 'global') or return undef;

    $self->modExists($name) or return undef;

    my $info = $self->readModInfo($name);
    return $self->get_bool("modules/$name/changed");
}

# Method: modChange
#
#       Set a module as changed
#
#      GlobalImpl cannot be marked as changed and such request will be ignored
#
# Parameters:
#
#       module -  module's name to set
#
sub modChange
{
    my ($self, $ro, $name) = @_;
    defined($name) or return;
    ($name ne 'global') or return;

    return if $self->modIsChanged($name);

    # FIXME: Forbid changing anything if ro == 1
    my $mod = $self->modInstance($ro, $name);
    defined($mod) or throw EBox::Exceptions::Internal("Module $name does not exist");

    $self->set_bool("modules/$name/changed", 1);
}

# Method: modRestarted
#
#       Sets a module as restarted
#
# Parameters:
#
#       module -  module's name to set
#
sub modRestarted
{
    my ($self, $name) = @_;

    defined($name) or return;
    ($name ne 'global') or return;
    $self->modExists($name) or return;

    $self->set_bool("modules/$name/changed", undef);
}

# Method: modNames
#
#       Return an array containing all module names
#
# Returns:
#
#       array ref - each element contains the module's name
#
sub modNames
{
    my ($self) = @_;

    my $log = EBox::logger();
    my @allmods = ();
    foreach (('sysinfo', 'network', 'firewall')) {
        if ($self->modExists($_)) {
            push(@allmods, $_);
        }
    }
    my @files = glob(EBox::Config::modules() . '*.yaml');
    my @mods = map { basename($_) =~ m/(.*)\.yaml/ ; $1 } @files;
    foreach my $mod (@mods) {
        next unless ($self->modExists($mod));
        next if (grep(/^$mod$/, @allmods));
        my $class = $self->_className($mod);
        if(defined($class)) {
            push(@allmods, $mod);
        }
    }
    return \@allmods;
}

# Method: unsaved
#
#       Tell you if there is at least one unsaved module
#
# Returns:
#
#       boolean - indicating if at least a module has unsaved changes
#
sub unsaved
{
    my $self = shift;
    my @names = @{$self->modNames()};
    foreach (@names) {
        $self->modIsChanged($_) or next;
        return 1;
    }
    return undef;
}


sub prepareRevokeAllModules
{
    my ($self) = @_;

    my $totalTicks = grep {
        $self->modIsChanged($_);
    }  @{$self->modNames};

    return $self->_prepareActionScript('revokeAllModules', $totalTicks);
}

# Method: revokeAllModules
#
#       Revoke the changes made in the configuration for all the modules
#
sub revokeAllModules
{
    my ($self, %options) = @_;

    my $ro = 0;

    my $progress = $options{progress};
    if (not $progress) {
        $progress = EBox::ProgressIndicator::Dummy->create();
    }

    my @names = @{$self->modNames};
    my $failed = "";

    foreach my $name (@names) {
        $self->modIsChanged($name) or next;

        $progress->setMessage($name);
        $progress->notifyTick();

        my $mod = $self->modInstance($ro, $name);
        try {
            $mod->revokeConfig;
        } catch EBox::Exceptions::Internal with {
            $failed .= "$name ";
        };
    }

    if ($failed eq "") {
        $progress->setAsFinished();
        return;
    }

    my $errorText = "The following modules failed while ".
        "revoking their changes, their state is unknown: $failed";
    $progress->setAsFinished(1, $errorText);
    throw EBox::Exceptions::Internal($errorText);
}

# Method: modifiedModules
#
#      Return the list of modified modules sorted by from parameter
#
# Parameters:
#
#      from - String the result is sorted depending on this parameter:
#             'enable' - the sort is done by enableDepends attribute
#             'save'   - the sort is done by depends attribute
#
# Returns:
#
#      array ref - containing the list of modified module names
#
sub modifiedModules
{
    my ($self, $from) = @_;

    defined($from) or throw EBox::Exceptions::MissingArgument('from');

    my $ro = 0;

    my @names = @{$self->modNames};
    my @mods;

    if ($self->modExists('firewall')) {
        push(@mods, 'firewall');
    }
    foreach my $modname (@names) {
        $self->modIsChanged($modname) or next;

        unless (grep(/^$modname$/, @mods)) {
            push(@mods, $modname);
        }

        my @deps = @{$self->modRevDepends($ro, $modname)};
        foreach my $aux (@deps) {
            unless (grep(/^$aux$/, @mods)) {
                push(@mods, $aux);
            }
        }
    }

    @mods = map { __PACKAGE__->modInstance($ro, $_) } @mods;

    my $sorted;
    if ( $from eq 'enable' ) {
        $sorted = sortModulesEnableModDepends(\@mods);
    } else {
        $sorted = __PACKAGE__->sortModulesByDependencies(\@mods, 'depends');
    }

    my @sorted = map { $_->name() } @{$sorted};

    return \@sorted;
}

sub sortModulesEnableModDepends
{
    my ($mods) = @_;
    return __PACKAGE__->sortModulesByDependencies(
        $mods,
        'enableModDepends'
       );
}

sub prepareSaveAllModules
{
    my ($self) = @_;

    my $totalTicks;
    if ($self->first()) {
        # enable + save modules
        $totalTicks = scalar @{$self->modNames} * 2;
    } else {
        # save changed modules
        $totalTicks = scalar @{$self->modifiedModules('save')};
    }
    $totalTicks += $self->_nScripts(PRESAVE_SUBDIR, POSTSAVE_SUBDIR);

    return $self->_prepareActionScript('saveAllModules', $totalTicks);
}

sub packageCache
{
    my $status = stat('/var/lib/dpkg/status');
    my $currentMtime = $status->mtime();

    if (defined ($lastDpkgStatusMtime)) {
        # Regenerate cache only if status file has changed
        if ($currentMtime != $lastDpkgStatusMtime) {
            $_cache = new AptPkg::Cache;
            $_brokenPackages = {};
        }
    } else {
        $_cache = new AptPkg::Cache;
    }
    $lastDpkgStatusMtime = $currentMtime;

    return $_cache;
}

sub brokenPackages
{
    my @names = keys %{$_brokenPackages};
    return \@names;
}

sub _prepareActionScript
{
    my ($self, $action, $totalTicks) = @_;

    my $script = EBox::Config::scripts() . 'global-action';
    $script .= " --action $action";

    my $progressIndicator =  EBox::ProgressIndicator->create(
            executable => $script,
            totalTicks => $totalTicks,
            );

    $progressIndicator->runExecutable();

    return $progressIndicator;
}

# Method: saveAllModules
#
#      Save changes in all modules
#
sub saveAllModules
{
    my ($self, %options) = @_;

    my $ro = 0;

    my $log = EBox::logger();

    my $failed = '';

    # Reset save messages array
    $self->{save_messages} = [];

    my $progress = $options{progress};
    if (not $progress) {
        $progress = EBox::ProgressIndicator::Dummy->create();
    }

    my @mods = @{$self->modifiedModules('save')};
    my $modNames = join (' ', @mods);

    $self->_runExecFromDir(PRESAVE_SUBDIR, $progress, $modNames);

    my $msg = "Saving config and restarting services: @mods";

    $log->info($msg);

    # First installation modules enable
    if ($self->first()) {
        my $mgr = EBox::ServiceManager->new();
        @mods = @{$mgr->_dependencyTree()};
        $modNames = join(' ', @mods);

        foreach my $name (@mods) {
            $progress->setMessage(__x("Enabling {modName} module",
                        modName => $name));
            $progress->notifyTick();

            next if ($name eq 'dhcp'); # Skip dhcp module
            next if ($name eq 'users'); # Skip usersandgroups

            my $module = EBox::GlobalImpl->modInstance($ro, $name);

            # Do not enable this module if dependencies were not enabled
            my $enable = 1;
            foreach my $dep (@{$module->enableModDepends()}) {
                unless (EBox::Global->modEnabled($dep)) {
                    $enable = 0;
                }
            }
            next unless ($enable);

            $module->setInstalled();
            $module->setConfigured(1);
            $module->enableService(1);
            try {
                $module->enableActions();
            } otherwise {
                my ($ex) = @_;
                my $err = $ex->text();
                $module->setConfigured(0);
                $module->enableService(0);
                EBox::debug("Failed to enable module $name: $err");
            };
        }
    }

    my $apache = 0;
    foreach my $name (@mods) {
        if ($name eq 'apache') {
            $apache = 1;
            next;
        }

        $progress->setMessage(__x("Saving {modName} module",
                    modName => $name));
        $progress->notifyTick();

        my $mod = EBox::GlobalImpl->modInstance($ro, $name);
        my $class = 'EBox::Module::Service';

        if ($mod->isa($class)) {
            $mod->setInstalled();

            if (not $mod->configured()) {
                $mod->_saveConfig();
                $self->modRestarted($name);
                next;
            }
        }

        try {
            $mod->save();
        } catch EBox::Exceptions::External with {
            my $ex = shift;
            $ex->throw();
        } otherwise {
            my $ex = shift;
            EBox::error("Failed to save changes in module $name: $ex");
            $failed .= "$name ";
        };
    }

    # Delete first time installation file (wizard)
    $self->deleteFirst();

    # FIXME - tell the CGI to inform the user that apache is restarting
    if ($apache) {
        $progress->setMessage(__x("Saving {modName} module",
                    modName => 'apache'));
        $progress->notifyTick();

        my $mod = EBox::GlobalImpl->modInstance($ro, 'apache');
        try {
            $mod->save();
        }  catch EBox::Exceptions::External with {
            my $ex = shift;
            $ex->throw();
        } otherwise {
            my $ex = shift;
            EBox::error("Failed to save changes in module apache: $ex");
            $failed .= "apache ";
        };
    }


    if (not $failed) {
        $self->_runExecFromDir(POSTSAVE_SUBDIR, $progress, $modNames);
        # Store a timestamp with the time of the ending
        $self->st_set_int(TIMESTAMP_KEY, time());

        my @messages = @{$self->saveMessages()};
        my $message;
        if (@messages) {
            $message = '<ul><li>' . join("</li><li>", @messages) . '</li></ul>';
        }
        $progress->setAsFinished(0, $message);

        return;
    }

    my $errorText = "The following modules failed while ".
        "saving their changes, their state is unknown: $failed";

    $progress->setAsFinished(1, $errorText);
    throw EBox::Exceptions::Internal($errorText);
}

# Method: restartAllModules
#
#       Force a restart for all the modules
#
sub restartAllModules
{
    my $self = shift;

    my $ro = 1;

    my @names = @{$self->modNames};
    my $log = EBox::logger();
    my $failed = "";
    $log->info("Restarting all modules");

    unless ($self->isReadOnly) {
        $self->{'mod_instances_rw'} = {};
    }

    foreach my $name (@names) {
        my $mod = EBox::GlobalImpl->modInstance($ro, $name);
        try {
            $mod->restartService();
        } catch EBox::Exceptions::Internal with {
            $failed .= "$name ";
        };
    }
    if ($failed eq "") {
        return;
    }
    throw EBox::Exceptions::Internal("The following modules failed while ".
            "being restarted, their state is unknown: $failed");
}

# Method: stopAllModules
#
#       Stops all the modules
#
sub stopAllModules
{
    my $self = shift;
    my @names = @{$self->modNames};
    my $log = EBox::logger();
    my $failed = "";
    $log->info("Stopping all modules");

    my $ro = 1;

    unless ($self->isReadOnly) {
        $self->{'mod_instances_rw'} = {};
    }

    foreach my $name (@names) {
        my $mod = EBox::GlobalImpl->modInstance($ro, $name);
        try {
            $mod->stopService();
        } catch EBox::Exceptions::Internal with {
            $failed .= "$name ";
        };
    }

    if ($failed eq "") {
        return;
    }
    throw EBox::Exceptions::Internal("The following modules failed while ".
            "stopping, their state is unknown: $failed");
}

# Method: modInstances
#
#       Return an array ref with an instance of every module
#
# Returns:
#
#       array ref - the elements contains the instance of modules
#
sub modInstances
{
    my ($self, $ro) = @_;

    $self = EBox::GlobalImpl->instance();
    my @names = @{$self->modNames};
    my @array = ();

    foreach my $name (@names) {
        my $mod = $self->modInstance($ro, $name);
        push(@array, $mod);
    }
    return \@array;
}

# Method: modInstancesOfType
#
#       Return an array ref with an instance of every module that extends
#       a given classname
#
#   Parameters:
#
#       classname - the class base you are interested in
#
# Returns:
#
#       array ref - the elments contains the instance of the modules
#                   extending the classname
#
sub modInstancesOfType
{
    my ($self, $ro, $classname) = @_;

    $self = EBox::GlobalImpl->instance();
    my @names = @{$self->modNames};
    my @array = ();

    foreach my $name (@names) {
        my $mod = $self->modInstance($ro, $name);
        if ($mod->isa($classname)) {
            push(@array, $mod);
        }
    }
    return \@array;
}


# Method: modInstance
#
#       Build an instance of a module. Can be called as a class method or as an
#       object method.
#
#   Parameters:
#
#       module - module name
#
# Returns:
#
#       If everything goes ok:
#
#       <EBox::Module> - An instance of the requested module
#
#       Otherwise
#
#       undef
#
sub modInstance
{
    my ($self, $ro, $name) = @_;

    if (not $name) {
        throw EBox::Exceptions::MissingArgument(q{module's name});
    }

    my $global = EBox::GlobalImpl->instance();

    if ($name eq 'global') {
        return $global;
    }

    my $instances = $ro ? $global->{'mod_instances_ro'} : $global->{'mod_instances_rw'};
    my $modInstance = $instances->{$name};
    if (defined($modInstance)) {
        return $modInstance;
    }

    $global->modExists($name) or return undef;
    my $classname = $global->_className($name);
    unless ($classname) {
        throw EBox::Exceptions::Internal("Module '$name' ".
                                         "declared, but it has no classname.");
    }
    eval "use $classname";
    if ($@) {
        throw EBox::Exceptions::Internal("Error loading ".
                                         "class: $classname error: $@");
    }

    $instances->{$name} = $classname->_create(ro => $ro);
    return $instances->{$name};
}


# Method: logger
#
#       Initialise Log4perl if necessary, returns the logger for the i
#       caller package
#
#   Parameters:
#
#       caller -
#
# Returns:
#
#       If everything goes ok:
#
#       <EBox::Module> - A instance of the requested module
#
#       Otherwise
#
#       undef
sub logger # (caller?)
{
    shift;
    EBox::deprecated();
    return EBox::logger(shift);
}

# Method: modDepends
#
#       Return an array ref with the names of the modules that the requested
#       module depends on
#
#   Parameters:
#
#       module - requested module
#
# Returns:
#
#       undef -  if the module does not exist
#       array ref - holding the names of the modules that the requested module
#
sub modDepends
{
    my ($self, $ro, $name) = @_;

    $self->modExists($name) or return undef;
    my $mod = $self->modInstance($ro, $name);
    return $mod->depends();
}

# Method: modRevDepends
#
#       Return an array ref with the names of the modules which depend on a given
#       module
#
#   Parameters:
#
#       module - requested module
#
# Returns:
#
#       undef -  if the module does not exist
#       array ref - holding the names of the modules which depend on the
#       requested module
#
sub modRevDepends
{
    my ($self, $ro, $name) = @_;

    $self->modExists($name) or return undef;
    my @revdeps = ();
    my @mods = @{$self->modNames};
    foreach my $mod (@mods) {
        my @deps = @{$self->modDepends($ro, $mod)};
        foreach my $dep (@deps) {
            defined($dep) or next;
            if ($name eq $dep) {
                push(@revdeps, $mod);
                last;
            }
        }
    }
    return \@revdeps;
}


# Name: sortModulesByDependencies
#
#  Sort a list of modules objects by its dependencies. The dependencies are get
# using a method that returns the names of the dependencies of each module.
#
#  Parameters:
#        modules_r          - reference to list of modules
#        dependenciesMethod - name of the method called in each module
#                             to get its dependencies
sub sortModulesByDependencies
{
    my ($package, $modules_r, $dependenciesMethod) = @_;

    my @modules = @{ $modules_r };
    my %availableModulesAndDependencies = map {
        $_->name() => undef;
    } @modules;

    my $i =0;
    while ($i < @modules) {
        my $mod = $modules[$i];
        my $modName = $mod->name();
        my @depends = ();
        if (defined $availableModulesAndDependencies{$modName}) {
            @depends = @{ $availableModulesAndDependencies{$modName} }
        } elsif ($mod->can($dependenciesMethod)) {
            @depends  = @{ $mod->$dependenciesMethod() };
            @depends = grep {
                exists $availableModulesAndDependencies{$_}
            } @depends;
            $availableModulesAndDependencies{$modName} = \@depends;
        }

        my $depOk = 1;

        foreach my $dependency (@depends) {
            my $depFound = 0;
            foreach my $j (0 .. $i) {
                if ($i == $j) {
                    # for $i ==0 case
                    last;
                } elsif ($modules[$j]->name() eq $dependency) {
                    $depFound = 1;
                    last;
                }
            }

            if (not $depFound) {
                $depOk = 0;
                last;
            }
        }

        if ($depOk) {
            $i += 1;
        } else {
            my $unreadyMod = splice @modules, $i, 1;
            push @modules, $unreadyMod;
        }

    }

    return \@modules;
}

# Method: lastModificationTime
#
#      Return the latest modification time, this is the latest of
#      these events:
#
#      - After finishing saving changes using <saveAllModules> call
#      - After a modification in LDAP in users module is present and at
#      least configured
#
# Returns:
#
#      Int - the lastModificationTime
#
sub lastModificationTime
{
    my ($self) = @_;

    my $lastStamp = $self->st_get_int(TIMESTAMP_KEY);
    $lastStamp = 0 unless defined($lastStamp);
    if ( $self->modExists('users') ) {
        my $usersMod = $self->modInstance('ro', 'users');
        if ( $usersMod->configured() ) {
            my ($sec, $min, $hour, $mday, $mon, $year) = localtime($lastStamp);
            my $lastStampStr = sprintf('%04d%02d%02d%02d%02d%02dZ',
                                       ($year + 1900, $mon + 1, $mday, $hour,
                                        $min, $sec));
            my $ldapStamp = $usersMod->ldap()->lastModificationTime($lastStampStr);
            if ( $ldapStamp > $lastStamp ) {
                $lastStamp = $ldapStamp;
            }
        }
    }

    return $lastStamp;
}

# Method: first
#
#      Check if the file created on the first installation exists
#
# Returns:
#
#       boolean - True if the file exists, false if not
#
sub first
{
    return (-f FIRST_FILE);
}

# Method: deleteFirst
#
#      Delete the file created on first installation, if exists
#
sub deleteFirst
{
    if (-f FIRST_FILE) {
        unlink (FIRST_FILE);
    }
}

# Method: saveMessages
#
# Returns:
#
#     Array ref - messages produced by modules during saveAllModules process
#
sub saveMessages
{
    my ($self) = @_;

    return $self->{save_messages};
}

# Method: addSaveMessage
#
# Parameters:
#
#     String - message to add to saveMessages list
#
sub addSaveMessage
{
    my ($self, $message) = @_;

    my $messages = $self->{save_messages};
    push (@{$messages}, $message);
}

# Method: _runExecFromDir
#
#      Run executables files from a directory using
#      <EBox::Sudo::command>. The execution will be done in lexical
#      order
#
# Parameters:
#
#      dir - String the directory to search for executables
#
#      progress - <EBox::ProgressIndicator> to indicate the user how
#      the actions are being performed
#
#      modNames - string with the names of modified modules
#
# Exceptions:
#
#      The ones launched by <EBox::Sudo::command>
#
sub _runExecFromDir
{
    my ($self, $dirPath, $progress, $modNames) = @_;

    unless ( -e $dirPath ) {
        throw EBox::Exceptions::DataNotFound(data  => 'directory',
                                             value => $dirPath);
    }

    opendir(my $dh, $dirPath);
    my @execs = ();
    while( my $file = readdir($dh) ) {
        next unless ( -f "${dirPath}/$file" or -l "${dirPath}/$file");
        next unless ( -x "${dirPath}/$file" );
        push(@execs, "${dirPath}/$file");
    }
    closedir($dh);

    # Sorting lexically the scripts to execute
    @execs = sort(@execs);

    if ( @execs > 0 ) {
        EBox::info("Running executable files from $dirPath");
        foreach my $exec (@execs) {
            try {
                EBox::info("Running $exec");
                # Progress indicator stuff
                $progress->setMessage(__x('running {scriptName} script',
                                          scriptName => scalar(File::Basename::fileparse($exec))));
                $progress->notifyTick();
                my $output = EBox::Sudo::command("$exec $modNames");
                if ( @{$output} > 0) {
                    EBox::info("Output from $exec: @{$output}");
                }
            } catch EBox::Exceptions::Command with {
                my ($exc) = @_;
                my $msg = "Command $exec failed its execution\n"
                  . 'Output: ' . @{$exc->output()} . "\n"
                  . 'Error: ' . @{$exc->error()} . "\n"
                  . 'Return value: ' . $exc->exitValue();
                EBox::error($msg);
            } otherwise {
                my ($exc) = @_;
                EBox::error("Error executing $exec: $exc");
            };
        }
    }
}

# Method: _nScripts
#
# Parameters:
#
#     array - the dir path to count executable files
#
# Returns:
#
#     Integer - number of executable scripts in pre/post dirs
#
sub _nScripts
{
    my ($self, @dirPaths) = @_;

    my $nScripts = 0;
    foreach my $dirPath (@dirPaths) {
        opendir(my $dh, $dirPath);
        while( my $file = readdir($dh) ) {
            next unless ( -f "${dirPath}/$file" or -l "${dirPath}/$file");
            next unless ( -x "${dirPath}/$file" );
            $nScripts++;
        }
        closedir($dh);
    }
    return $nScripts;
}

sub _packageInstalled
{
    my ($name) = @_;

    if (exists $_installedPackages->{$name}) {
        return 1;
    }

    my $cache = packageCache();

    my $installed = 0;
    if ($cache->exists($name)) {
        my $pkg = $cache->get($name);
        if ($pkg->{SelectedState} == AptPkg::State::Install) {
            $installed = ($pkg->{InstState} == AptPkg::State::Ok and
                          $pkg->{CurrentState} == AptPkg::State::Installed);

            if ($installed) {
                $_installedPackages->{$name} = 1;
            } else {
                $_brokenPackages->{$name} = 1;
            }
        }
    }
    return $installed;
}

1;
