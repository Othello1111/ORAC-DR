package ORAC::Index;

=head1 NAME

ORAC::Index - perl routines for manipulating ORAC index files

=head1 SYNOPSIS

use ORAC::Index;


=head1 DESCRIPTION

This module provides subs for manipulating ORAC index files. ORAC
index files consist of whitespace seperated columns containing
information about a particular frame.

In the case of calibration index files, these may also contain rules
for determining the suitability of use for these frames. These consist
of code that is TRUE or FALSE depending on appropriate header values
of the object to be calibrated.

=cut


use Carp;
use strict;
use vars qw/$VERSION/;
use ORAC::Print;

use POSIX qw/tmpnam/;  # For unique keys

$VERSION = '0.11';

=head1 PUBLIC METHODS

The following methods are available in this class.

=over 4

=item new

Create a new instance of an ORAC::Index object.

$Index = new ORAC::Index;

=cut

sub new {
  
  
  my $proto = shift;
  my $class = ref($proto) || $proto;
  
  my $index = {};			# Anon hash reference
  $index->{IndexRules} = {};		# ditto
  $index->{IndexEntries} = {};		# ditto
  
  $index->{IndexFile} = undef;
  $index->{IndexFileHandle} = undef;
  $index->{IndexRulesFile} = undef;
  
  bless($index, $class);
  
  if (@_) { $index->configure(@_)};
  
  
  return $index;
  
};

=item indexfile

Return (or set) the filename of the index file

$file = $Index->indexfile;

=cut


sub indexfile {
  my $self = shift;
  if (@_) {
    $self->{IndexFile} = shift; 
    $self->slurpindex;    
  };
  return $self->{IndexFile};
};


=item indexrulesfile

Return (or set) the filename of the rules file

=cut

sub indexrulesfile {
  my $self = shift;
  if (@_) {
    $self->{IndexRulesFile} = shift; 
    $self->slurprules;
  };
  return $self->{IndexRulesFile};
};

=item configure

Takes an index file and an rules file and sets up the index object

=cut

sub configure {
  my $self = shift;
  my ($file,$rules) = @_;
  $self->indexfile($file);
  $self->indexrulesfile($rules);
};

=item rulesref

Returns or sets the reference to the hash containing the rules

=cut

sub rulesref {
  my $self = shift;
  
  if (@_) { 
    my $arg = shift;
    croak("Argument is not a hash") unless ref($arg) eq "HASH";
    $self->{IndexRules} = $arg;
  }
  
  return $self->{IndexRules};
}

=item indexref

Returns or sets the reference to the hash containing the index

=cut

sub indexref {
  my $self = shift;
  
  if (@_) { 
    my $arg = shift;
    croak("Argument is not a hash") unless ref($arg) eq "HASH";
    $self->{IndexEntries} = $arg;
  }
  
  return $self->{IndexEntries};
}


=item slurprules

Sets up the index rules in the object. Croaks if it fails.

=cut

sub slurprules {
  
  my $self = shift;
  my $file = $self->indexrulesfile;
  
  my %rules = ();
  my $handle = new IO::File "< $file";
  
  
  if (defined $handle) {
    
    foreach my $line (<$handle>) {
      
      next if $line =~ /^\s*\#/;

      $line =~ s/^\s+//g;		# zap leading blanks
      my ($header,$rule)=split(/\s+/,$line,2);
      
      next unless defined $header;	# skip blank lines
      chomp($rule);                     # Remove carriage return
      $rules{$header} = $rule;   
      
    };
    
  } else {
    
    croak("Couldn't open rules file $file : $!");
    
  };
  
  $self->rulesref(\%rules);
  
};


=item slurpindex(usekey)

Sets up the index data in the object. Croaks if it fails.
The supplied argument is used to control the behaviour of the
read. If the 'usekey' flag is true the first string in each
row (space separated) is used as a key for the index hash.

