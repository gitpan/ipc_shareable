package IPC::Shareable;

# --- Class used to tie variables to shared memory

# --- Library requirements
use strict;
use Carp;
use Storable qw(freeze thaw);
use vars qw($VERSION $AUTOLOAD
	    @ISA @EXPORT_OK
	    %EXPORT_TAGS %Shm_Info
	    $Package $Debug
	    );
use subs qw(IPC_CREAT IPC_EXCL IPC_RMID IPC_STAT IPC_PRIVATE
	    SHM_BUFSIZ SHM_HEADSIZE SHM_FOOTSIZE
	    SHM_VERSSEM SHM_RLOCKSEM SHM_WLOCKSEM
	    GETVAL SETVAL GETALL
	    debug parse_argument_hash
	    tie_to_shm read_shm_variable
	    write_shm_variable read_shm_header
	    write_shm_header read_shm_footer
	    write_shm_footer
	    );
require DynaLoader;

# --- Classes to inherit methods from
@ISA = qw(DynaLoader);

# --- Package globals
$VERSION = '0.16';
$Package = 'IPC::Shareable';
$Debug = ($Debug or undef);

# --- The Autoload method as created by h2xs
sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.  If a constant is not found then control is passed
    # to the AUTOLOAD in AutoLoader.

    my $constname;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    my $val = constant($constname, @_ ? $_[0] : 0);
    if ($! != 0) {
	if ($! =~ /Invalid/) {
	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
	}
	else {
		croak "Your vendor has not defined IPC::Shareable macro $constname";
	}
    }
    eval "sub $AUTOLOAD { $val }";
    goto &$AUTOLOAD;
}

# --- Subroutines that define constants
sub SHM_BUFSIZ {
    65536;
}

sub SHM_HEADSIZE {
    4;
}

sub SHM_FOOTSIZE {
    4;
}

sub SHM_VERSSEM {
    0;
}

sub SHM_RLOCKSEM {
    1;
}

sub SHM_WLOCKSEM {
    2;
}

# --- Pull other constants into Perl
bootstrap IPC::Shareable $VERSION;

package IPC::Shareable;

# --------------------------------------------------------------------------------
# --- Preloaded methods common to all variable types
# --------------------------------------------------------------------------------
sub FETCH {
    # --- Used when a variable is being retrieved.  First it checks the version, to
    # --- see if the variable has changed.  If the variable has not changed, the
    # --- cached value is returned.  If the variable has changed, its current
    # --- value is retrieved and the cache is updated.
    my($variable, @args) = @_;
    my($data_ref, $key, $type, $semid, $arg);
    my($their_version, $our_version);
    debug "$Package\:\:FETCH: fetching $variable";
    $type = $Shm_Info{$$variable}{'type'};

    # --- Check the cache first; Get the sem_id
    $semid = $Shm_Info{$$variable}{'sem_id'};

    # --- Get the public version number
    $arg = 0;
    $their_version = semctl($semid, SHM_VERSSEM, GETVAL, $arg);
    defined $their_version or
	croak "$Package\:\:FETCH: semctl returned undef";
    debug "$Package\:\:FETCH: public version number is $their_version";

    # --- Get our version number
    $our_version = $Shm_Info{$$variable}{'version'};
    debug "$Package\:\:FETCH: private version number is $our_version";

    # --- Just use our cached value if the version is the same
    if ($their_version eq $our_version) {
	debug "$Package\:\:FETCH: returning value for $variable ($$variable) from local cache";
    } else  {
	# --- Retrieve the proper value
	$Shm_Info{$$variable}{'DATA'} = read_shm_variable($variable);

	# --- Update our local version number
	$Shm_Info{$$variable}{'version'} = $their_version;
    }

    # --- Dereference in the appropriate manner, and return
    TYPE: {
	if ($type eq 'SCALAR') {
	    debug "$Package\:\:FETCH: $variable is indeed a SCALAR";
	    return ${$Shm_Info{$$variable}{'DATA'}};
	}
	if ($type eq 'HASH') {
	    debug "$Package\:\:FETCH: $variable is indeed a HASH";
	    ($key) = (@args);
	    if (defined $key) {
		return $Shm_Info{$$variable}{'DATA'}{$key};
	    } else {
		return $key;
	    }
	}
	croak "$Package\:\:FETCH: not implemented";
    }
}

