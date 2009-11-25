#!/usr/bin/perl -w
use strict;
use Bio::DB::SeqFeature::Store;
use Getopt::Long;
use Env qw(HOME);

my ($user,$pass,$dbname_from,$dbname_to,$host);
$host ='localhost';
my $prefix;
my $debug = 0;
my $to_feature   = 'gene:Broad';
my $from_feature = 'gene:JGI';

my ($mercator_dir,$output);
my ($genome_from,$genome_to);
GetOptions(
	   'v|verbose!' => \$debug,
	   'u|user:s' => \$user,
	   'p|pass:s' => \$pass,
	   'host:s'   => \$host,
	   'df|dbfrom:s'   => \$dbname_from,
	   'dt|dbto:s'     => \$dbname_to,
	   
	   'f|from:s'   => \$from_feature,
	   't|to:s'     => \$to_feature,
	   'gf|genomefrom:s' => \$genome_from,
	   'gt|genometo:s' => \$genome_to,
	   
	   'm|mercator:s' => \$mercator_dir, # alignment dir
	   'output:s'  => \$output,
	   );

unless(  defined $dbname_from ) {
    die("no dbname_from provided\n");
}

unless(  defined $dbname_to ) {
    die("no dbname_to provided\n");
}

unless( defined $mercator_dir && -d $mercator_dir ) {
    die("cannot open $mercator_dir, provide with -m or --mercator\n");
}

if( $output && $output ne '-' ) { 
    open($output => ">$output" ) || die $!;
} else {
    $output = \*STDOUT;
}

unless( defined $genome_from ) {
    die("must provide a query genome name with -gf or --genomefrom\n");
}

unless( defined $genome_to ) {
    die("must provide a query genome name with -gt or --genometo\n");
}

($user,$pass) = &read_cnf($user,$pass) unless $pass && $user;
my $dsn = sprintf('dbi:mysql:database=%s;host=%s',$dbname_from,$host);
my $dbh_from = Bio::DB::SeqFeature::Store->new(-adaptor => 'DBI::mysql',
					       -dsn     => $dsn,
					       -user    => $user,
					       -password => $pass,
					       );

$dsn = sprintf('dbi:mysql:database=%s;host=%s',$dbname_to,$host);
my $dbh_to = Bio::DB::SeqFeature::Store->new(-adaptor => 'DBI::mysql',
					     -dsn     => $dsn,
					     -user    => $user,
					     -password => $pass,
					     );

my $iter = $dbh_from->get_seq_stream(-type => $from_feature);
my (undef,$fromsrc) = split(/:/,$from_feature);
my (undef,$tosrc) = split(/:/,$to_feature);

print $output join("\t", qw(GENE_FROM MRNA_FROM CHROM_FROM 
			    START_FROM STOP_FROM STRAND_FROM 
			    GENE_TO MRNA_TO START_TO STOP_TO 
			    STRAND_TO SINGLE_MATCH)), "\n";

while( my $gene = $iter->next_seq ) {

    my $name = $gene->name;
    my ($mRNA) = $gene->get_SeqFeatures('mRNA'); # 1st mRNA for now
    my $t_name = $mRNA->name;
    my $arg = sprintf("sliceAlignment %s %s %s %d %d %s",
		      $mercator_dir, $genome_from,
		      $gene->seq_id, $gene->start, $gene->end,
		      $gene->strand > 0 ? '+' : '-');
    open(my $map => "$arg 2>/dev/null | grep '>' | " ) || die "Cannot open slice with $arg\n";
    my $seen = 0;
    while(<$map>) {
	if( /^>(\S+)\s+([^:]+):(\d+)\-(\d+)([+-])/ ) {
	    my ($genome,$chrom,$start,$end,$strand) = ($1,$2,$3,$4,$5);	
	    if( $genome eq $genome_to ) {
		$seen = 1;
		my $segment = $dbh_to->segment($chrom,$start,$end);
		my @genes = $segment->features(-type => $to_feature);
		if( @genes ) {
		    for my $g ( @genes ) {
			my ($to_mRNA) = $g->get_SeqFeatures('mRNA');
			print $output join("\t",
					   $name, $t_name,$gene->seq_id,
					   $gene->start,$gene->end,
					   $gene->strand,
					   
					   $g->name,$to_mRNA->name,
					   $g->seq_id,$g->start,$g->end,
					   $g->strand,
					   @genes == 1 ? 'yes' : 'no'),"\n";
		    }
		} else {
		    print $output join("\t",
				       $name, $t_name,$gene->seq_id,
				       $gene->start,$gene->end,$gene->strand,
				       '','','','','','NO_GENES_IN_INTERNAL'),"\n";
		}
	    }
	}
    }
    unless( $seen ) {
	print $output join("\t",
			   $name, $t_name,$gene->seq_id,
			   $gene->start,$gene->end,$gene->strand,
			   '','','','','','NO_SYNTENIC_ALIGNMENT'),"\n";
    }
    last if $debug;
}


# read the .my.cnf file
sub read_cnf {
    my ($user,$pass) = @_;
    if( -f "$HOME/.my.cnf") {
        open(IN,"$HOME/.my.cnf");
        while(<IN>) {
            if(/user(name)?\s*=\s*(\S+)/ ) {
                $user = $2;
            } elsif( /pass(word)\s*=\s*(\S+)/ ) {
                $pass = $2;
            }
        }
        close(IN);
    }
    return ($user,$pass);
}