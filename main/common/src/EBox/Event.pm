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

package EBox::Event;

# Class: EBox::Event
#
# This package is intended to support events. These events could be
# sent to the control center or it is also be recorded
#

use strict;
use warnings;

# Constants:
use constant LEVEL_VALUES => qw(info warn error fatal);

# eBox uses
use EBox::Config;

##################
# Core modules
##################
use POSIX qw(strftime);

##################
# Dependencies
##################
use Perl6::Junction qw(any);

# Constructor: new
#
#      Create a new <EBox::Event> object
#
# Parameters:
#
#      message - String a i18ned message which will be dispatched
#
#      source - String the event watcher/subwatcher name to categorise
#               afterwards the event depending on the source.
#
#      compMessage - String this field is indicated to distinguish
#                    among events from the same source but the message
#                    is different. We could think of it as a message
#                    which is not i18ned.
#
#                    *(Optional)* Default value: undef
#
#      level - Enumerate the level of the event *(Optional)*
#              Possible values: 'info', 'warn', 'error' or 'fatal'.
#              Default: 'info'
#
#      timestamp - Int the number of seconds since the epoch (1 Jan 1970)
#                  *(Optional)* Default value: now
#
#      dispatchTo - array ref containing the relative name for the
#      dispatchers you want to dispatch this event *(Optional)*
#      Default value: *any*, which means any available dispatcher will
#      dispatch the event. Concrete example: ControlCenter
#
#      duration - Int the event duration in seconds
#                 Default value: 0, no duration an instant event
#
#      - Named parameters
#
# Exceptions:
#
#      <EBox::Exceptions::MissingArgument> - thrown if any argument is
#      not present
#      <EBox::Exceptions::InvalidType> - thrown if any
#      argument is not from the correct type
#
sub new
{
    my ($class, %args) = @_;

    my $self = {};
    bless ( $self, $class );

    defined ( $args{message} ) or
      throw EBox::Exceptions::MissingArgument('message');
    defined ( $args{source} ) or
      throw EBox::Exceptions::MissingArgument('source');

    if ( defined ($args{level}) ) {
        unless ( $args{level} eq any(LEVEL_VALUES)) {
            throw EBox::Exceptions::InvalidType('level',
                                                'enumerate type, possible values: ' . LEVEL_VALUES);
        }
    }
    $self->{message} = delete ( $args{message} );
    $self->{source} = delete ( $args{source} );
    $self->{compMessage} = delete ( $args{compMessage} );
    $self->{level} = delete ( $args{level} );
    $self->{level} = 'info' unless defined ( $self->{level} );
    $self->{dispatchers} = delete ( $args{dispatchTo} );
    $self->{dispatchers} = ['any'] unless defined ( $self->{dispatchers} );
    $self->{timestamp} = delete ( $args{timestamp} );
    $self->{timestamp} = time() unless defined ( $self->{timestamp} );
    $self->{duration}  = delete ( $args{duration} );
    $self->{duration}  = 0 unless ( defined($self->{duration}) );

    return $self;
}

# Method: message
#
#     Accessor to the i18ned event message
#
# Returns:
#
#     String - the message
#
sub message
{
    my ( $self ) = @_;

    return $self->{message};
}

# Method: source
#
#     Accessor to the source of the event, that is, the event
#     watcher/subwatcher name
#
# Returns:
#
#     String - the source
#
sub source
{
    my ( $self ) = @_;

    return $self->{source};
}

# Method: compMessage
#
#     Accessor to the compMessage of the event, that is, the category of
#     a source from an event. The non-i18ned counterpart of message.
#
# Returns:
#
#     String - the compMessage field, it could be undef
#
sub compMessage
{
    my ( $self ) = @_;

    return $self->{compMessage};
}

# Method: level
#
#     Accessor to the event level
#
# Returns:
#
#     Enum - the level can be 'info', 'warn', 'error' or 'fatal'
#
sub level
{
    my ( $self ) = @_;

    return $self->{level};
}

# Method: dispatchTo
#
#       Get the dispatcher to dispatch the message
#
# Returns:
#
#       array ref - the containing the relative name for the
#       dispatchers you want to dispatch this event
#
sub dispatchTo
{
    my ($self) = @_;

    return $self->{dispatchers};
}

# Method: timestamp
#
#       Get the event timestamp when the event has been happened
#
# Returns:
#
#       Int - the event timestamp
#
sub timestamp
{
    my ($self) = @_;

    return $self->{timestamp};
}

# Method: strTimestamp
#
#       Get the event timestamp in RFC 822 complaint format. That is,
#       "dayweek, dm month yyyy hh:mm:ss".
#
# Example:
#
#       Tue, 02 Sep 2007 10:02:12
#
# Returns:
#
#       String - the event timestamp in RFC 822 format
#
sub strTimestamp
{
    my ($self) = @_;

    return strftime("%a, %d %b %Y %T %z",
                    localtime($self->{timestamp}));
}

# Method: duration
#
#       Get the event duration. That is, from the event starting point
#       up to the event was dispatched by the watcher.
#
# Returns:
#
#       Int - the event duration
#
sub duration
{
    my ($self) = @_;

    return $self->{duration};
}

1;