sub STORE {
    # --- Used for all data types
    my($variable, @args) = @_;
    my($key, $value, $type, $semid, $arg, $version, $opstring);
    debug "$Package\:\:STORE: storing $variable, @args";

    # --- Update our local cache (note we can't ref($variable) to get its type
    # --- since it's been blessed
    $type = $Shm_Info{$$variable}{'type'};
    debug "$Package\:\:STORE: $variable is a $type";
  TYPE: {
      if ($type eq 'SCALAR') {
	  # --- Here we don't care what the other version is since we're completely
	  # --- overwriting any existing value with our value
	  ($value) = @args;
	  $Shm_Info{$$variable}{'DATA'} = \$value;
	  last TYPE;
      }
      if ($type eq 'HASH') {
	  # --- If the user appears to be in the middle of some kind of iteration
	  # --- we update the local cache only and return immediately
	  if ($Shm_Info{$$variable}{'hash_iterating'}) {
	      $Shm_Info{$$variable}{'DATA'}{$key} = $value;
	  }

	  # --- Now we make our change.  If $key was supplied, we assume that we're
	  # --- making an incremental change and our value is simply merged with
	  # --- any existing values.  If $key was not supplied, we assume
	  # --- that a wholesale change is being made and our (cached) hash represents
	  # --- the authoritative record.
	  ($key, $value) = @args;
	  if (defined $key) {
	      debug "$Package\:\:STORE: making incremental change to HASH";
	      # --- Incremental change: fetch the most recent public version.
	      FETCH($variable);
	      $Shm_Info{$$variable}{'DATA'}{$key} = $value;
	  } else {
	      debug "$Package\:\:STORE: making wholesale change to HASH";
	      # --- Wholesale change; ignore any existing public version.
	      1;
	  }
	  last TYPE;
      }
      croak "not implemented";
  }
    
    # --- Write it to shared memory
    write_shm_variable($variable, $Shm_Info{$$variable}{'DATA'});

    # --- Update the version number
    $semid = $Shm_Info{$$variable}{'sem_id'};

    # --- Diagnostic
    $arg = 0; # :-(
    $version = semctl($semid, 0, GETVAL, $arg);
    debug "Package\:\:STORE: previous version number was $version";

    # --- Increment it
    $opstring = pack('sss', SHM_VERSSEM, 1, 0);
    semop($semid, $opstring) or
	croak "Package\:\:STORE: semop returned false";
	
    # --- Diagnostic
    $version = semctl($semid, 0, GETVAL, $arg);
    debug "Package\:\:STORE: new version number is $version";
    $Shm_Info{$$variable}{'version'} = $version;

    # --- Done
    return $value;
}

sub DESTROY {
    # --- Runs when a tied variable is about to be wiped out...
    # --- so long as 'destroy' was specified upon creation
    my($variable) = @_;
    my($argument, $shmid, $fragment, $semid);
    my(@shmids, @fragments);
    
    $argument = 0;
    debug "$Package\:\:DESTROY called on $variable";
    $Shm_Info{$$variable}{'destroy'} or return;

    # --- Smoke first all associated shm fragments
    @fragments = keys %{$Shm_Info{$$variable}{'frag_id'}};
    foreach $fragment (@fragments) {
	$shmid = $Shm_Info{$$variable}{'frag_id'}{$fragment};
	debug "$Package\:\:DESTROY: calling shmctl($shmid, IPC_RMID, $argument)";
	shmctl($shmid, IPC_RMID, $argument);
    }

    # --- Now smoke the associated semaphore
    $semid = $Shm_Info{$$variable}{'sem_id'};
    debug "$Package\:\:DESTROY: calling semctl($semid, 0, IPC_RMID, $argument)";
    semctl($semid, 0, IPC_RMID, $argument);
}

sub debug {
    # --- Used for debugging
    my(@complaints) = @_;
    my($package, $line);
    ($package, undef, $line) = caller;
    warn "$package: $line: ", @complaints if $Debug;
}

sub parse_argument_hash {
    # --- Parses the anonymous hash passed to constructors; returns a list
    # --- of args suitable for passing to shmget
    my($arguments) = @_;
    my($key, $create, $exclusive, $mode, $flags, $size, $destroy);
    my($shm_header);
    my(%shm_info);

    # --- Make sure we're not being spoofed
    return unless ref $arguments eq 'HASH';

    # --- Check the key
    $key = ($$arguments{'key'} or IPC_PRIVATE);
    if ($key =~ /^\d+$/) {
	# --- $key is numeric; take as is
	debug "$Package\:\:parse_argument_hash: $key is numeric";
    } else {
	# --- create a numeric key; THIS ONLY USES THE FIRST FOUR CHARACTERS!!!!
	debug "$Package\:\:parse_argument_hash: $key is alphabetic";
	$key = pack('A4', $key);
	$key = unpack('i', $key);
	debug "$Package\:\:parse_argument_hash: \$key is now $key";
    }
    $shm_info{'key'} = $key;

    # --- Determine whether to create a new segment or not
    $create = $$arguments{'create'};
    if ($create =~ /^no$/i) {
	$create = 0;
    } elsif ($create) {
	$create = IPC_CREAT;
    } else {
	$create = 0;
    }
    debug "$Package\:\:parse_argument_hash: \$create is $create"; 

    # --- Determine whether they want an exclusive one or not
    $exclusive = $$arguments{'exclusive'};
    if ($exclusive =~ /^no$/i) {
	$exclusive = 0;
    } elsif ($exclusive) {
	$exclusive = IPC_EXCL;
    } else {
	$exclusive = 0;
    }
    debug "$Package\:\:parse_argument_hash: \$exclusive is $exclusive";

    # --- Get the access modes they want
    $mode = ($$arguments{'mode'} or 0666); # - At some point, add a hook to accept symbolic values
    
    # --- Create the flags argument
    $flags = $exclusive|$create|$mode;
    $shm_info{'flags'} = $flags;

    # --- Determine whether the segment is to be destroyed upon exit
    $destroy = ($$arguments{'destroy'} or '');
    if ($destroy =~ /^no$/i) {
	undef $destroy;
    } elsif ($destroy) {
	$destroy = $destroy; # :-)
    } else {
	undef $destroy;
    }
    debug "$Package\:\:parse_argument_hash: \$destroy is $destroy" if $destroy;
    $shm_info{'destroy'} = $destroy;

    # --- Return the desired values
    return \%shm_info;
}