If 'usekey' is false the key for each row is created 
automatically. This is useful for indexes where the contents 
of the index is more important than any particular key.

  $index->slurpindex(0); # Auto-generate keys

Default behaviour (ie no args) is to read the key from the
index file (ie usekey=1).

=cut

sub slurpindex {
  
  my $self = shift;

  # Read arguments
  my $usekey = 1;
  if (@_) { $usekey = shift; }

  # Look for index file
  my $file = $self->indexfile;
  return unless (-e $file);
  
  my %index = ();
  my $handle = new IO::File "< $file";
  
  
  if (defined $handle) {
    
    foreach my $line (<$handle>) {
      
      next if $line =~ /^\s*#/; 

      $line =~ s/^\s+//g;		   # zap leading blanks
      my ($name,@data)=split(/\s+/,$line); # Split on spaces
      next unless defined $name;	   # skip blank lines

      # If we are using the key from the file then we
      # have that as $name. Else we have to create a new $name
      # for the hash

      unless ($usekey) {
        # Put $name back onto the index array
        unshift (@data, $name);
  
        # Create a new key
        $name = tmpnam;
      }
      
      # Store index entry in hash
      $index{$name} = \@data;
      
    };
    
  } else {
    
    croak("Couldn't open index file $file : $!");
    
  };
  
  $self->indexref(\%index);
  
};




=item writeindex

writes out the current state of the index object into the index file

=cut

sub writeindex {
  
  my $self=shift;
  my $file = $self->indexfile;
  
  my $handle = new IO::File "> $file";

  if (defined $handle) {
    
    print $handle "#",join(" ",sort keys %{$self->rulesref}),"\n";
    
    foreach my $entry (sort keys %{$self->indexref}) {
      print $handle $self->index_to_text($entry) . "\n";
    };
    
  } else {
    
    croak("Couldn't open index $file : $!");
    
  };
  
};

=item add 

adds an entry to an index

$index->add($name,$hashref)

=cut

sub add {
  
  my $self=shift;
  croak('Usage: add($name,$hashref)') unless (scalar(@_)==2);
  my ($name,$hashref) = @_;
  
  croak("Argument is not a hash") unless ref($hashref) eq "HASH";  
  
  my @entry = ();
  foreach my $key (sort keys %{$self->rulesref}) {
    if (exists $$hashref{$key}) {
      push (@entry,$$hashref{$key});
    } else {
      croak "Rules file specifies entry $key unknown to file header";
    };
  };

  # Decide whether we are adding a brand new index entry
  # (ie $name is not in index) OR this is a modification
  # of an existing entry
  # If we have a new entry - simply append to the index file
  # If we have an old entry - write the complete index file
  # This optimisation is to prevent a slow down that occurs
  # when an index file contains a few hundred entries (eg when
  # examining calibration history)

  if (exists $self->indexref->{$name}) {
    $self->indexref->{$name} = \@entry;
    $self->writeindex;
  } else {
    $self->indexref->{$name} = \@entry;
    $self->append_to_index($name);
  }

}


=item append_to_index

Method to force an append of the specified index entry to the
the index file on disk.

  $Index->append_to_index($name);

$name is the name of the key (indexentry) to use to select the
index entry to append [cf the indexentry() method].

This method is intended to be called from the add() method
to speed up index read/write when appending a new entry.
Do not use this method to write a modified entry to the
index file (since the original entry will still be on disk)

No return value.

=cut

sub append_to_index {
  my $self = shift;

  # Read the key from the arg list
  croak 'No argument supplied' unless @_;
  my $entry = shift;

  my $file = $self->indexfile;
  my $index= $self->indexref;

  # Look for the key in the indexfile (cant append if not present)
  if (exists $index->{$entry}) {

    # Look for the file on disk - if it is not there then simply
    # call writeindex
    if (-e $file) {
      # Open file for append
      my $handle = new IO::File ">> $file";

      if (defined $handle) {
        # Write entry (automatically close file when leave scope)
        print $handle $self->index_to_text($entry) . "\n";

      } else {
         croak "Couldn't open index $file : $!";   
      }

    } else {
      $self->writeindex;
    }

  } else {
    carp "Possible programming error: Entry ($entry) not in current index\n";
  }

}


