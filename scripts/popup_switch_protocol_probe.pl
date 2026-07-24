#!/usr/bin/perl

use strict;
use warnings;

use Errno qw(EINTR);
use File::Temp qw(tempfile);
use POSIX qw(setpgid);
use Time::HiRes qw(alarm);

my $EXPECTED_PROTOCOL = "barista-popup-switch-v1\n";
my $TIMEOUT_SECONDS = 0.25;

my $helper = shift @ARGV;
exit 2 if !defined($helper) || @ARGV || !-x $helper;

my ($capture) = tempfile("barista-popup-switch-probe-XXXXXX", TMPDIR => 1, UNLINK => 1);
my $pid = fork();
exit 1 if !defined($pid);

if ($pid == 0) {
    # Establish the process group before the helper can create descendants.
    setpgid(0, 0) == 0 or POSIX::_exit(125);
    open(STDOUT, ">&", $capture) or POSIX::_exit(126);
    open(STDERR, ">", "/dev/null") or POSIX::_exit(126);
    exec {$helper} $helper, "protocol" or POSIX::_exit(127);
}

# This closes the small race before the child establishes its own group.
eval { setpgid($pid, $pid) };

my $timed_out = 0;
local $SIG{ALRM} = sub {
    $timed_out = 1;
    kill "KILL", -$pid;
    kill "KILL", $pid;
};

alarm($TIMEOUT_SECONDS);
my $waited;
while (1) {
    $waited = waitpid($pid, 0);
    last if $waited == $pid;
    next if $waited == -1 && $! == EINTR;
    last;
}
my $status = $?;
alarm(0);

# Remove any descendants left by a helper that exited before them.
kill "KILL", -$pid;

exit 124 if $timed_out;
exit 1 if $waited != $pid || $status != 0;

seek($capture, 0, 0) or exit 1;
local $/;
my $output = <$capture>;
exit 0 if defined($output) && $output eq $EXPECTED_PROTOCOL;
exit 1;