sub tie_to_shm {
    # --- Common logic for all data types during the construction process
    my($type, $arg1, $other_args) = @_;
    my($shm_info, $shmid, $shm_header, $semid, $semnum, $arg, $version);
    my($opstring, $data, $length, $read_lock, $write_lock, $key, $value);
    my $empty = '';
    my %empty = ();

    # --- Parse the arguments
    if (ref $arg1 eq 'HASH') {
	# --- They've passed arguments as a hash
	$shm_info = parse_argument_hash($arg1) or return;
    } elsif (ref $other_args eq 'HASH') {
	# --- The first arg is assumed to be glue; options come in %$other_args
	$$other_args{'key'} = $arg1;
	$shm_info = parse_argument_hash($other_args) or return;
    } elsif (defined $arg1 and not defined $other_args) {
	# --- They've passed no %options hash ref; create one
	$other_args = { 'key' => $arg1 };
	$shm_info = parse_argument_hash($other_args) or return;
    } elsif (not defined $arg1 and not defined $other_args) {
	# --- No arguments whatsoever
	$other_args = { 'key' => 0 };
	$shm_info = parse_argument_hash($other_args) or return
    } else {
	# --- At some point I plan to let people pass arguments like key, IPC_CREATE|PERMS...
	# --- but not yet
	carp "not implemented";
	return;
    }

    # --- Now get the shared memory id
    debug "$Package\:\:tie_to_shm: calling shmget($$shm_info{'key'}, SHM_BUFSIZ, $$shm_info{'flags'})";
    $shmid = shmget($$shm_info{'key'}, SHM_BUFSIZ, $$shm_info{'flags'});
    defined $shmid or return;
    debug "$Package\:\:tie_to_shm: got \$shmid of $shmid";

    # --- Create the semaphore flags we'll use for locking and version control
    debug "$Package\:\:tie_to_shm: calling semget($$shm_info{'key'}, 3, $$shm_info{'flags'})";
    $semid= semget($$shm_info{'key'}, 3, $$shm_info{'flags'});
    defined $semid or return;
    debug "$Package\:\:tie_to_shm: semid associated with $shmid is $semid";
    $Shm_Info{$shmid}{'sem_id'} = $semid;

    # --- Get (or create) the version number
    $arg = 0; # - Not used for anything but Perl complains if I don't have it
    $version = semctl($semid, 0, GETVAL, $arg);
    defined $version or
	croak "$Package\:\:tie_to_shm: semctl returned undef";
    $version =~ tr/0-9//cd; # - semctl returns '0 but true' if the C function returns (int) 0.
    debug "$Package\:\:tie_to_shm: version number is $version";
    if ($version == 0) {
	# --- Must be the first version of this variable; set version number to 1
	debug "$Package\:\:tie_to_shm: creating initial version of $shmid";
	debug "$Package\:\:tie_to_shm: setting read/write lock semaphores to 1";
	$opstring = pack('sss sss sss',
			 SHM_VERSSEM,  1, 0,
			 SHM_RLOCKSEM, 1, 0,
			 SHM_WLOCKSEM, 1, 0);
	semop($semid, $opstring) or
	    croak "$Package\:\:tie_to_shm: return false";
	# --- Initialize the variable to be empty at first
	if ($type eq 'SCALAR') {
	    $Shm_Info{$shmid}{'DATA'} = \$empty;
	    write_shm_variable(\$shmid, $Shm_Info{$shmid}{'DATA'});
	} else {
	    $Shm_Info{$shmid}{'DATA'} = { %empty };
	    write_shm_variable(\$shmid, $Shm_Info{$shmid}{'DATA'});
	}
    } else {
	# --- This variable must exist already
	# --- Fill the cache with the current contents of the variable
	debug "$Package\:\:tie_to_shm: retrieving public version of $shmid";
	$Shm_Info{$shmid}{'DATA'} = read_shm_variable(\$shmid);
    }

    # --- Confirm the version number
    $version = semctl($semid, SHM_VERSSEM, GETVAL, $arg);
    defined $version or
	croak "$Package\:\:tie_to_shm: semctl returned undef\n";

    # --- Diagnostics
    if ($Debug) {
	$read_lock = semctl($semid, SHM_RLOCKSEM, GETVAL, $arg);
	$write_lock = semctl($semid, SHM_WLOCKSEM, GETVAL, $arg);
	debug "$Package\:\:tie_to_shm: revised version number is $version";
	defined $read_lock or
	    croak "$Package\:\:tie_to_shm: semctl returned undef\n";
	debug "$Package\:\:tie_to_shm: read lock is $read_lock";
	defined $write_lock or
	    croak "$Package\:\:tie_to_shm: semctl returned undef\n";
	debug "$Package\:\:tie_to_shm: write lock is $write_lock";
    }
    
    # --- Store the info
    while (($key, $value) = each %$shm_info) {
	$Shm_Info{$shmid}{$key} = $value;
    }
    $Shm_Info{$shmid}{'frag_id'}{'0'} = $shmid;
    $Shm_Info{$shmid}{'type'} = $type;
    $Shm_Info{$shmid}{'version'} = $version;

    # --- Done
    return $shmid;
}

