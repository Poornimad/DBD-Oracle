use strict;
use warnings;
use Data::Dumper;

require utf8;

# perl 5.6 doesn't define utf8::is_utf8()
*utf8::is_utf8 = sub {
    return 0; # XXX fortunately not needed for any tests
} unless defined &{"utf8::is_utf8"};

sub long_test_cols
{
   my ($type) = @_ ;
   return 
   [
      [ lng => $type ],
   ];
}
sub char_cols
{
    [ 
        [ ch    => 'varchar2(20)' ],
        [ descr => 'varchar2(50)' ],
    ];
}
sub nchar_cols
{
    [ 
        [ nch   => 'nvarchar2(20)' ],
        [ descr => 'varchar2(50)' ],
    ];
}
sub wide_data
{
    [
        [ "\x{03}",   "control-C"        ], 
        [ "a",        "lowercase a"      ],
        [ "b",        "lowercase b"      ],
        [ "\x{08A1}", "upside down bang" ],
        [ "\x{08A2}", "cent char"        ],
        [ "\x{08A3}", "brittish pound"   ],
        [ "\x{263A}", "smiley face"      ],
    ];
}
sub extra_wide_rows
{
   return (  
      [ "\x{32263A}",   "3 byte wide char"  ],
      [ "\x{2532263A}", "4 byte wide char"  ],  
   );
}
sub narrow_data
{
    [
        [ chr(3),   "control-C"        ],
        [ "a",      "lowercase a"      ],
        [ "b",      "lowercase b"      ],
        [ chr(161), "upside down bang" ],
        [ chr(162), "cent char"        ],
        [ chr(163), "brittish pound"   ],
    ];
}
sub utf8_narrow_data
{
    [
        [ "\x{03}", "control-C"        ],
        [ "a",      "lowercase a" ],
        [ "b",      "lowercase b" ],
        [ "\x{08A1}", "upside down bang" ],
        [ "\x{08A2}", "cent char"        ],
        [ "\x{08A3}", "brittish pound"   ],
    ];
}


my $tdata_hr = {
    narrow_char => {
        cols => char_cols(),
        rows => narrow_data()
    }
    ,
    narrow_nchar => {
        cols => nchar_cols(),
        rows => narrow_data()
    }
    ,
    wide_char => {
        cols => char_cols(),
        rows => wide_data()
    }
    ,
    wide_nchar => {
        cols => nchar_cols(),
        rows => wide_data()
    }
    ,
};
sub test_data
{
    my ($which) = @_;
    return $tdata_hr->{$which};
}

sub db_handle
{

    my $dbuser = $ENV{ORACLE_USERID} || 'scott/tiger';
    my $dbh = DBI->connect('dbi:Oracle:', $dbuser, '', {
        AutoCommit => 1,
        PrintError => 1,
        ora_envhp  => 0,
    });
    return $dbh;
}
sub show_test_data
{
    my ($tdata) = @_;
    my $rowsR = $tdata->{rows};
    my $cnt = 0;
    my $vcnt = 0;
    foreach my $recR ( @$rowsR )
    {
        $cnt++;
        printf( "row: %3d: nice_string=%s byte_string=%s (%s)\n",
                $cnt ,nice_string($$recR[0]),  byte_string($$recR[0]), $$recR[1] );
    }
    return $cnt;
}

sub table { 'dbd_ora__drop_me' ; }
sub drop_table
{
    my ($dbh) = @_;
    my $table = table();
    local $dbh->{PrintError} = 0;
    $dbh->do(qq{ drop table $table });
}

