#!perl -w
#written by Lincoln A Baxter (lab@lincolnbaxter.com)

use strict;
#use warnings;
use Test::More;

use DBI qw(:sql_types);
use DBD::Oracle qw( :ora_types ORA_OCI SQLCS_NCHAR );

unshift @INC ,'t';
require 'nchar_test_lib.pl';

my $dbh;
$| = 1;
SKIP: {

    plan skip_all => "Unable to run unicode test, perl version is less than 5.6" unless ( $] >= 5.006 );
    eval {
       require utf8;
       import utf8;
    };
    plan skip_all => "Could not require or import utf8" if ($@);
    plan skip_all => "ORC_OCI < 8" if (! ORA_OCI >= 8);

    set_nls_lang_charset( 'AL32UTF8' ,1 );
    $dbh = db_handle();

    plan skip_all => "Not connected to oracle" if not $dbh;
    plan skip_all => "Oracle version < 9.2" if 0; # need a oracle 9i version test.... 
    plan skip_all => "Database character set is not UTF8" if not db_is_utf8($dbh) ;
    print "testing utf8 with char columns (wide mode database)\n" ;

    my $tdata = test_data( 'wide_char' );
    my $testcount = 0 #create table
                  + insert_test_count( $tdata )
                  + select_test_count( $tdata ) * 1;
                  ;

    plan tests => $testcount; 
    show_test_data( $tdata ,0 );
    drop_table($dbh);
    create_table( $dbh, $tdata );
    insert_rows( $dbh, $tdata ,SQLCS_NCHAR);
    dump_table( $dbh ,'ch' ,'descr' );
    select_rows( $dbh, $tdata );
}

END {
    eval {
        local $dbh->{PrintError} = 0;
	     drop_table($dbh) if $dbh and not $ENV{'DBD_SKIP_TABLE_DROP'};
    };
}
