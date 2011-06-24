# Copyright (C) 2011 eBox Technologies S.L.
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

package EBox::Virt::AbstractBackend;

use strict;
use warnings;

use EBox::Exceptions::NotImplemented;

# Class: EBox::Virt::AbstractBackend
#
#   Abstract class with the methods that each virtualization backend
#   has to implement

# Method: createDisk
#
#   Creates a disk image.
#
# Parameters:
#
#   file    - filename of the disk image
#   size    - size of the disk in megabytes
#
sub createDisk
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: resizeDisk
#
#   Resizes a VDI file.
#
# Parameters:
#
#   file    - filename of the disk image
#   size    - size of the disk in megabytes
#
sub resizeDisk
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: vmExists
#
#   Checks if a VM with the given name already exists
#
# Parameters:
#
#   name    - virtual machine name
#
# Returns:
#
#   boolean - true if exists, false if not
#
sub vmExists
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: vmRunning
#
#   Checks if a VM with the given name is running
#
# Parameters:
#
#   name    - virtual machine name
#
# Returns:
#
#   boolean - true if running, false if not
#
sub vmRunning
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: createVM
#
#   Creates a new virtual machine
#
# Parameters:
#
#   name    - virtual machine name
#   os      - operating system identifier
#
sub createVM
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: startVMCommand
#
#   Command to start a VM with a VNC server on the specified port.
#
# Parameters:
#
#   name    - virtual machine name
#   port    - VNC port
#
# Returns:
#
#   string with the command
#
sub startVMCommand
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: shutdownVMCommand
#
#   Command to shut down a virtual machine.
#
# Parameters:
#
#   name    - virtual machine name
#
sub shutdownVMCommand
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: shutdownVM
#
#   Shuts down a virtual machine.
#
# Parameters:
#
#   name    - virtual machine name
#
sub shutdownVM
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: pauseVM
#
#   Pauses a virtual machine.
#
# Parameters:
#
#   name    - virtual machine name
#
sub pauseVM
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: resumeVM
#
#   Shuts down a virtual machine.
#
# Parameters:
#
#   name    - virtual machine name
#
sub resumeVM
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: deleteVM
#
#   Deletes a virtual machine.
#
# Parameters:
#
#   name    - virtual machine name
#
sub deleteVM
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: setMemory
#
#   Set memory amount for the given VM.
#
# Parameters:
#
#   name    - virtual machine name
#   size    - memory size (in megabytes)
#
sub setMemory
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: setOS
#
#   Set the OS type for the given VM.
#
# Parameters:
#
#   name    - virtual machine name
#   os      - operating system identifier
#
sub setOS
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: setIface
#
#   Set a network interface for the given VM.
#
# Parameters:
#
#   name    - virtual machine name
#   iface   - iface number
#   type    - iface type (nat, bridged, internal)
#   arg     - iface arg (bridged => devicename, internal => networkname)
#
sub setIface
{
    throw Ebox::Exceptions::NotImplemented();
}

sub initDeviceNumbers
{
}

# Method: attachDevice
#
#   Attach a device to a VM.
#
# Parameters:
#
#   name   - virtual machine name
#   port   - port number
#   device - device number
#   type   - hdd | dvddrive | none
#   file   - path of the ISO or VDI file
#
sub attachDevice
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: systemTypes
#
#   Returns system types supported by the virtualizer
#
# Returns:
#
#   [ { value => 'foo', printableValue => 'Foo' }, ... ]
#
sub systemTypes
{
    throw Ebox::Exceptions::NotImplemented();
}

# Method: writeConf
#
#   Writes configuration file for a VM if needed.
#
# Parameters:
#
#   name    - virtual machine name
#
sub writeConf
{
}

1;