sub insert_handle 
{
    my ($dbh,$tcols) = @_;
    my $table = table();
    my $sql = "insert into $table ( idx, ";
    my $cnt = 1;
    foreach my $col ( @$tcols )
    {
        $sql .= $$col[0] . ", ";
        $cnt++;
    }
    $sql .= "dt ) values( " . "?, " x $cnt ."sysdate )";
    my $h = $dbh->prepare( $sql );
    ok( $h ,"prepared: $sql" );
    return $h;
}
sub insert_test_count
{
    my ( $tdata ) = @_;
    my $rcnt = @{$tdata->{rows}};
    my $ccnt = @{$tdata->{cols}};
    return 1 + $rcnt*2 + $rcnt * $ccnt;
}
sub insert_rows #1 + rows*2 +rows*ncols tests
{
    my ($dbh, $tdata ,$csform) = @_;
    my $trows = $tdata->{rows};
    my $tcols = $tdata->{cols};
    my $table = table();
    $dbh->trace(0);
    my $sth = insert_handle($dbh, $tcols);

    my $cnt = 0;
    foreach my $rowR ( @$trows )
    {
        my $colnum = 1;
        my $attrR = $csform ? { ora_csform => $csform } : {};
        ok(  $sth->bind_param( $colnum++ ,$cnt ) ,"bind_param idx" );
        for( my $i = 0; $i < @$rowR; $i++ )
        {
            my $note = 'withOUT attribute ora_csform';
            my $val = $$rowR[$i];
            my $type = $$tcols[$i][1];
            #print "type=$type\n";
            my $attr = {};
            if ( $type =~ m/^nchar|^nvar|^nclob/i ) 
            {
                $attr = $attrR;
                $note = $attr && $csform ? "with attribute { ora_csfrom => $csform }" : "";
            } 
            ok( $sth->bind_param( $colnum++ ,$val ,$attr ) ,"bind_param " . $$tcols[$i][0] ." $note" );
        }
        ok( $sth->execute ,"insert row $cnt" );
        $cnt++;
    }
    $dbh->trace(0);
}
sub dump_table
{
    my ( $dbh ,@cols ) = @_;
    my $table = table();
    my $colstr = '';
    foreach my $col ( @cols ) {
        $colstr .= ", " if $colstr;
        $colstr .= "dump($col)"
    }
    my $sql = "select $colstr from $table order by idx" ;
    my $sth = $dbh->prepare( $sql );
    print "dumping $table\nprepared: $sql\n" ;
    my $colnum = 0;
    my @data = ();;
    $sth->execute();
    my $cnt = 0;
    while ( my $aref = $sth->fetchrow_arrayref() ) {
        $cnt++;
        my $colnum = 0;
        foreach my $col ( @cols ) {
            print "row $cnt: " ; 
            print "$col=" .$$aref[$colnum] ."\n";
            $colnum++;
        }
    }
}
sub select_handle #1 test
{
    my ($dbh,$tdata) = @_;
    my $table = table();
    my $sql = "select ";
    foreach my $col ( @{$tdata->{cols}} )
    {
        $sql .= $$col[0] . ", ";
    }
    $sql .= "dt from $table order by idx" ;
$dbh->trace(0) ;
    my $h = $dbh->prepare( $sql );
    ok( $h ,"prepared: $sql" );
$dbh->trace(0) ;
    return $h;
}
sub select_test_count 
{
    my ( $tdata ) = @_;
    my $rcnt = @{$tdata->{rows}};
    my $ccnt = @{$tdata->{cols}};
    return 2 + $ccnt + $rcnt * $ccnt * 2;
}
sub select_rows # 1 + numcols + rows * cols * 2
{
    my ($dbh,$tdata,$csform) = @_;
    my $table = table();
    my $trows = $tdata->{rows};
    my $tcols = $tdata->{cols};
    my $sth = select_handle($dbh,$tdata);
    my @data = ();
    my $colnum = 0;
    foreach my $col ( @$tcols )
    {
        ok( $sth->bind_col( $colnum+1 ,\$data[$colnum] ), "bind column " .$$tcols[$colnum][0] );
        $colnum++;
    }
    my $cnt = 0;
    $sth->execute();
    while ( $sth->fetch() )
    {
        for( my $i = 0 ; $i < @$tcols; $i++ )
        {
            my $res = $data[$i];
            my $is_utf8 = utf8::is_utf8( $res ) ? "(uft8 string)" : "";
            cmp_ok( byte_string($res), 'eq',
                    byte_string($$trows[$cnt][$i] ),
                    "byte_string test of row $cnt; column: " .$$tcols[$i][0] .$is_utf8
                    );
            if ( 1 or nls_lang_is_utf8() ) {
                cmp_ok( nice_string($res), 'eq',
                        nice_string($$trows[$cnt][$i] ),
                        "nice_string test of row $cnt; column: " .$$tcols[$i][0] .$is_utf8
                        );
            } else {
                cmp_ok( $res, 'eq',$$trows[$cnt][$i],
                        "nice_string test of row $cnt; column: " .$$tcols[$i][0] .$is_utf8
                        );
            }
            $sth->trace(0) if $cnt >= 3 ;
        }
        $cnt++;
    }
    $sth->trace(0);
    my $trow_cnt = @$trows;
    cmp_ok( $cnt, '==', $trow_cnt, "number of rows fetched" );
}
sub create_table 
{
    my ($dbh,$tdata,$drop) = @_;
    my $tcols = $tdata->{cols};
    my $table = table();
    my $sql = "create table $table ( idx integer, ";
    foreach my $col ( @$tcols )
    {
        $sql .= $$col[0] . " " .$$col[1] .", ";
    }
    $sql .= " dt date )";

    drop_table( $dbh ) if $drop;
    #$dbh->do(qq{ drop table $table }) if $drop;
    $dbh->do($sql);
    if ($dbh->err && $dbh->err==955) {
        $dbh->do(qq{ drop table $table });
        warn "Unexpectedly had to drop old test table '$table'\n" unless $dbh->err;
        $dbh->do($sql);
    } else {
       #$sql =~ s/ \( */(\n\t/g;
       #$sql =~ s/, */,\n\t/g;
       print "$sql\n" ;
    }
    return 1;
#    ok( not $dbh->err, "create table $table..." );
}



