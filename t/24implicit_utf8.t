#!perl -w
#written by Lincoln A Baxter (lab@lincolnbaxter.com)

use strict;
#use warnings;
use Test::More;

unshift @INC ,'t';
require 'nchar_test_lib.pl';

use DBI qw(:sql_types);
use DBD::Oracle qw(:ora_types ORA_OCI SQLCS_NCHAR );

my $dbh;
$| = 1;
SKIP: {
    plan skip_all => "Unable to run 8bit char test, perl version is less than 5.6" unless ( $] >= 5.006 );
    plan skip_all => "ORA_OCI < 8" if (! ORA_OCI >= 8);

    my $cset = 'UTF8';
    set_nls_nchar( $cset ,1 ); 
    $dbh = db_handle();

    plan skip_all => "Not connected to oracle" if not $dbh;
    plan skip_all => "Oracle version < 9" if not ( ORA_OCI >= 9 ); 
    plan skip_all => "Database NCHAR character set is not a utf-N charset" if not nchar_is_utf8($dbh) ;


    print " --- testing implicit csform (dbhimp.c sets csform implicitly)\n" ;
    my $tdata = test_data( 'wide_nchar' );
    my $testcount = 0 
                  + insert_test_count( $tdata )
                  + select_test_count( $tdata ) * 1;
                  ;

    plan tests => $testcount * 2 ;
    show_test_data( $tdata ,0 );

    foreach $cset ( qw( UTF8 AL32UTF8 ))  {
        $dbh->disconnect(); undef $dbh;
        print " --- testing with NLS_NCHAR=$cset\n" ;
        SKIP: { 
            set_nls_nchar( $cset ,1 ); 
            $dbh = db_handle();
            skip "failed to connect to oracle with NLS_NCHAR=$cset" ,$testcount if not $dbh;
            drop_table($dbh);
            create_table( $dbh, $tdata );
            insert_rows( $dbh, $tdata );
            dump_table( $dbh ,'nch' ,'descr' );
            select_rows( $dbh, $tdata );
        }
    }
}

END {
    eval {
        local $dbh->{PrintError} = 0;
	     drop_table( $dbh ) if $dbh and not $ENV{'DBD_SKIP_TABLE_DROP'};
    };
}

__END__
