package Test::Builder::Tester;

use strict;
use vars qw(@EXPORT $VERSION @ISA);
$VERSION = 0.07;

use Test::Builder;
use Symbol;
use Carp;

=head1 NAME

Test::Builder::Tester - test testsuites that have been built with
Test::Builder

=head1 SYNOPSIS

    use Test::Builder::Tester tests => 1;
    use Test::More;

    test_out("not ok 1 - foo");
    test_err("#     Failed test ($0 at line ".line_num(+1).")");
    fail("foo");
    test_test("fail works");

=head1 DESCRIPTION

A module that helps you test test modules that are built with
Test::Builder.

Basically, the system works by performing a three step process for
each test you wish to test.  This starts with using 'test_out' and
'test_err' in advance to declare what the testsuite you are testing
will output with Test::Builder to it's stdout and stderr.

You then can run the test(s) from your test suite that call
Test::Builder.  The output of Test::Builder is captured by
Test::Builder::Tester rather than going to its usual destination.

The final stage is to call test_test that will simply compare what you
predeclared to what Test::Builder actually outputted, and report the
results back with a "ok" or "not ok" (with debugging) to the normal
output.

=cut

####
# set up testing
####

my $t = Test::Builder->new;

###
# make us an exporter
###

use Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(test_out test_err test_fail test_diag test_test line_num);

# _export_to_level and import stolen directly from Test::More.  I am
# the king of cargo cult programming ;-)

# 5.004's Exporter doesn't have export_to_level.
sub _export_to_level
{
      my $pkg = shift;
      my $level = shift;
      (undef) = shift;                  # XXX redundant arg
      my $callpkg = caller($level);
      $pkg->export($callpkg, @_);
}

sub import {
    my $class = shift;
    my(@plan) = @_;

    my $caller = caller;

    $t->exported_to($caller);
    $t->plan(@plan);

    my @imports = ();
    foreach my $idx (0..$#plan) {
        if( $plan[$idx] eq 'import' ) {
            @imports = @{$plan[$idx+1]};
            last;
        }
    }

    __PACKAGE__->_export_to_level(1, __PACKAGE__, @imports);
}

###
# set up file handles
###

# create some private file handles
my $output_handle = gensym;
my $error_handle  = gensym;

# and tie them to this package
my $out = tie *$output_handle, "Test::Tester::Tie", "STDOUT";
my $err = tie *$error_handle,  "Test::Tester::Tie", "STDERR";

####
# exported functions
####

# for remembering that we're testing and where we're testing at
my $testing = 0;
my $testing_num;

# remembering where the file handles were originally connected
my $original_output_handle;
my $original_failure_handle;
my $original_todo_handle;

# function that starts testing and redirects the filehandles for now
sub _start_testing
{
    # remember what the handles were set to
    $original_output_handle  = $t->output();
    $original_failure_handle = $t->failure_output();
    $original_todo_handle    = $t->todo_output();

    # switch out to our own handles
    $t->output($output_handle);
    $t->failure_output($error_handle);
    $t->todo_output($error_handle);

    # clear the expected list
    $out->reset();
    $err->reset();

    # remeber that we're testing
    $testing = 1;
    $testing_num = $t->current_test;
    $t->current_test(0);

    # look, we shouldn't do the ending stuff
    $t->no_ending(1);
}

=head2 Methods

These are the six methods that are exported as default.

=over 4

=item test_out

=item test_err

Procedures for predeclaring the output that your test suite is
expected to produce until test_test is called.  These procedures
automatically assume that each line terminates with "\n".  So

   test_out("ok 1","ok 2");

is the same as

   test_out("ok 1\nok 2");

which is even the same as

   test_out("ok 1");
   test_out("ok 2");

Once test_out, test_err, test_fail or test_diag have been called all
output from Test::Builder will be captured by Test::Builder::Tester.
This means that your will not be able perform further tests to the
normal output in the normal way until you call test_test (well, unless
you manually meddle with the output filehandles)

=cut

sub test_out(@)
{
    # do we need to do any setup?
    _start_testing() unless $testing;

    $out->expect(@_)
}

sub test_err(@)
{
    # do we need to do any setup?
    _start_testing() unless $testing;

    $err->expect(@_)
}

=item test_fail

Because the standard failure message that Test::Builder produces
whenever a test fails will be a common occurrence in your test error
output, rather than forcing you to call test_err with the string
all the time like so

    test_err("#     Failed test ($0 at line ".line_num(+1).")");

test_fail exists as a convenience method that can be called instead.
It takes one argument, the offset from the current line that the
line that causes the fail is on.

    test_fail(+1);

This means that the example in the synopsis could be rewritten
more simply as:

   test_out("not ok 1 - foo");
   test_fail(+1);
   fail("foo");
   test_test("fail works");

=cut

sub test_fail
{
    # do we need to do any setup?
    _start_testing() unless $testing;

    # work out what line we should be on
    my ($package, $filename, $line) = caller;
    $line = $line + (shift() || 0); # prevent warnings

    # expect that on stderr
    $err->expect("#     Failed test ($0 at line $line)");
}

=item test_diag

As most of your output to the error stream will be performed by
Test::Builder's diag function which prepends comment hashes and
spacing to the start of the output Test::Builder::Tester provides
the test_diag function that auotmatically adds the output onto
the front.  So instead of writing

   test_err("#     Couldn't open file");