=item index_to_text

Convert an index entry (in the index hash) to text suitable for
writing to an index file. Called by writeindex() and append_to_index()

  $text = $Ind->index_to_text($entry);

Returns the text string (including the entry name but no carriage 
return).

=cut

sub index_to_text {
  my $self = shift;
  my $entry = shift;
  return $entry . " " . join(" ",@{$self->indexref->{$entry}});
}


=item indexentry

Returns a hash containing the key value pairs of the
selected index entry.

Input argument is the index entry name (ie the key in the hash
that returns the information (in an array).

Returns a hash reference if successful, undef if error.

=cut

sub indexentry {
  my $self = shift;

  croak('Usage: indexentry(name)') unless (scalar(@_) == 1);

  # Read the name from the input
  my $name = shift;

  # Check that it exists
  unless (exists $ {$self->indexref}{$name}) {
    orac_err "$name is unknown to oracdr and may not be used as calibration\n";
    orac_err "Make sure it is reduced by oracdr\n";
    return undef;
  };

  # take local copy of the calibration data index entry
  my @calibdata = @{$ {$self->indexref}{$name}};
  # take local copy the rules
  my %rules = %{$self->rulesref};

  # check that number of rules match index entries
  # This should probably be a method???
  unless ($#calibdata == (scalar(keys %rules) - 1)) {
    print '$#calibdata is ',$#calibdata,'(scalar(keys %rules) - 1)) is ',(scalar(keys %rules) - 1),"\n";
    orac_err "Something has gone seriously wrong with the index file\n";
    orac_err "You will need to regenerate it\n";
    return undef;
  };

  # Now construct the entry hash
  # This is very similar to writing out the values to file
  my %entry = ();

  # Loop over the rules keys
  foreach my $key (sort keys %rules) {
    $entry{$key} = shift(@calibdata);
  }

  return \%entry;

}



=item verify

verifies a frame (in the form of a hash reference) against a 
(calibration) index entry (ie by supplying the hash key to the index
entry). An optional third argument is available to turn off warning 
messages -- default is for warning messages to be turned on (true)

  $result = $index->verify(indexkey, \%hash, $warn);

Returns undef (error), 0 (not suitable), or 1 (suitable)

=cut

sub verify {

  my $self=shift;
  # expect the name of the calibration file and the object header hash
  croak('Usage: verify($calibration,$hashref)') 
    unless (scalar(@_)==2 || scalar(@_)== 3);

  my $name = shift;
  my $hashref = shift;
  
  my $warn = 1;
  if (@_) { $warn = shift; }

  croak("Argument is not a hash") unless ref($hashref) eq "HASH";  
  return 0 unless defined $name;

  unless (exists $ {$self->indexref}{$name}) {
    orac_err "$name is unknown to oracdr and may not be used as calibration\n";
    orac_err "Make sure it is reduced by oracdr\n";
    return 0;
  };

  # take local copy of the calibration data index entry
  my @calibdata = @{ $self->indexref->{$name} };
  # take local copy the rules
  my %rules = %{$self->rulesref};
  # take local copy of the object header hash
  my %Hdr = %$hashref;

  # check that number of rules match index entries
  # This should probably be a method???
  unless ($#calibdata == (scalar(keys %rules) - 1)) {
    print '$#calibdata is ',$#calibdata,'(scalar(keys %rules) - 1)) is ',(scalar(keys %rules) - 1),"\n";
    orac_err "Something has gone seriously wrong with the index file\n";
    orac_err "You will need to regenerate it\n";
    return undef;
  };
  
  foreach my $key (sort keys %rules) {
    # remember, by design the index file data is already sorted by rule order
    my $CALVALUE = shift(@calibdata);	# value of nth index entry

    # ignore if there is no rule attached to the keyword
    next unless $rules{$key} =~ /\w/;

    # We need to replace the key (eg ORACTIME) with $CALVALUE
    # Note that we do not want to replace $Hdr{ORACTIME} only
    # occurences of ORACTIME that do not have brackets
    # Use a zero-width negative lookahead assertion
    # Note that this does not replace ORACTIME}, ORACTIME'} or
    # ORACTIME"}
    $rules{$key} =~ s/$key(?!(\}|([\'\"]\})))/$CALVALUE/gx;

    # Now check the rule against the header values
    my $ok = eval("'$CALVALUE' $rules{$key}");
    if ($@) {
      orac_err "Eval error - check the syntax in your rules file\n";
      orac_err "Error was: $@ \n";
      return undef;
    };
    unless ($ok) {
      if ($warn) {
	orac_warn("$name not a suitable calibration: failed $key $rules{$key}\n");
	orac_warn "Header:-",$Hdr{$key},"--","Calvalue:-$CALVALUE-\n";
      }
      return 0;
    };
    
  };

  
  # if we have gotten to this stage, the calibration must be groovy
  return 1;
  
};

=item choosebydt

Chooses the optimal (nearest in time to an observation) calibration
frame from the index hash

  $calibration = $Index->choosebydt($key, \%header, $warn);

Key is the name of the field that should be compared (eg ORACTIME)
and %header is the hash containing the header values that are to
be compared with the index rules. $warn is an optional third argument
that can be used to turn off warning messages from verify (default
is to report messages - true).

This method returns the name of the calibration frame closest in 
time that has met the selection criteria.

If a suitable calibration can not be found an undefined value is returned.

=cut


sub choosebydt {

  my $self=shift;

  my $calibration =  $self->choosebydt_generic('ABS', @_);    

#  croak("No suitable calibrations were found in index file. Sorry.")
#    unless defined $calibration;
  return $calibration;
}

=item chooseby_positivedt

Chooses the calibration frame closest in time from above by looking 
in the index file (ie difference between the index file entry and
the current frame is positive).

  $calibration = $Index->chooseby_positivedt($key, \%header, $warn);

Key is the name of the field that should be compared (eg ORACTIME)
and %header is the hash containing the header values that are to
be compared with the index rules. $warn is an optional third argument
that can be used to turn off warning messages from verify (default
is to report messages - true).

This method returns the name of the calibration frame closest in 
time that has met the selection criteria.

This is similar to the choosebydt() method except that only
calibrations taken after the current time (read from the
header) can be chosen. undef is returned if no suitable
calibration frames can be found (eg because we are running
on-line and they have not even been taken yet).


=cut


sub chooseby_positivedt {
  my $self = shift;
  return $self->choosebydt_generic('POSITIVE', @_);  
}

=item chooseby_negativedt

Chooses the calibration frame closest in time from below by looking 
in the index file (ie delta time between the index entry and the 
current frame is negative).

  $calibration = $Index->chooseby_negativedt($key, \%header, $warn);

Key is the name of the field that should be compared (eg ORACTIME)
and %header is the hash containing the header values that are to
be compared with the index rules. $warn is an optional third argument
that can be used to turn off warning messages from verify (default
is to report messages - true).

This method returns the name of the calibration frame closest in 
time that has met the selection criteria.

This is similar to the choosebydt() method except that only
calibrations taken before the current time (read from the
header) can be chosen. undef is returned if no suitable 
calibration can be found.

=cut

sub chooseby_negativedt {
  my $self = shift;
  my $calibration =  $self->choosebydt_generic('NEGATIVE', @_);  

#  unless (defined $calibration) {
#    croak('No suitable calibration found before current frame');
#  }

  return $calibration;
}


=item choosebydt_generic 

Internal routine for handling calibraion matches using a 
time difference.

  $calibration = $Index->choosebydt_generic(TYPE, $key, \%header, $warn);

TYPES can be 'ABS' (chooses the closest calibration in time), 
'POSITIVE' (chooses the closest in time from calibrations earlier
than the current header) and 'NEGATIVE' (chooses calibrations after
the current observation [as described by %header]).

KEY, HEADER and WARN are described in the choosebydt() documentation.

=cut

sub choosebydt_generic {

  my $self = shift;

  my $type = shift;
  my $timekey = shift;
  my $hashref = shift;
  my $warn = 1;
  $warn = shift if @_;

  croak("Argument is not a hash") unless ref($hashref) eq "HASH";  

  my %Hdr = %$hashref;

  croak("Key $timekey unknown to orac - this should not happen\n") 
    unless exists $Hdr{$timekey};

  my %index = %{$self->indexref};
  
  my $pos = -1;

  foreach my $key (sort keys %{$self->rulesref}) {
    $pos++;
    last if $key eq $timekey;
  };

  ($pos < 0) && croak("Key $timekey not in rules - how can I be expected to work under these conditions?");

  my %dthash = (); # this is the hash for the keys and the associated time differences
  foreach my $key (keys %index) {
    # calculate the value of the time difference wrt to the object
    my $delta = $ {$index{$key}}[$pos]-$Hdr{$timekey};

    # Only store if we want POSITIVE/NEGATIVE or ABSOLUTE values
    if ($type eq 'ABS') {
      $dthash{$key} = abs($delta);
    } elsif ($type eq 'POSITIVE') {
      $dthash{$key} = $delta if $delta > 0;
    } elsif ($type eq 'NEGATIVE') {
      # Need to invert sense to keep the sorting correct
      $dthash{$key} = -1 * $delta if $delta < 0;
    } else {
      croak "choosebydt_generic: Unrecognised flag: $type\n";
    }
  };
   
  # sort index keys by value (delta-tee)
  # as described by Economou (1997) TPJ 2 2 :-) :-)
  my @timesorted = sort {$dthash{$a} <=> $dthash{$b}} keys %dthash;

  foreach my $calibration (@timesorted) {

    my $ok = $self->verify($calibration,\%Hdr, $warn);

    return $calibration if ($ok);
  };
  
  # If we get to this point, we didn't find any suitable ones
  return undef;
  
}




=item cmp_with_hash

Compares each index entry with the values in the supplied hash
(supplied as a hash reference). The key to the first matching 
index entry is returned. undef is returned if no match could be 
found.

  $key = $index->cmp_with_hash(\%hash);
  $key = $index->cmp_with_hash({ key1 => 'value',
                                 key2 => 'value2'});

Use the indexentry() method to convert this key into the actual
index entry. Note that warning messages are turned off during the
verification stage since we are not interested in failed matches.

Returns 'undef' if no match is found or if no argument is supplied
[or that argument itself is undef]

=cut

sub cmp_with_hash {

  my $self = shift;

  # Read the has
  my $hashref = shift;

  # Return undef if the hashref is undef
  return undef unless defined $hashref;

  # Croak if the argument is not a hash
  croak("cmp_with_hash: Argument is not a hash") 
    unless ref($hashref) eq "HASH";  

  # Get a copy of the index
  my %index = %{ $self->indexref };

  # Go through all the keys in the index comparing
  # the index entry with the supplied hash using the rules

  for my $entry (keys %index) {
    my $ok = $self->verify($entry, $hashref, 0);

    return $entry if ($ok);
  }

  # If we get this far we have no match
  return undef;
}


=back

=head1 AUTHORS

Frossie Economou (frossie@jach.hawaii.edu) and
Tim Jenness (t.jenness@jach.hawaii.edu)

=cut

1;