sub read_shm_variable {
    # --- Reads a variable from shared memory segments.  Waits until the write
    # --- lock has clear on a variable.
    my($shmid) = @_;
    my($frag_id, $length, $frag, $frag_size, $data, $frag_count);
    my($next_frag_id, $more_frags, $semid, $opstring);
    debug "$Package\:\:read_shm_variable called on $shmid";

    # --- Determine the length of the data area (same for all fragments)
    $frag_size = (SHM_BUFSIZ) - (SHM_HEADSIZE) - (SHM_FOOTSIZE);
    debug "$Package\:\:read_shm_variable: each fragment is $frag_size bytes max";

    # --- Get the id of the first fragment
    $frag_id = $$shmid;
    debug "$Package\:\:read_shm_variable: first fragment is $frag_id";
    $data = '';
    $frag_count = 0;

    # --- Wait on the write-lock semaphore
    $semid = $Shm_Info{$$shmid}{'sem_id'};
    debug "$Package\:\:read_shm_variable: \$semid is $semid";
    $opstring = pack('sss', SHM_WLOCKSEM, -1, 0);
    semop($semid, $opstring) or
	croak "$Package\:\:read_shm_variable: semop returned false";

    # --- Loop through until we get to the end of the data
  READ: while (1) {
      
      # --- Read the header
      $length = read_shm_header($frag_id);
      debug "$Package\:\:read_shm_variable: length of $shmid/$frag_id is $length";

      # --- If length is greater than the threshold, it indicates there are more fragments to come
      undef $more_frags;
      if ($length > $frag_size) {
	  $more_frags = 1;
	  $length = $frag_size;
      }

      # --- Read the data
      $frag = '';
      shmread($frag_id, $frag, SHM_HEADSIZE, $length) or
	  croak "$Package\:\:read_shm_variable: shmread returned false";
      debug "$Package\:\:read_shm_variable: read $length bytes from $shmid/$frag_id";

      # --- Concatenate the data
      $data .= $frag;

      # --- This assumed to be the last fragment if it's not complete
      last READ unless $more_frags;

      # --- There must be more fragments
      $next_frag_id = read_shm_footer($frag_id);
      debug "$Package\:\:read_shm_variable: next fragment is $next_frag_id";
      $Shm_Info{$$shmid}{'frag_id'}{$frag_count + 1} = $next_frag_id;

      # --- Increment the fragment count
      ++$frag_count;

      # --- Move onto the next fragment
      $frag_id = $next_frag_id;
  }

    # --- Release the write lock
    $opstring = pack('sss', SHM_WLOCKSEM, 1, 0);
    semop($semid, $opstring) or
	croak "$Package\:\:read_shm_variable: semop returned false";

    # --- Now turn the concatenated data into a real perl reference
    thaw($data);
}