sub show_db_charsets
{
    my ( $dbh ) = @_;
    #verify the NLS NCHAR character set is 'UTF8'
    my $paramsH = $dbh->ora_nls_parameters();
    #warn Dumper( $paramsH );
    print "Database character set is " .$paramsH->{NLS_CHARACTERSET} ."\n";
    print "Database NCHAR character set is " .$paramsH->{NLS_NCHAR_CHARACTERSET} ."\n";
}
sub db_is_ascii    { my ($dbh) = @_; return  ( $dbh->ora_nls_parameters()->{'NLS_CHARACTERSET'}       =~ m/US7ASCII/i ); }
sub db_is_utf8     { my ($dbh) = @_; return  ( $dbh->ora_nls_parameters()->{'NLS_CHARACTERSET'}       =~ m/UTF/i ); }
sub nchar_is_utf8  { my ($dbh) = @_; return  ( $dbh->ora_nls_parameters()->{'NLS_NCHAR_CHARACTERSET'} =~ m/UTF/i ); }

sub nls_lang_is_utf8
{
   return 0 if not defined $ENV{NLS_LANG};
   return ( $ENV{NLS_LANG} =~ m/utf8/i );
}
sub set_nls_nchar
{
    my ($cset,$verbose) = @_;
    if ( defined $cset ) {
        $ENV{NLS_NCHAR} = "$cset"
    } else {
        undef $ENV{NLS_NCHAR};
    }
    print defined $ENV{NLS_NCHAR} ?
        "set \$ENV{NLS_NCHAR}=$cset\n" :
        "set \$ENV{NLS_LANG}=undef\n"
            if defined $verbose;
}

sub set_nls_lang_charset
{
    my ($lang,$verbose) = @_;
    if ( $lang ) {
        $ENV{NLS_LANG} = "AMERICAN_AMERICA.$lang";
        print "set \$ENV{NLS_LANG}=AMERICAN_AMERICA.$lang\n" if ( $verbose );
    } else {
        $ENV{NLS_LANG} = "";
        print "set \$ENV{NLS_LANG}=''\n" if ( $verbose );
    }
}

sub _achar { chr(ord("@")+$_[0]); }
sub byte_string { my $ret = join( "|" ,unpack( "C*" ,$_[0] ) ); return $ret; }
sub nice_string {
    my @chars = map { $_ > 255 ?                  # if wide character...
          sprintf("\\x{%04X}", $_) :  # \x{...}
          chr($_) =~ /[[:cntrl:]]/ ?  # else if control character ...
          sprintf("\\x%02X", $_) :    # \x..
          chr($_)                     # else as themselves
    } unpack("U*", $_[0]);           # unpack Unicode characters
   
   foreach my $c ( @chars )
   {
      if ( $c =~ m/\\x\{08(..)}/ ) {
         $c .= "='" .chr(hex($1)) ."'";
      }
   }
   my $ret = join("",@chars); 

}


sub view_with_sqlplus
{
    my ( $use_nls_lang ,$tdata ) = @_ ;
    my $table = table();
    my $tcols = $tdata->{cols};
    my $sqlfile = "sql.txt" ;
    my $cols = 'idx,nch_col' ;
    open F , ">$sqlfile" or die "could open $sqlfile";
    print F $ENV{ORACLE_USERID} ."\n";
    my $str = qq(
col idx form 99
col ch_col form a8
col nch_col form a16
select $cols from $table;
) ;
    print F $str;
    print F "exit;\n" ;
    close F;
    
    my $nls='unset';
    $nls = $ENV{NLS_LANG} if $ENV{NLS_LANG};
    $ENV{NLS_LANG} = '' if not $use_nls_lang;
    print "From sqlplus...$str\n  ...with NLS_LANG = $nls\n" ;
    system( "sqlplus -s \@$sqlfile" );
    $ENV{NLS_LANG} = $nls if $nls ne 'unset';
    unlink $sqlfile;
}



1;
