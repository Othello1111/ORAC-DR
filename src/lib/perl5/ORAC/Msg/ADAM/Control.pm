package ORAC::Msg::ADAM::Control;


=head1 NAME

ORAC::Msg::ADAM::Control - control and initialise ADAM messaging from ORAC

=head1 SYNOPSIS

  use ORAC::Msg::ADAM::Control;

  $ams = new ORAC::Msg::ADAM::Control(1);
  $ams->init;

  $ams->messages(0);
  $ams->errors(1);
  $ams->timeout(30);
  $ams->stderr(*ERRHANDLE);
  $ams->stdout(*MSGHANDLE);
  $ams->paramrep( sub { return "!" } );
  

=head1 DESCRIPTION

Methods to initialise the ADAM messaging system (AMS) )and control the
behaviour.

=head1 METHODS

The following methods are available:

=over 4

=cut


use strict;
use Carp;

use vars qw/$VERSION $RUNNING/;

$VERSION = '0.01';

*RUNNING = *Starlink::AMS::Init::AMSRUNNING;


# This needs to Starlink module
use Starlink::AMS::Init;

# Derive all methods from the Starlink module since this
# behaves in exactly the same way.

@ORAC::Msg::ADAM::Control::ISA = qw/Starlink::AMS::Init/;


=item new

Create a new instance of Starlink::AMS::Init.
If a true argument is supplied the messaging system is also
initialised via the init() method.


=item messages

Method to set whether standard messages returned from monoliths
are printed or not. If set to true the messages are printed
else they are ignored.

  $current = $ams->messages;
  $ams->messages(0);

Default is to print all messages.

=item errors

Method to set whether error messages returned from monoliths
are printed or not. If set to true the errors are printed
else they are ignored.

  $current = $ams->errors;
  $ams->errors(0);

Default is to print all messages.

=item timeout

Set or retrieve the timeout (in seconds) for some of the ADAM messages.
Default is 30 seconds.

  $ams->timeout(10);
  $current = $ams->timeout;

=item stderr

Set and retrieve the current filehandle to be used for printing
error messages. Default is to use STDERR.

=item stderr

Set and retrieve the current filehandle to be used for printing
normal ADAM messages. Default is to use STDOUT.

=item paramrep

Set and retrieve the code reference that will be executed if
the parameter system needs to ask for a parameter.
Default behaviour is to call a routine that simply prompts
the user for the required value. The supplied subroutine
should accept three arguments (the parameter name, prompt string and
default value) and should return the required value.

  $self->paramrep(\&mysub);

A simple check is made to make sure that the supplied argument
is a code reference.

Warning: It is possible to get into an infinite loop if you try
to continually return an unacceptable answer.

=item init

Initialises the ADAM messaging system. This routine should always be
called before attempting to control I-tasks.

A relay task is spawned in order to test that the messaging system
is functioning correctly. The relay itself is not necessary for the
non-event loop implementation. If this command hangs then it is
likely that the messaging system is not running correctly (eg
because the system was shutdown uncleanly - try removing named pipes
from the ~/adam directory).

=back

=head1 VARIABLES

The ORAC::Msg::ADAM::Control::RUNNING variable can be 
used to determine whether the message system is running or not.
(Multiple message system objects can be created although only
the first will actually start the message system - an error is raised
if multiple objects are created).

=head1 REQUIREMENTS

This module requires the Starlink::AMS::Init module.

=head1 SEE ALSO

L<Starlink::AMS::Init>

=head1 AUTHORS

Tim Jenness (t.jenness@jach.hawaii.edu)
and Frossie Economou (frossie@jach.hawaii.edu)    

=cut


1;