sub write_shm_variable {
    # --- Writes a variable to shared memory segments.  Waits until all processes
    # --- have stopped reading or writing the variable.
    my($shmid, $var_ref) = @_;
    my($data, $length, $frag_num, $last_frag_length, $frag_count, $template);
    my($frag_id, $next_frag_id, $key, $flags, $header_info, $frag_size, $frag);
    my($shmctl_arg, $shmctl_return, $stale_fragment);
    my($semid, $opstring);
    my(@frags, @stale_fragments);
    debug "$Package\:\:write_shm_variable called on $shmid, $var_ref";

    # --- Serialize the data
    $data = freeze($var_ref);
    $length = length($data);
    $frag_size = (SHM_BUFSIZ) - (SHM_HEADSIZE) - (SHM_FOOTSIZE); # - Why don't bare words work here, Larry?
    debug "$Package\:\:write_shm_variable: each fragment is $frag_size bytes max";
    debug "$Package\:\:write_shm_variable: $var_ref has $length bytes of data";

    # --- Fragment the data; first get the number of fragments, less one
    $frag_num = int($length / $frag_size);
	
    # --- Get the length of the last fragment
    $last_frag_length = $length % $frag_size;
	
    # --- Create a template to split the data into the required number of fragments
    $template = "a$frag_size " x $frag_num;
    $template = "$template A$last_frag_length";
    debug "$Package\:\:write_shm_variable: unpacking $shmid into $frag_num + 1 fragments";
    debug "$Package\:\:write_shm_variable: using this template for unpacking: $template";
    @frags = unpack($template, $data);
    debug("$Package\:\:write_shm_variable: got " . @frags . " fragments");
    
    # --- Now write the data, starting from fragment 0
    $frag_count = 0;

    # --- The first fragment is always written to the first shm segment we got
    # --- for this variable, so that's we're we start writing
    $frag_id = $$shmid;

    # --- Wait on both the read and write locks
    $semid = $Shm_Info{$$shmid}{'sem_id'};
    debug "$Package\:\:write_shm_variable: got sem_id $semid";
    $opstring = pack('sss',
		     SHM_RLOCKSEM, -1, 0,
		     SHM_WLOCKSEM, -1, 0
		     );
    semop($semid, $opstring) or
	croak "$Package\:\:write_shm_variable: semop returned false";

    # --- Write each fragment in succession
    foreach $frag (@frags) {
	debug "$Package\:\:write_shm_variable: writing fragment $frag_count to shm";
	debug "$Package\:\:write_shm_variable: fragment $frag_count will reside at $frag_id";

	# --- Get the length of this fragment
	$length  = length($frag);
	debug "$Package\:\:write_shm_variable: fragment $frag_count is $length bytes long";

	# --- Write the header; if this is not the last fragment, the length is set
	# --- to greater than a fragment data area size to indicate there is more data coming
	if ($frag_count < $#frags) {
	    # --- more fragments
	    $header_info = (SHM_BUFSIZ) + 1;
	} else {
	    $header_info = $length;
	}
	write_shm_header($frag_id, $header_info);

	# --- Write the data for this fragment
	shmwrite($frag_id, $frag, SHM_HEADSIZE, $length) or
	    croak "$Package\:\:write_shm_variable: shmwrite returned false";
	debug "$Package\:\:write_shm_variable: wrote $length bytes to $frag_id";

	# --- See if we have to write another fragment, and therefore create another shmid
	if ($frag_count < $#frags) {

	    # --- See if we already know what the ID is to be
	    $next_frag_id = $Shm_Info{$$shmid}{'frag_id'}{$frag_count + 1};
	    if (not defined $next_frag_id) {
		debug "$Package\:\:write_shm_variable: getting next fragment id for fragment $frag_count";

		# --- We have to create a new shared memory segment
		$key = ($Shm_Info{$$shmid}{'key'} + $frag_count + 1);
		$flags = $Shm_Info{$$shmid}{'flags'};
		debug "$Package\:\:write_shm_variable: calling shmget($key, SHM_BUFSIZ, $flags)";
		# --- Or IPC_CREATE and IPC_EXCL into flags to make sure we get a new segment
		$flags = IPC_CREAT|$flags;
		$flags = IPC_EXCL|$flags; # - To make sure don't step on anybody else's toes
		$next_frag_id = shmget($key, SHM_BUFSIZ, $flags) or
		    croak "$Package\:\:write_shm_variable: shmget returned false";

		# --- Store the fragment ID for future use
		$Shm_Info{$$shmid}{'frag_id'}{$frag_count + 1} = $next_frag_id;
	    }
	    debug "$Package\:\:write_shm_variable: got frag_id $next_frag_id for fragment following $frag_count";

	    # --- Write the id of the next fragment as the footer
	    write_shm_footer($frag_id, $next_frag_id);

	} else {
	    # --- There is no next fragment
	    debug "$Package\:\:write_shm_variable: fragment $frag_count is last one";

	    # --- Remove any previously used fragments from shared memory
	    debug "$Package\:\:write_shm_variable: doing garbage collection on $$shmid";

	    # --- Get the list of stale fragments
	    @stale_fragments = grep(/$_ > $frag_count/, keys %{$Shm_Info{$$shmid}{'frag_id'}});

	    # --- Loop through each one and delete
	    $shmctl_arg = 0;
	    foreach $stale_fragment (@stale_fragments) {

		# --- Get the shmid for this piece of garbage
		debug "$Package\:\:write_shm_variable: fragment $stale_fragment no longer needed";
		$frag_id = $Shm_Info{$$shmid}{'frag_id'}{$stale_fragment};

		# --- Remove from shared memory
		$shmctl_return = shmctl($frag_id, IPC_RMID, $shmctl_arg);
		defined $shmctl_return or
		    croak "$Package\:\:write_shm_variable: shmctl returned undefined when removing $frag_id";

		# --- Remove from the local cache
		delete $Shm_Info{$$shmid}{'frag_id'}{$stale_fragment};
	    }
	}
	
	# --- Increment the fragment count
	++$frag_count;
	$frag_id = $next_frag_id;
    }

    # --- Unlock the variable
    $opstring = pack('sss',
		     SHM_RLOCKSEM, 1, 0,
		     SHM_WLOCKSEM, 1, 0
		     );
    semop($semid, $opstring) or
	croak "$Package\:\:write_shm_variable: semop returned false";

    1;
}
		  

sub read_shm_header {
    # --- Reads the (minimal) shm header that we put into each shm segment
    # --- Returns the unencoded header; currently this value indicates the
    # --- the length of the data
    my($shmid) = @_;
    my $shm_header = '';
    debug "$Package\:\:read_shm_header called on $shmid";

    # --- Read the shm header
    shmread($shmid, $shm_header, 0, SHM_HEADSIZE) or
	croak "$Package\:\:read_shm_header: shmread returned false ($!)";
    debug "$Package\:\:read_shm_header: read $shm_header from $shmid";

    # --- Unencode it
    unpack('L', $shm_header);
}

sub write_shm_header {
    # --- Writes the (minimal) shm header that we put into each shm segment
    # --- Returns true upon success, craps out if there's an error
    my($shmid, $length) = @_;
    debug "$Package\:\:write_shm_header called on $shmid";

    # --- Write the header
    shmwrite($shmid, pack('L', $length), 0, SHM_HEADSIZE) or
	croak "$Package\:\:write_shm_header: shmwrite returned false ($!)";
    debug "$Package\:\:write_shm_header: wrote $length to $shmid";
    1;
}

sub read_shm_footer {
    # --- Read the (minimal) shm footer that indicates the next segment containing
    # --- data for this variable
    my($shmid) = @_;
    my $shm_footer = '';
    my $foot_offset = (SHM_BUFSIZ) - (SHM_FOOTSIZE);
    debug "$Package\:\:read_shm_footer called on $shmid";

    # --- Do it
    shmread($shmid, $shm_footer, $foot_offset, SHM_FOOTSIZE) or
	croak "$Package\:\:read_shm_footer return false";

    # --- Unencode it
    unpack('i', $shm_footer);
}

