# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

BEGIN {
    sub catch_int {
	exit;
    }
$SIG{INT} = \&catch_int;
$| = 1; print "1..14\n";
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
    tie($scalar, IPC::Shareable, 'data', { 'create' => 'yes', 'destroy' => 'no' })
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

# --- Fragmentation
$ok = 1;
++$number;
$pid = fork;
defined $pid or die $!;
$SIG{'ALRM'} = sub { 1; };
$shm_bufsiz = &IPC::Shareable::SHM_BUFSIZ;
if ($pid == 0) {
    # --- Child
    sleep; # - To ensure parent process creates the binding first
    tie($long_scalar, IPC::Shareable, 'zata', { 'create' => 'yes', 'destroy' => 'no' })
	or die "child process can't tie \$long_scalar";
    $long_scalar = 'foo' x ($shm_bufsiz * 3); # - Lots of data
    exit;
} else {
    # --- Parent
    tie($long_scalar, IPC::Shareable, 'zata', { 'create' => 'yes', 'destroy' => 'yes' })
	or die "parent process can't tie \$long_scalar";
    sleep 2; # - Makes sure the following alarm doesn't ring to soon
    kill $signo{ALRM}, $pid; # - Wake up the child process
    wait;
    $long_scalar eq ('foo' x ($shm_bufsiz * 3)) or
	undef $ok;
    print $ok ? "ok $number\n" : "not ok $number\n";
    untie $long_scalar;
}

# --- Test locking
$ok = 1;
++$number;
$pid = fork;
defined $pid or die $|;
if ($pid == 0) {
    # --- Child
    sleep; # - To ensure parent process creates the binding first
    tie($scalar, IPC::Shareable, 'data', { 'create' => 'yes', 'destroy' => 'no' })
	or die "child process can't tie \$scalar";
    for $i (0 .. 99) {
  	(tied $scalar)->shlock;
	++$scalar;
	(tied $scalar)->shunlock;
    }
    exit;
} else {
    # --- Parent
    tie($scalar, IPC::Shareable, 'data', { 'create' => 'yes', 'destroy' => 'yes' })
	or die "parent process can't tie \$scalar";
    $scalar = 0;
    sleep 2; # - Makes sure the following alarm doesn't ring to soon
    kill $signo{ALRM}, $pid; # - Wake up the child process
    for $i (0 .. 99) {
	(tied $scalar)->shlock;
	++$scalar;
	(tied $scalar)->shunlock;
    }
    wait;
    ($scalar == 200)
	or undef $ok;
    print $ok ? "ok $number\n" : "not ok $number\n";
    untie $scalar;
}

# --- Test magical tying of referenced thingies
$ok = 1;
++$number;
$pid = fork;
defined $pid or die $!;
if ($pid == 0) {
    # --- Child
    sleep 3;
    tie($hash_ref, IPC::Shareable, 'data', { 'create' => 'yes', 'destroy' => 'no' })
	or undef $ok;
    # --- Assign some stuff.  These operations are completely non-atomic, so we
    # --- need to lock
    (tied $hash_ref)->shlock;
    $hash_ref->{'blip'}{'blarp'} = 'blurp';
    $hash_ref->{'flip'}{'flop'} = 'flurp';
    (tied $hash_ref)->shunlock;
    $hash_ref->{'blip'}{'blarp'} eq 'blurp' or
	undef $ok;
    $hash_ref->{'flip'}{'flop'} eq 'flurp' or
	undef $ok;
    print $ok ? "ok $number\n" : "not ok $number\n";
    exit;
} else {
    # --- Parent
    tie($hash_ref, IPC::Shareable, 'data', { 'create' => 'yes', 'destroy' => 'yes' })
	or undef $ok;
    $hash_ref = {};
    wait;
    $hash_ref->{'blip'}{'blarp'} eq 'blurp' or
	undef $ok;
    $hash_ref->{'flip'}{'flop'} eq 'flurp' or
	undef $ok;
    ++$number; # - Child performed a test
    print $ok ? "ok $number\n" : "not ok $number\n";
    untie $hash_ref;
}

# --- Done!
exit;
