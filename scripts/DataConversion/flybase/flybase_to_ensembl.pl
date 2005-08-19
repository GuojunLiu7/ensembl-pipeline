#!/usr/local/ensembl/bin/perl

# based on ensembl branch 25
use strict;
use FlyBaseGff;
use FlyBaseConf;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DBSQL::DBAdaptor;


$| = 1;

print "reading config-file FlyBaseConf.pm\n";

my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
                                            -host => $FB_DBHOST,
                                            -user => $FB_DBUSER,
                                            -dbname => $FB_DBNAME,
                                            -pass  => $FB_DBPASS,
                                            -port  => $FB_DBPORT,
                                           );


my $sa = $db->get_SimpleFeatureAdaptor();


#
# control options
#
 ################################################################################

my $store_simple_features = 1 ;

# check if all files are there and readable
for my $conf(@{$FB_CHR_INFO}){
     unless ( -r  $conf->{'gff_file'}){
	print "Can't find file ".$conf->{'gff_file'}."\n";
	exit(0);
     }else{
	print "File ".$conf->{'gff_file'}." is OK\n";
     }
}




# loop through each chr-gff in Configuration-file
foreach my $chr(@{$FB_CHR_INFO}) {
  print STDERR "handling ".$chr->{'chr_name'}." with file ".$chr->{'gff_file'}."\n" if($FB_DEBUG);


  my $slice= $db->get_SliceAdaptor()->fetch_by_region('chromosome',$chr->{chr_name});

  my $gff = FlyBaseGff->new(
                            -DB => $db,
                            -GFF=> $chr->{'gff_file'},
                            -SLICE => $slice
                           );



  #
  # process genes of gff
  #
  # ###############################################################################

  $gff->store_as_gene_object("gene");
  $gff->store_as_gene_object("gene","mRNA","gene");
  $gff->store_as_gene_object("gene","ncRNA","ncRNA");
  $gff->store_as_gene_object("gene","snRNA","snRNA");
  $gff->store_as_gene_object("gene","tRNA","tRNA");
  $gff->store_as_gene_object("gene","rRNA","rRNA");
  $gff->store_as_gene_object("gene","pseudogene","pseudogene");
  $gff->store_as_gene_object("gene","snoRNA","snoRNA");



  # 
  # dump all loaded proteins
  #
  my $cmd = "perl /acari/work6a/jhv/project_droso/bdgp4.1/cvs_checkout/ensembl-pipeline/scripts/protein_pipeline/" .
              "dump_translations.pl -dbn $FB_DBNAME -dbh $FB_DBHOST -dbpo $FB_DBPORT -dbu ensro" .
		"-pr -no_ -f/acari/work6a/jhv/project_droso/bdgp4.1/dump_seqs.fasta"; 


  print "CMD is:\n$cmd\n";
  system ("$cmd") ;



  #
  # store other stuff 
  # ncRNA, snRNA, snoRNA, tRNA etc are now child of parent 'gene', they're not stored here anymore
  #


  #
  # store all simplefeatures as referenced in the FlyBaseConf.pm
  #
  # ###############################################################################

  if ($store_simple_features) {

    foreach my $feat (@{$SIMPLE_FEATURES}) {
      my $feature_type = $feat->{type};
      my $feature_label = $feat->{label};
      my $logic_name = $feat->{logic_name};
      print "searching for simple features of type $feature_type ... ";
      my $sf_num = $gff->store_as_simple_feature($sa, $feature_type,  $logic_name, $feature_label);
      
      if ($sf_num > 0 ) { 
        print "number found + stored in db: $sf_num \n";
      }else { 
        print " NOTHING found\n" ; 
      }

    }
  }

}