you can write

   test_diag("Couldn't open file");

Remember that Test::Builder's diag function will not add newlines to
the end of output and test_diag will. So to check

   Test::Builder->new->diag("foo\n","bar\n");

You would do

  test_diag("foo","bar")

without the newlines.

=cut

sub test_diag
{
    # do we need to do any setup?
    _start_testing() unless $testing;

    # expect the same thing, but prepended with "#     "
    local $_;
    $err->expect(map {"#     $_"} @_)
}

=item test_test

Actually performs the output check testing the tests, comparing the
data (with 'eq') that we have captured from Test::Builder against that
that was declared with test_out and test_err.

Optionally takes a name for the test as its only argument.

Once test_test has been run test output will be redirected back to
the original filehandles that Test::Builder was connected to (probably
STDOUT and STDERR)

=cut

sub test_test(;$)
{
    my $mess = shift;

    # er, are we testing?
    croak "Not testing.  You must declare output with a test function first."
	unless $testing;

    # okay, reconnect the test suite back to the saved handles
    $t->output($original_output_handle);
    $t->failure_output($original_failure_handle);
    $t->todo_output($original_todo_handle);

    # restore the test no, etc, back to the original point
    $t->current_test($testing_num);
    $testing = 0;

    # check the output we've stashed
    unless ($t->ok(($out->check && $err->check), $mess))
    {
      # print out the diagnostic information about why this
      # test failed

      local $_;

      $t->diag(map {"$_\n"} $out->complaint)
	unless $out->check;

      $t->diag(map {"$_\n"} $err->complaint)
	unless $err->check;
    }
}

=item line_num

A utility function that returns the line number that the function was
called on.  You can pass it an offset which will be added to the
result.  This is very useful for working out what the correct
diagnostic methods should contain when they mention line numbers.

=cut

sub line_num
{
    my ($package, $filename, $line) = caller;
    return $line + (shift() || 0); # prevent warnings
}

=back

In addition there exists one function that is not exported.

=item color

When test_test is called and the output that your tests generate does
not match that which you declared, test_test will print out debug
information showing the two conflicting versions.  As this output
itself is debug information it can be confusing which part of the output
is from test_test and which is from your original tests.

To assist you, if you have the Term::ANSIColor module installed
(which you will do by default on perl 5.005 onwards), test_test can
use colour to disambiguate the different types of output.  This
will cause the output that was originally from the tests you are
testing to be coloured green and red.  The green part represents the
text which is the same between the executed and actual output, the
red shows which part differs.

The color function determines if colouring should occur or not.
Passing it a true or false value will enable and disable colouring
respectively, and the function called with no argument will return the
current setting.

To enable colouring from the command line, you can use the
Text::Builder::Tester::Color module like so:

   perl -Mlib=Text::Builder::Tester::Color test.t

=cut

my $color;
sub color
{
  $color = shift if @_;
  $color;
}

=head1 BUGS

Calls Test::Builder's no_ending method turning off the ending tests.
This is needed as otherwise it will trip out because we've run more
tests than we strictly should have and it'll register any failures we
had that we were testing for as real failures.

The color function doesn't work unless Term::ANSIColor is installed
and is compatible with your terminal.

=head1 AUTHOR

Copyright Mark Fowler E<lt>mark@twoshortplanks.comE<gt> 2002.

Some code taken from Test::More and Test::Catch, written by by Michael
G Schwern E<lt>schwern@pobox.comE<gt>.  Hence, those parts Copyright
Micheal G Schwern 2001.  Used and distributed with permission.

This program is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Test::Builder>, L<Test::Builder::Tester::Color>, L<Test::More>.

=cut

1;

####################################################################
# Helper class that is used to remember expected and received data

package Test::Tester::Tie;

##
# add line(s) to be expected

sub expect
{
    my $self = shift;
    $self->[2] .= join '', map { "$_\n" } @_;
}

##
# return true iff the expected data matches the got data

sub check
{
    my $self = shift;

    # turn off warnings as these might be undef
    local $^W = 0;

    $self->[1] eq $self->[2];
}

##
# a complaint message about the inputs not matching (to be
# used for debugging messages)

sub complaint
{
    my $self = shift;
    my ($type, $got, $wanted) = @$self;

    my $green = "";
    my $reset = "";

    # are we running in colour mode?
    if (Test::Builder::Tester::color)
    {
      # get color
      eval "require Term::ANSIColor";
      unless ($@)
      {
	$green  = Term::ANSIColor::color("green");
	$reset  = Term::ANSIColor::color("reset");
        my $red = Term::ANSIColor::color("red");

	# work out where the two strings start to differ
	my $char = 0;
	$char++ while substr($got, $char, 1) eq substr($wanted, $char, 1);

	# now insert red colouring escape where the differences start
	substr($got,    $char, 0, $red);
	substr($wanted, $char, 0, $red);
      }
    }

    return "$type is '$green$got$reset' not '$green$wanted$reset' as expected"
}

##
# forget all expected and got data

sub reset
{
    my $self = shift;
    @$self = ($self->[0]);
}

###
# tie interface
###

sub PRINT  {
    my $self = shift;
    $self->[1] .= join '', @_;
}

sub TIEHANDLE {
    my $class = shift;
    my $self = [shift()];
    return bless $self, $class;
}

sub READ {}
sub READLINE {}
sub GETC {}
sub FILENO {}

1;
