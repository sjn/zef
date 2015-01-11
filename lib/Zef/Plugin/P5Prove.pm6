use Zef::Phase::Testing;
role Zef::Plugin::P5Prove does Zef::Phase::Testing {
    multi method test(*@dirs) {
        my $cmd = -> *@libs {
            "prove -V && "
           ~"(cd $*CWD && "
               ~"prove -v -e '"
                   ~ "perl6 " 
                   ~ @libs.map({ "-I$_" }).join(' ')
                   ~ "' {~@dirs} )";
        }

        # test /lib if /blib/lib fails or does not exist
        'blib/lib'.IO.e && shell($cmd('blib/lib')).exit == 0
             ?? True  
             !! shell($cmd('lib')).exit == 0
                ?? ("ERROR: Source code passes test; Precomp fails".say andthen True)
                !! False;
    }
}