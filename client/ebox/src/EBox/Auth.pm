# Copyright (C) 2005 Warp Networks S.L.
# Copyright (C) 2006-2007 Warp Networks S.L.
# Copyright (C) 2008-2010 eBox Technologies S.L.
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

package EBox::Auth;

use strict;
use warnings;

use base qw(EBox::ThirdParty::Apache2::AuthCookie);

use EBox;
use EBox::CGI::Run;
use EBox::Config;
use EBox::Gettext;
use EBox::Global;
use EBox::Exceptions::Internal;
use EBox::Exceptions::Lock;
use EBox::LogAdmin;
use Apache2::Connection;
use Apache2::Const qw(:common HTTP_FORBIDDEN HTTP_MOVED_TEMPORARILY);

use Authen::Simple::PAM;
use Digest::MD5;
use Fcntl qw(:flock);

# By now, the expiration time for session is hardcoded here
use constant EXPIRE => 3600; #In seconds  1h
# By now, the expiration time for a script session
use constant MAX_SCRIPT_SESSION => 10; # In seconds
# CC cookie
use constant CC_COOKIE_NAME => 'EBox_Services_Remote_Access';
use constant CC_DOMAIN => 'dynamic.ebox-services.com';

sub new
{
    my $class = shift;
    my $self = {};
    bless($self, $class);
    return $self;
}

# Parameters:
#
#   - session id : if the id is undef, it truncates the session file
# Exceptions:
#   - Internal
#       - When session file cannot be opened to write
sub _savesession # (session_id)
{
    my ($sid) = @_;
    my $sidFile;
    my $openMode = '>';
    if ( -f EBox::Config->sessionid() ) {
        $openMode = '+<';
    }
    unless  ( open ( $sidFile, $openMode, EBox::Config->sessionid() )){
        throw EBox::Exceptions::Internal(
                "Could not open to write ".
                EBox::Config->sessionid);
    }
    # Lock the file in exclusive mode
    flock($sidFile, LOCK_EX)
        or throw EBox::Exceptions::Lock('EBox::Auth');
    # Truncate the file after locking
    truncate($sidFile, 0);
    print $sidFile $sid . "\t" . time if defined $sid;
    # Release the lock
    flock($sidFile, LOCK_UN);
    close($sidFile);
}

# Method: checkValidUser
#
#       Check with PAM if the user/password provided is of a valid admin
#
# Parameters:
#
#       username - string containing the user name
#       password - string containing the plain password
#
# Returns:
#
#       boolean - true if it's correct, otherwise false
#
sub checkValidUser
{
    my ($self, $username, $password) = @_;

    my $pam = new Authen::Simple::PAM(service => 'zentyal');

    return $pam->authenticate($username, $password);
}

# Method: setPassword
#
#       Changes the password of the given username
#
# Parameters:
#
#       username - username to change the password
#       password - string containing the plain password
#
# Exceptions:
#
#   <EBox::Exceptions::Internal> - when password cannot be changed
#   <EBox::Exceptions::External> - when password length is no
#                                  longer than 6 characters
sub setPassword
{
    my ($self, $username, $password) = @_;

    unless (length($password) > 5) {
        throw EBox::Exceptions::External('The password must be at least 6 characters long');
    }

    open(my $pipe, "|/usr/bin/sudo /usr/sbin/chpasswd") or
        throw EBox::Exceptions::Internal("Could not change password: $!");

    print $pipe "$username:$password\n";
    close($pipe);
    EBox::LogAdmin::logAdminNow('ebox',__n('Password changed'),'');
}

# Method: authen_cred
#
#       Overriden method from <Apache2::AuthCookie>.
#
sub authen_cred  # (request, $user, password, fromCC)
{
    my ($self, $r, $user, $passwd, $fromCC) = @_;

    # If there's a script session opened, give it priority to the
    # Web interface session
    if ( $self->_actionScriptSession() ){
        EBox::warn('Failed login since a script session is opened');
        $r->subprocess_env(LoginReason => 'Script active');
        return;
    }

    # Unless it is a CC session or password does
    if ( not (defined($fromCC) and $fromCC) ) {
        unless ($self->checkValidUser($user, $passwd)) {
            my $log = EBox->logger();
            my $ip  = $r->connection->remote_ip();
            $log->warn("Failed login from: $ip");
            return;
        }
    }

    my $rndStr;
    for my $i (1..64) {
        $rndStr .= rand (2**32);
    }
    my $md5 = Digest::MD5->new();
    $md5->add($rndStr);
    my $sid = $md5->hexdigest();
    _savesession($sid);

    my $global = EBox::Global->getInstance();
    $global->revokeAllModules();

    return $sid;
}


