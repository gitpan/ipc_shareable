# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

BEGIN {
    sub catch_int {
	exit;
    }
$SIG{INT} = \&catch_int;
$| = 1; print "1..11\n";
}
END {print "not ok 1\n" unless $loaded;}
use IPC::Shareable;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

use Config;
defined $Config{sig_name} or
    die "No sigs?";
foreach $name (split(' ', $Config{sig_name})) {
    $signo{$name} = $i;
    $signame[$i] = $name;
    $i++;
}
# --- Tie a scalar variable
$scalar = 'bar';
$ok = 1;
$number = 1;
++$number;
tie($scalar, IPC::Shareable, { 'destroy' => 'yes' })
    or undef $ok;
print $ok ? "ok $number\n" : "not ok $number\n";

# --- Assign a value
++$number;
$ok = 1;
$scalar = 'foo';
($scalar eq 'foo') or undef $ok;
print $ok ? "ok $number\n" : "not ok $number\n";
untie $scalar;

# --- Tie a hash
++$number;
$ok = 1;
tie(%hash, IPC::Shareable, { 'destroy' => 'yes' })
    or undef $ok;
print $ok ? "ok $number\n" : "not ok $number\n";

# --- Assign a few values
++$number;
$ok = 1;
srand;
for ($i = 0; $i < 10; ++$i) {
    my $key, $value;
    for (0 .. 9) {
	$key .= (a .. z)[int(rand(26))];
	$value .= (A .. Z)[int(rand(26))];
    }
    $check{$key} = $value;
    $hash{$key} = $value;
}
while (($key, $value) = each %check) {
    $check{$key} eq $hash{$key} or
	undef $ok;
}
print $ok ? "ok $number\n" : "not ok $number\n";
untie %hash;

# --- References: array refs
++$number;
$ok = 1;
tie($scalar, IPC::Shareable, { 'destroy' => 'yes' })
    or undef $ok;
$scalar = [ 0 .. 9 ];
for (0 .. 9) {
    ($$scalar[$_] eq $_)
	or undef $ok;
}
print $ok ? "ok $number\n" : "not ok $number\n";
untie $scalar;

# --- References: hash refs
++$number;
$ok = 1;
tie($scalar, IPC::Shareable, { 'destroy' => 'yes' })
    or undef $ok;
$scalar = { %check };
for (keys %check) {
    $$scalar{$_} eq $check{$_}
	or undef $ok;
}
print $ok ? "ok $number\n" : "not ok $number\n";
untie $scalar;


# --- Now try some real IPC
$ok = 1;
++$number;
$SIG{'CHLD'} = 'IGNORE';
$pid = fork;
defined $pid or die $!;
if ($pid == 0) {
    # --- Child
    sleep 3;
    tie($scalar, IPC::Shareable, 'data', { 'create' => 'no', 'destroy' => 'no' })
	or undef $ok;
    # --- Retrieve the value
    $scalar eq 'bar' or
	undef $ok;
    print $ok ? "ok $number\n" : "not ok $number\n";
    # --- Change the value
    ++$number;
    $ok = 1;
    $scalar = 'foo';
    $scalar eq 'foo' or
	undef $ok;
    print $ok ? "ok $number\n" : "not ok $number\n";
    exit;
} else {
    # --- Parent
    tie($scalar, IPC::Shareable, 'data', { 'create' => 'yes', 'destroy' => 'yes' })
	or undef $ok;
    $scalar = 'bar';
    # --- Wait for the value to change
    sleep 1 while $scalar eq 'bar';
    wait;
    $scalar eq 'foo' or
	undef $ok;
    $number += 2; # - Child performed two tests.
    print $ok ? "ok $number\n" : "not ok $number\n";
}
untie $scalar;

# --- Now that (minimal) IPC is working, we use it to keep
# --- track of the test number in the future

# --- Test fragmentation
#$IPC::Shareable::Debug = 1;
$ok = 1;
++$number;
$pid = fork;
defined $pid or die $!;
$SIG{'ALRM'} = \&wake_up;
sub wakeup {
    1;
}
$shm_bufsiz = &IPC::Shareable::SHM_BUFSIZ;
if ($pid == 0) {
    # --- Child
    sleep; # - To ensure parent process creates the binding first
    tie($ipc_test_number, IPC::Shareable, 't_no', { 'create' => 'no', 'destroy' => 'no' })
	or die "child process can't tie test number";
    tie($long_scalar, IPC::Shareable, 'data', { 'create' => 'no', 'destroy' => 'no' })
	or die "child process can't tie \$long scalar";
    $long_scalar = 'foo' x ($shm_bufsiz * 3); # - Lots of data
    exit;
} else {
    # --- Parent
    tie($ipc_test_number, IPC::Shareable, 't_no', { 'create' => 'yes', 'destroy' => 'yes' })
	or die "parent process can't tie test number";
    tie($long_scalar, IPC::Shareable, 'data', { 'create' => 'yes', 'destroy' => 'yes' })
	or die "parent process can't tie \$long scalar";
    $ipc_test_number = $number;
    ++$ipc_test_number;
    sleep 2; # - Makes sure the following alarm doesn't ring to soon
    kill $signo{ALRM}, $pid; # - Wake up the child process
    wait;
    $long_scalar eq ('foo' x ($shm_bufsiz * 3)) or
	undef $ok;
    print $ok ? "ok $number\n" : "not ok $number\n";
}

# --- Other tests to be added soon


exit;


