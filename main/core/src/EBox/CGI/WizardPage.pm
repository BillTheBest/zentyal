# Copyright (C) 2010 eBox Technologies S.L.
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

#
# Wizard pages are used by modules to help user on initial configuration
# If a module implements some wizard it will be shown by zentyal-software to
# the user
#
# A wizard page CGI has 2 types of calls differentiated by HTTP request method:
#
#   - GET - The page will show a form that the user must fill
#   - POST - That form will sent to this CGI for processing.
#
# If form processing fails POST request must response with an error code and
# print an error messages that user will see
#
# If status is OK the wizard will step into next wizard page.
#
package EBox::CGI::WizardPage;
use strict;
use warnings;

use base 'EBox::CGI::Base';
use EBox::Gettext;
use EBox::Html;
use HTML::Mason::Exceptions;
use Apache2::RequestUtil;
use Error qw(:try);
use HTML::Mason::Exceptions;
use EBox::Exceptions::DataInUse;
use EBox::Exceptions::Base;

use constant ERROR_STATUS => '500';

## arguments
##		title [optional]
##		error [optional]
##		msg [optional]
##		cgi   [optional]
##		template [optional]
sub new # (title=?, error=?, msg=?, cgi=?, template=?)
{
    my $class = shift;
    my %opts = @_;

    my $self = $class->SUPER::new(@_);
    my $namespace = delete $opts{'namespace'};
    my $tmp = $class;
    $tmp =~ s/^(.*?)::CGI::(.*?)(?:::)?(.*)//;
    if(not $namespace) {
        $namespace = $1;
    }
    $self->{namespace} = $namespace;
    $self->{module} = $2;
    $self->{cginame} = $3;
    if (defined($self->{cginame})) {
        $self->{url} = $self->{module} . "/" . $self->{cginame};
    } else {
        $self->{url} = $self->{module} . "/Index";
    }

    bless($self, $class);
    return $self;
}


# Method: _processWizard
#
# Processes form submission and configures module
#
sub _processWizard
{
    # Override this to process wizard page
}


# Method: _masonParameters
#
# Configures parameteres for mason template
#
# Returns
#   array ref to mason parameters
sub _masonParameters
{
    # Override this to set mason template params
}

sub _print
{
	my ($self) = @_;
	$self->_header();
    if ( $self->{cgi}->request_method() eq 'GET' ) {
	    $self->_body();
    }
}


sub _process
{
    my $self = shift;
    $self->{params} = $self->_masonParameters();
    if ( $self->{cgi}->request_method() eq 'POST' ) {
	    $self->_processWizard();
    }
}


sub _print_error
{
    my ($self, $text) = @_;
    $text or return;
    ($text ne "") or return;

    # We send a ERROR_STATUS code. This is necessary in order to trigger
    # onFailure functions on Ajax code
    my $r = Apache2::RequestUtil->request();
    $r->status(ERROR_STATUS);
    $r->subprocess_env('suppress-error-charset' => 1) ;
    $r->custom_response(ERROR_STATUS, $text);
}

sub run
{
    my $self = shift;

    if (not $self->_loggedIn) {
        $self->{redirect} = "/ebox/Login/Index";
    }
    else {
        try {
            $self->_validateReferer();
            $self->_process();
            $self->_print;
        } otherwise {
            my $ex = shift;
            my $logger = EBox::logger;
            if (isa_mason_exception($ex)) {
                $logger->error($ex->as_text);
                my $error = __("An internal error related to ".
                        "a template has occurred. This is ".
                        "a bug, relevant information can ".
                        "be found in the logs.");
                $self->_print_error($error);
            } else {
                if ($ex->can('text')) {
                    $logger->error('Exception: ' . $ex->text());
                    $self->_print_error($ex->text());
                } else {
                    $logger->error('Unknown exception');
                    $self->_print_error('Unknown exception');
                }
            }
        };
    }
}


sub _title
{

}

sub _header
{
    my $self = shift;
    print($self->cgi()->header(-charset=>'utf-8'));
}

sub _footer
{

}

sub _menu
{

}

1;