# Method: authen_ses_key
#
#       Overriden method from <Apache2::AuthCookie>.
#
sub authen_ses_key  # (request, session_key)
{
    my ($self, $r, $session_key) = @_;

    my ($sid, $lastime) = _currentSessionId();

    my $expired =  _timeExpired($lastime);

    if ( $self->_actionScriptSession() ) {
        $r->subprocess_env(LoginReason => 'Script active');
        _savesession(undef);
    }
    elsif(($session_key eq $sid) and (!$expired )){
        _savesession($sid);
        return "admin";
    }
    elsif ($expired) {
        $r->subprocess_env(LoginReason => "Expired");
        _savesession(undef);
    }
    else {
        $r->subprocess_env(LoginReason => "Already");
    }

    return;
}

# Method: loginCC
#
#      Login from Control Center, which is different if the
#      passwordless option is activated
#
# Parameters:
#
#      request - <Apache2::RequestRec> the HTTP request
#
# Return:
#
#     the same response as <Apache2::AuthCookie::login> gives back
#
sub loginCC
{
    my ($self, $req) = @_;

    if ( $self->recognize_user($req) == OK ) {
        return $self->authenticate($req);
    } else {
        if ( EBox::Global->modExists('remoteservices') ) {
            my $remoteServMod = EBox::Global->modInstance('remoteservices');
            if ( $remoteServMod->eBoxSubscribed()
                 and $remoteServMod->model('AccessSettings')->passwordlessValue()) {
                # Do what login does
                my $sessionKey = $self->authen_cred($req,'',1);
                $self->send_cookie($req, $sessionKey);
                $self->handle_cache($req);
                $req->headers_out()->set('Location' => '/ebox/');
                return HTTP_MOVED_TEMPORARILY;
            }
        }
        return EBox::CGI::Run->run('/Login/Index', 'EBox');
    }
}

# XXX not sure if this will be useful, if not remove
sub alreadyLogged
{
    my ($self) = @_;
    my ($sid, $lastime) = _currentSessionId();

    return 0 if !defined $sid;
    return 0 if _timeExpired($lastime);

    return 1;
}

# scalar mode: return the sessionid
# list mode:   return (sessionid, lastime)
sub _currentSessionId
{
    my $SID_F; # sid file handle

    unless(-e EBox::Config->sessionid()) {
        unless (open ($SID_F,  ">". EBox::Config->sessionid())) {
            throw EBox::Exceptions::Internal("Could not create  " .
                                             EBox::Config->sessionid);
        }
        close($SID_F);
        return;
    }
    unless (open ($SID_F,  EBox::Config->sessionid())) {
        throw EBox::Exceptions::Internal(
                "Could not open ".
                EBox::Config->sessionid);
    }

    # Lock in shared mode for reading
    flock($SID_F, LOCK_SH)
        or throw EBox::Exceptions::Lock('EBox::Auth');

    $_ = <$SID_F>;
    my ($sid, $lastime);
    ($sid, $lastime) = split /\t/ if defined $_;

    # Release the lock
    flock($SID_F, LOCK_UN);
    close($SID_F);

    if (wantarray()) {
        return ($sid, $lastime) ;
    }
    else {
        return $sid;
    }
}

sub _timeExpired
{
    my ($lastime) = @_;

    my $expires = $lastime + EXPIRE;

    my $expired = (time() > $expires);
    return $expired;
}

# Method: _actionScriptSession
#
#       Check whether a script session is already opened or not
#
# Returns:
#
#       Boolean - indicate if a script session is already opened
#
sub _actionScriptSession
{

    my ($self) = @_;

    # The script session filehandle
    my $scriptSessionFile;

    unless ( -e EBox::Config->scriptSession() ){
        return undef;
    }

    # Trying to open the script sid
    open( $scriptSessionFile, '<', EBox::Config->scriptSession() ) or
      throw EBox::Exceptions::Internal('Could not open ' .
                                       EBox::Config->scriptSession());

    # Lock in shared mode
    flock($scriptSessionFile, LOCK_SH)
      or throw EBox::Exceptions::Lock($self);

    # The file structure is the following:
    # TIMESTAMP
    my ($timeStamp) = <$scriptSessionFile>;

    # Release the lock and close the file
    flock($scriptSessionFile, LOCK_UN);
    close($scriptSessionFile);

    # time() return the # of seconds since an epoch (1 Jan 1970
    # typically)

    my $expireTime = $timeStamp + MAX_SCRIPT_SESSION;
    return ( $expireTime >= time() );
}

1;