sub write_shm_footer {
    # --- Write the minimal shm footer hat indicates the next segment containing
    # --- data for this variable
    my($shmid, $shm_footer) = @_;
    my $foot_offset = (SHM_BUFSIZ) - (SHM_FOOTSIZE);
    debug "$Package\:\:write_shm_footer called on $shmid, $shm_footer";

    # --- Pack the data as necessary
    $shm_footer = pack('i', $shm_footer);
    debug "$Package\:\:write_shm_footer: packed foot looks like $shm_footer";

    # --- Do it
    shmwrite($shmid, $shm_footer, $foot_offset, SHM_FOOTSIZE) or
	croak "$Package\:\:write_shm_footer: shmwrite returned false ($!)";
}

# --------------------------------------------------------------------------------
# --- Preloaded methods specific to hashes
# --------------------------------------------------------------------------------
sub TIEHASH {
    # --- Constructor
    my($class, @arguments) = @_;
    my($shm_hash, $shmid, $shm_info);
    debug "$Package\:\:TIEHASH called on $class, @arguments";

    # --- Parse arguments and get the shmid
    $shmid = tie_to_shm('HASH', @arguments);
    defined $shmid or return;

    # --- Create the reference
    $shm_hash = \$shmid;

    # --- Bless into this class
    bless $shm_hash, $class;
}

sub FIRSTKEY {
    my($shm_hash) = @_;
    # --- Called when the user begins an iteration via each() or keys().
    debug "$Package\:\:FIRSTKEY called on $shm_hash ($$shm_hash)";

    # --- Make sure that %Shm_Info is up-to-date
    FETCH($shm_hash);

    # --- Set the magical token indicating an iteration has begun
    $Shm_Info{$$shm_hash}{'hash_iterating'} = 1;

    # --- Now the $hash_ref obtained on the next line should be (reasonably) up-to-date
    scalar each %{$Shm_Info{$$shm_hash}{'DATA'}};
}

sub NEXTKEY {
    my($shm_hash) = @_;
    my($key);
    # --- Called during the middle of an iteration via each() or keys().
    debug "$Package\:\:NEXTKEY called on $shm_hash";

    # --- Get the next key from our local cache
    $key = each %{$Shm_Info{$$shm_hash}{'DATA'}};

    # --- Check to see if we're at the end of the iteration; if so,
    # --- we save our cached copy for the world to see.
    if (not defined $key) {
	debug "$Package\:\:NEXTKEY: end of iteration detected";
	delete $Shm_Info{$$shm_hash}{'hash_iterating'};
	STORE($shm_hash);
    }

    # --- Now we return the key
    $key;
}

sub DELETE {
    my($shm_hash, $key) = @_;
    my $value;
    debug "$Package\:\:DELETE called on $shm_hash with $key";

    # --- Make sure that Shm_Info is up-to-date
    FETCH($shm_hash);

    # --- Delete the unwanted key
    $value = delete $Shm_Info{$$shm_hash}{'DATA'}{$key};
    debug "$Package\:\:DELETE: removed '$key' => '$value' from $shm_hash";

    # --- Store the new hash
    STORE($shm_hash);
    return $value;
}
    

sub EXISTS {
    # --- Tests if a given key exists or not
    my($shm_hash, $key) = @_;
    my($hash_ref);

    # --- Make sure that %Shm_Info is up-to-date
    FETCH($shm_hash);

    # --- Just do it
    exists $Shm_Info{$$shm_hash}{'DATA'}{$key};
}

sub CLEAR {
    # --- Wipes out the entire contents of the hash
    my($shm_hash) = @_;
    debug "$Package\:\:CLEAR called on $shm_hash";

    # --- Store an empty hash locally
    $Shm_Info{$$shm_hash}{'DATA'} = {};

    # --- Write the new hash
    STORE($shm_hash);
    1;
}

# --------------------------------------------------------------------------------
# --- Preloaded methods specific to scalars
# --------------------------------------------------------------------------------
sub TIESCALAR {
    # --- Constructor
    my($class, @arguments) = @_;
    my($shm_scalar, $shmid);
    debug "$Package\:\:TIESCALAR called on $class, @arguments";

    # --- Parse arguments and get the shmid
    $shmid = tie_to_shm('SCALAR', @arguments);
    defined $shmid or return;

    # --- Create the reference
    $shm_scalar = \$shmid;

    # --- Bless the reference into this class
    bless $shm_scalar, $class;
}

1;
__END__

=head1 NAME

IPC::Shareable - share Perl variables between processes

=head1 SYNOPSIS

  use IPC::Shareable;
  tie($scalar, IPC::Shareable, $glue, { %options });
  tie(%hash, IPC::Shareable, $glue, { %options });

=head1 CONVENTIONS

The occurrence of a number in square brackets, as in [N], in the text
of this document refers to a numbered note in the L</NOTES>.

=head1 DESCRIPTION

IPC::Shareable allows you to tie a a variable to shared memory making
it easy to share the contents of that variable with other Perl
processes.  Currently either scalars or hashes can be tied; tying of
arrays remains a work in progress.  However, the variable being tied
may contain arbitrarily complex data structures - including references
to arrays, hashes of hashes, etc.

The association between variables in distinct processes is provided by
I<$glue>.  This is an integer number or 4 character string[1] that serves
as a common identifier for data across process space.  Hence the
statement

	tie($scalar, IPC::Shareable, 'data');

