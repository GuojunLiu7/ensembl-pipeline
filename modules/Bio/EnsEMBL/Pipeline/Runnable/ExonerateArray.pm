#
# Written by Eduardo Eyras
#
# Copyright GRL/EBI 2002
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod

=head1 NAME

Bio::EnsEMBL::Pipeline::Runnable::ExonerateArray

=head1 SYNOPSIS
$database  = a full path location for the directory containing the target (genomic usually) sequence,
@sequences = a list of Bio::Seq objects,
$exonerate = a location for the binary,
$options   = a string with options ,

  my $runnable = Bio::EnsEMBL::Pipeline::Runnable::ExonerateArray->new(
								 -database      => $database,
								 -query_seqs    => \@sequences,
								 -query_type    => 'dna',
			                                         -target_type   => 'dna',
                                                                 -exonerate     => $exonerate,
								 -options       => $options,
								);

 $runnable->run; #create and fill Bio::Seq object
 my @results = $runnable->output;
 
 where @results is an array of DnaDnaAlignFeatures, each one representing an aligment which are
 in fact feature pairs.
 
=head1 DESCRIPTION

ExonerateArray takes a Bio::Seq (or Bio::PrimarySeq) object and runs Exonerate
against a set of sequences.  The resulting output file is parsed
to produce a set of features.


=head1 CONTACT

ensembl-dev@ebi.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Pipeline::Runnable::ExonerateArray;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Pipeline::RunnableI;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableI);