in program one and the statement

	tie($variable, IPC::Shareable, 'data');

in program two will bind $scalar in program one and $variable in
program two.  There is no pre-set limit to the number of processes
that can bind to data; nor is there a pre-set limit to the size or
complexity of the underlying data of the tied variables[2].

The bound data structures are all linearized (using Raphael Manfredi's
Storable module) before being slurped into shared memory.  Upon
retrieval, the original format of the data structure is recovered.
Semaphore flags are used for versioning and managing a per-process
cache, allowing quick retrieval of data when, for instance, operating
on a tie()d variable in a tight loop.

=head1 OPTIONS

Options are specified by passing a reference to a hash as the fourth
argument to the tie function that enchants a variable.  Alternatively
you can pass a reference to a hash as the third argument;
IPC::Shareable will then look at the field named I<'key'> in this hash
for the value of I<$glue>.  So,

	tie($variable, IPC::Shareable, 'data', \%options);

is equivalent to

	tie($variable, IPC::Shareable, { 'key' => 'data', ... });

When defining an options hash, values that match the word I<'no'> in a
case-insensitive manner are treated as false.  Therefore, setting
C<$options{'create'} = 'No';> is the same as C<$options{'create'} =
0;>.

The following fields are recognized in the options hash.

=over 4

=item key

The I<'key'> field is used to determine the I<$glue> if I<$glue> was
not present in the call to tie().  This argument is then, in turn,
used as the KEY argument in subsequent calls to shmget() and semget().
If this field is not provided, a value of IPC_PRIVATE is assumed,
meaning that your variables cannot be shared with other
processes. (Note that setting I<$glue> to 0 is the same as using
IPC_PRIVATE.)

=item create

If I<'create'> is set to a true value, IPC::Shareable will create a new
binding associated with I<$glue> if such a binding does not already
exist.  If I<'create'> is false, calls to tie() will fail (returning
undef) if such a binding does not already exist.  This is achieved by
ORing IPC_PRIVATE into FLAGS argument of calls to shmget() when
I<create> is true.

=item exclusive

If I<'exclusive'> field is set to a true value, calls to tie() will
fail (returning undef) if a data binding associated with I<$glue>
already exists.  This is achieved by ORing IPC_ IPC_EXCL into the
FLAGS argument of calls to shmget() when I<'exclusive'> is true.

=item mode

The I<mode> argument is an octal number specifying the access
permissions when a new data binding is being created.  These access
permission are the same as file access permissions in that 0666 is
world readable, 0600 is readable only by the effective UID of the
process creating the shared variable, etc.  If not provided, a default
of 0666 (world readable and writable) will be assumed.

=item destroy

If set to a true value, the data binding will be destroyed when the
process calling tie() exits (gracefully)[3].

=back

=head1 EXAMPLES

In a file called B<server>:

    #!/usr/bin/perl -w
    use IPC::Shareable;
    $glue = 'data';
    %options = (
        'create' => 'yes',
        'exclusive' => 'no',
        'mode' => 0644,
        'destroy' => 'yes',
    );
    tie(%colours, IPC::Shareable, $glue, { %options }) or
        die "server: tie failed\n";
    %colours = (
        'red' => [
             'fire truck',
             'leaves in the fall',
        ],
        'blue' => [
             'sky',
             'police cars',
        ],
    );
    (print("server: there are 2 colours\n"), sleep 5)
        while scalar keys %colours == 2;
    print "server: here are all my colours:\n";
    foreach $colour (keys %colours) {
        print "server: these are $colour: ",
            join(', ', @{$colours{$colour}}), "\n";
    }
    exit;

In a file called B<client>

    #!/usr/bin/perl -w
    use IPC::Shareable;
    $glue = 'data';
    %options = (
        'key' => 'paint',
        'create' => 'no',
        'exclusive' => 'no',
        'mode' => 0644,
        'destroy' => 'no',
        );
    tie(%colours, IPC::Shareable, $glue, { %options }) or
        die "client: tie failed\n";
    foreach $colour (keys %colours) {
        print "client: these are $colour: ",
            join(', ', @{$colours{$colour}}), "\n";
    }
    delete $colours{'red'};
    exit;

And here is the output (the sleep commands in the command line prevent
the output from being interrupted by shell prompts):

    bash$ ( ./server & ) ; sleep 10 ; ./client ; sleep 10
    server: there are 2 colours
    server: there are 2 colours
    server: there are 2 colours
    client: these are blue: sky, police cars
    client: these are red: fire truck, leaves in the fall
    server: here are all my colours:
    server: these are blue: sky, police cars



=head1 RETURN VALUES

Calls to tie() that try to implement IPC::Shareable will return true
if successful, I<undef> otherwise.

=head1 INTERNALS

When a variable is tie()d, a blessed reference to a SCALAR is created.
(This is true even if it is a HASH being tie()d.)  The value thereby
referred is an integer[4] ID that is used as a key in a hash called
I<%IPC::Shareable::Shm_Info>; this hash is created and maintained by
IPC::Shareable to manage the variables it has tie()d.  When
IPC::Shareable needs to perform an operation on a tie()d variable, it
dereferences the blessed reference to perform a lookup in
I<%IPC::Shareable::Shm_Info> for the information needed to proceed.