sub new {
  my ($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  
  my ($db,$database, $query_seqs, $query_type, $target_type, $exonerate, $options, $analysis) = 
    $self->_rearrange([qw(
			  DB
			  DATABASE
			  QUERY_SEQS
			  QUERY_TYPE
			  TARGET_TYPE
			  EXONERATE
			  OPTIONS
			  ANALYSIS
			 )
		      ], @args);
  
  
  $self->{_output} = [];
  $self->analysis($analysis) if $analysis;

  ###$db is needed to create $slice which is needed to create DnaDnaAlignFeatures
  $self->db($db) if $db;
  # must have a target and a query sequences
  unless( $query_seqs ){
    $self->throw("Exonerate needs a query_seqs: $query_seqs");
  }
  $self->query_seqs(@{$query_seqs});
  
  # you can pass a sequence object for the target or a database (multiple fasta file);
  if( $database ){
    $self->database( $database );
  }
  else{
    $self->throw("Exonerate needs a target - database: $database");
  }
  
  ############################################################
  # Target type: The default is dna
  if ($target_type){
    $self->target_type($target_type);
  }
  else{
    print STDERR "Defaulting target type to dna\n";
    $self->target_type('dna');
  }

  ############################################################
  # Query type: The default is dna
  if ($query_type){
    $self->query_type($query_type);
  }
  else{
    print STDERR "Defaulting query type to dna\n";
    $self->query_type('dna');
  }
  
  $self->exonerate($exonerate);
  
  my $basic_options = '--showalignment no --showvulgar no --bestn 5 --ryo "myoutput: %S %V %pi\n"';
  
  if ($options){
    $self->options($options);
  }
  else {
    $self->options($basic_options);
  }
  return $self;
}

############################################################
#
# Analysis methods
#
############################################################

=head2 run

Usage   :   $obj->run($workdir, $args)
Function:   Runs exonerate script and generate features which then stored in $self->output
            
=cut

sub run {
  my ($self) = @_;
  
  my $verbose = 0;
  
  my $dir         = $self->workdir();
  my $exonerate   = $self->exonerate;
  my @query_seqs  = $self->query_seqs;
  my $query_type  = $self->query_type;
  my $target_type = $self->target_type;
  
  # set the working directory (usually /tmp)
  $self->workdir('/tmp') unless ($self->workdir());
  
  # target sequence
  
  my $target;
  if ( $self->database ){
    $target = $self->database;
  }
  
  #elsif( $self->target_seq ){
  #  
  #  # write the target sequence into a temporary file then
  #  $target = "$dir/target_seq.$$";
  #  open( TARGET_SEQ,">$target") || $self->throw("Could not open $target $!");
  #  my $seqout = Bio::SeqIO->new('-format' => 'Fasta',
  #		 '-fh'     => \*TARGET_SEQ);
  #  $seqout->write_seq($self->target_seq);
  #  close( TARGET_SEQ );
  #}
  
  ############################################################
  # write the query sequence into a temporary file then
  
  our (%length,%rec_q_id,%done);
  
  my $query = "$dir/query_seqs.$$";
  
  open( QUERY_SEQ,">$query") || $self->throw("Could not open $query $!");
  
  my $seqout = Bio::SeqIO->new('-format' => 'Fasta',
			       '-fh'     => \*QUERY_SEQ);
  
  # we write each Bio::Seq sequence in the fasta file $query
  
  foreach my $query_seq (@query_seqs) {
    $length{$query_seq->display_id} = $query_seq->length;
    $seqout->write_seq($query_seq);
  }
  
  close( QUERY_SEQ );
  
  my $command =$self->exonerate." ".$self->options.
    " --querytype $query_type --targettype $target_type --query $query --target $target ";
  
  $command .= " | ";
  
  #print STDERR "running exonerate: $command\n" if $verbose;
  print STDERR "running exonerate: $command\n";
  
  open( EXO, $command ) || $self->throw("Error running exonerate $!");
  
  # system calls return 0 (true in Unix) if they succeed
  #$self->throw("Error running exonerate\n") if (system ($command));
  
  
  ############################################################
  # store each alignment as a features
  
  my (@pro_features);
  
  ############################################################
  # parse results - avoid writing to disk the output
  
  while (<EXO>){
    
    print STDERR $_ if $verbose;
    print $_;
    ############################################################
    # the output is of the format:
    #
    #
    # vulgar contains 9 fields
    # ( <qy_id> <qy_start> <qy_len> <qy_strand> <tg_id> <tg_start> <tg_len> <tg_strand> <score> ), 
    # 
    # The vulgar (Verbose Useful Labelled Gapped Alignment Report) blocks are a series 
    # of <label, query_length, target_length> triplets. The label may be one of the following: 
    #
    # M    Match 
    #
    # example:
    # vulgar: probe:HG-U95Av2:1002_f_at:195:583; 0 25 + 10.1-135037215 96244887 96244912 + 125 M 25 25 100
    # match_length is 25 bs, it may not be exact match, score 125->exact match, score 116 match 24 bs
    # if it is 120 M 24 24, it means exact match for 24 bs.
    
    if (/^myoutput\:/) {
      my $h={};
      chomp;
      my ( $tag, $q_id, $q_start, $q_end, $q_strand, $t_id, $t_start, $t_end, $t_strand, $score, $match, $matching_length, $null, $pid) = split;
      
      # the VULGAR 'start' coordinates are 1 less than the actual position on the sequence
      $q_start++;
      $t_start++;
      
      my $strand;
      if ($q_strand eq $t_strand) {
	$strand = 1;
      }
      else {
	$strand = -1;
      }
      
      $h->{'q_id'} = $q_id;
      $h->{'q_start'} = $q_start;
      $h->{'q_end'} = $q_end;
      $h->{'q_strand'} = $strand;
      $h->{'t_id'} = $t_id;
      $h->{'t_start'} = $t_start;
      $h->{'t_end'} = $t_end;
      $h->{'t_strand'} = $strand;
      $h->{'score'} = $score;
      $h->{'matching_length'} = $matching_length;
      $h->{'percent_id'} = $pid;
      
      ###for affymetrix probe sequence, they are 25 bs long, we require at least 24 bs exact match###
      #if ($h->{'matching_length'} ==24 and $h->{'percent_id'} ==100) {
      if ($h->{'matching_length'} == $length{$h->{'q_id'}}-1 and $h->{'percent_id'}==100) {
	print "24 $_\n";
	$self->_create_features($h);
      } 
      #elsif ($h->{'matching_length'} ==25 and $h->{'percent_id'}>=96) {
      elsif ($h->{'matching_length'} == $length{$h->{'q_id'}} and $h->{'percent_id'}>=(($length{$h->{'q_id'}}-1)/$length{$h->{'q_id'}}*100)) {
	print "25 $_\n";
	$self->_create_features($h);
      }
    }
  }
  
  
  close(EXO) or $self->throw("couldn't close pipe ");  
  
  #$self->_create_features(@pro_features);

  ############################################################
  # remove interim files (but do not remove the database if you are using one)
  unlink $query;
  if ( $self->genomic){
    unlink $target;
  }
}

sub _create_features {
  
  
  ###I am not sure how to create MiscFeature, only using the following temperately####
  
  my ($self,$h) = @_;
  
  ###to make DnaDnaAlignFeature, we need to make Analysis_obj and slice_obj###
  
  my @features;
  
  my $coord_system_name = "chromosome";
  my ($seq_region_name) = $h->{'t_id'} =~ /^(\S+)\..*$/;
  my $slice = $self->db->get_SliceAdaptor->fetch_by_region($coord_system_name,$seq_region_name,$h->{'t_start'},$h->{'t_end'});
  my $feat_pair = Bio::EnsEMBL::FeaturePair->new(
						 -slice    => $slice,
						 -start    => $h->{'t_start'},
						 -end      => $h->{'t_end'},
						 -strand   => $h->{'t_strand'},
						 -hseqname => $h->{'q_id'},
						 -hstart   => $h->{'q_start'},
						 -hend     => $h->{'q_end'},
						 -hstrand  => $h->{'q_strand'},
						 -percent_id => $h->{'percent_id'},
						 -analysis  => $self->analysis,
						);
  
  my $feat = Bio::EnsEMBL::DnaDnaAlignFeature->new (-features => [$feat_pair]);
  
  
  
  $self->output($feat);
  
  
}

############################################################
#
# get/set methods
#
############################################################

sub analysis{
  
  my ($self,$analysis) = @_;
  if( defined $analysis) {
    $self->{'_analysis'} = $analysis;
  }
  return $self->{'_analysis'};
  
}

############################################################

sub query_seqs {
  my ($self, @seqs) = @_;
  if (@seqs){
    unless ($seqs[0]->isa("Bio::PrimarySeqI") || $seqs[0]->isa("Bio::SeqI")){
      $self->throw("query seq must be a Bio::SeqI or Bio::PrimarySeqI");
    }
    push(@{$self->{_query_seqs}}, @seqs) ;
  }
  return @{$self->{_query_seqs}};
}

############################################################

sub genomic {
  my ($self, $seq) = @_;
  if ($seq){
    unless ($seq->isa("Bio::PrimarySeqI") || $seq->isa("Bio::SeqI")){
      $self->throw("query seq must be a Bio::SeqI or Bio::PrimarySeqI");
    }
    $self->{_genomic} = $seq ;
  }
  return $self->{_genomic};
}

############################################################

sub exonerate {
  my ($self, $location) = @_;
  if ($location) {
    $self->throw("Exonerate not found at $location: $!\n") unless (-e $location);
    $self->{_exonerate} = $location ;
  }
  return $self->{_exonerate};
}

############################################################

sub options {
  my ($self, $options) = @_;
  if ($options) {
    $self->{_options} = $options ;
  }
  return $self->{_options};
}

############################################################

sub db {
  my ($self, $db) = @_;
  if ($db) {
    $self->{_db} = $db ;
  }
  return $self->{_db};
}

############################################################

sub output {
  my ($self, $output) = @_;
  if ($output) {
    unless( $self->{_output} ){
      $self->{_output} = [];
    }
    push( @{$self->{_output}}, $output );
  }
  return @{$self->{_output}};
}

############################################################

sub database {
  my ($self, $database) = @_;
  if ($database) {
    $self->{_database} = $database;
  }
  return $self->{_database};
}
############################################################

sub query_type {
  my ($self, $mytype) = @_;
  if (defined($mytype) ){
    my $type = lc($mytype);
    unless( $type eq 'dna' || $type eq 'protein' ){
      $self->throw("not the right query type: $type");
    }
    $self->{_query_type} = $type;
  }
  return $self->{_query_type};
}

############################################################

sub target_type {
  my ($self, $mytype) = @_;
  if (defined($mytype) ){
    my $type = lc($mytype);
    unless( $type eq 'dna'|| $type eq 'protein' ){
      $self->throw("not the right target type: $type");
    }
    $self->{_target_type} = $type ;
  }
  return $self->{_target_type};
}

############################################################


1;