I<%IPC::Shareable::Shm_Info> has the following structure:

    %IPC::Shareable::Shm_Info = (

        # - The id of an enchanted variable
        $id => {

            # -  A literal indicating the variable type
            'type' => 'SCALAR' || 'HASH',

            # - Shm segment IDs for this variable
            'frag_id' => {
                '0' => $id_1, # - ID of first shm segment
                '1' => $id_2, # - ID of next shm segment
                ... # - etc
            },

            # - ID of associated semaphores
            'sem_id' => $semid,

            # - The I<$glue> used when tie() was called
            'key' => $glue,

            # - The value of FLAGS for shmget() calls.
            'flags' => $flags,

            # - Destroy shm segements on exit?
            'destroy' => $destroy,

            # - Data cache
            'DATA' => \$data || \%data,

            # - The version number of the cached data
            'version' => $version,
            },
       ...
   );

Perhaps the most important thing to note the existence of the
I<'DATA'> and I<'version'> fields: data for all tie()d variables is
stored locally in a per-process cache.  When storing data, the values
of the semaphores referred to by I<$Shm_Info{$id}{'sem_id'}> are
changed to indicate to the world a new version of the data is
available. When retrieving data for a tie()d variables, the values of
these semaphores are examined to see if another process has created a
more recent version than the cached version.  If a more recent version
is available, it will be retrieved from shared memory and used. If no
more recent version has been created, the cached version is used[5].

Another important thing to know is that IPC::Shareable allocates
shared memory of a constant size SHM_BUFSIZ, where SHM_BUFSIZ is
defined in this module.  If the amount of (serialized) data exceeds
this value, it will be fragmented into multiple segments during a
write operation and reassembled during a read operation.

=head1 AUTHOR

Benjamin Sugars <bsugars@canoe.ca>

=head1 NOTES

=head2 Footnotes from the above sections

=over 4

=item 1

If I<$glue> is longer than 4 characters, only the 4 most significant
characters are used.  These characters are turned into integers by unpack()ing
them.  If I<$glue> is less than 4 characters, it is space padded.

=item 2

IPC::Shareable provides no pre-set limits, but the system does.
Namely, there are limits on the number of shared memory segments that
can be allocated and the total amount of memory usable by shared
memory.

=item 3.

If the process has been smoked by an untrapped signal, the binding
will remain in shared memory.  If you're cautious, you might try

    $SIG{INT} = \&catch_int;
    sub catch_int {
        exit;
    }
    ...
    tie($variable, IPC::Shareable, 'data', { 'destroy' => 'Yes!' });

which will at least clean up after your user hits CTRL-C because
IPC::Shareable's DESTROY method will be called.  Or, maybe you'd like
to leave the binding in shared memory, so subsequent process can
recover the data...

=item 4

The integer happens to be the shared memory ID of the first shared
memory segment used to store the variable's data.

=item 5

The exception to this is when the FIRSTKEY and NEXTKEY methods are
implemented, presumably because of a call to each() or keys().  In
this case, the cached value is ALWAYS used until the end of the cached
hash has been reached.  Then the cache is refreshed with the public
version (if the public version is more recent).

The reason for this is that if a (changed) public version is retrieved
in the middle of a loop implemented via each() or keys(), chaos could
result if another process added or removed a key from the hash being
iterated over.  To guard against this, the cached version is always
used during such cases.

=back

=head2 General Notes

=over 4

=item o

As mentioned in L</INTERNALS>, shared memory segments are acquired
with sizes of SHM_BUFSIZ.  SHM_BUFSIZ's largest possible value is
nominally SHMMAX, which is highly system-dependent.  Indeed, for some
systems it may be defined at boot time.  If you can't seem to tie()
any variables, it may be that SHM_BUFSIZ is set a value that exceeds
SHMMAX on your system.  Try reducing the size of this constant and
recompiling the module.

=item o

The class contains a translation of the constants defined in the
<sys/ipc.h>, <sys/shm.h>, and <sys/sem.h> header files.  These
constants are used internally by the class and cannot be imported into
a calling environment.  To do that, use IPC::SysV instead.  Indeed, I
would have used IPC::SysV myself, but I haven't been able to get it to
compile on any system I have access to :-(.

=item o

There is a program called ipcs(1/8) that is available on at least
Solaris and Linux that might be useful for cleaning moribund shared
memory segments or semaphore sets produced by bugs in either
IPC::Shareable or applications using it.

=item o

Set the variable I<$IPC::Shareable::Debug> to a true value to produce
*many* verbose debugging messages on the standard error (I don't use
the Perl debugger as much as I should... )

=back

=head1 BUGS

Certainly; this is alpha software.

The first bug is that I do not know what all the bugs are. If you
discover an anomaly, send me an email at bsugars@canoe.ca.

Variables that have been declared local with my() and subsequently
tie()d can act in a bizarre fashion if you store references in them.
You can try not not using my() in these cases, or go through extra
pain when dereferencing them, like this:

    #!/usr/bin/perl
    use IPC::Shareable;
    my $scalar;
    tie($scalar, IPC::Shareable, { 'destroy' => 'yes' });
    $scalar = [ 0 .. 9 ];
    @array = @$scalar;
    for (0 .. 9) {
        print "$array[$_]\n"; # $$scalar won't work after 'my $scalar;'
    }

I suspect the reason for this is highly mystical and requires a wizard
to explain.

=head1 SEE ALSO

perl(1), perltie(1), Storable(3), shmget(2) and other SysV IPC man
pages.

=cut

# --- Autoloaded methods
