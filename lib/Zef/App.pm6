class Zef::App;

#core modes 
use Zef::Tester;
use Zef::Installer;
use Zef::Getter;
use Zef::Builder;
use Zef::Config;

# load plugins from config file
BEGIN our @plugins := $config<plugins>.list;

# when invoked as a class, we have the usual @.plugins
has @.plugins;

# override config file plugins if invoked as a class
# *and* :@plugins was passed to initializer 
submethod BUILD(:@!plugins) { 
    @plugins := @!plugins if @!plugins.defined;
}



#| Test modules in cwd
multi MAIN('test') is export { &MAIN('test', 't/') }
#| Test modules in the specified directories
multi MAIN('test', *@paths) is export {
    my $tester = Zef::Tester.new(:@plugins);
    $tester.test($_) for @paths;
}


#| Install freshness
multi MAIN('install', *@modules) is export {
    my $installer = Zef::Installer.new(:@plugins);
    $installer.install($_) for @modules;
}


#| Get the freshness
multi MAIN('get', *@modules) is export {
    my $getter = Zef::Getter.new(:@plugins);
    $getter.get($_, $*CWD) for @modules;
}


#| Build modules in cwd
multi MAIN('build') is export { &MAIN('build', $*SPEC.catdir($*CWD, 'lib')) }
#| Build modules in the specified directories
multi MAIN('build', $path) {
    my $builder = Zef::Builder.new(:@plugins);
    $builder.pre-compile($path);
}

multi MAIN('login', $user, $password?) {
    my $pass = $password // prompt 'Password: ';
    say "Password required" && exit(1) unless $pass;
    use IO::Socket::SSL;
    my $data = to-json({ username => $user, password => $pass, });
    my $sock = IO::Socket::SSL.new(:host<zef.pm>, :port(443));
    $sock.send("POST /login HTTP/1.0\r\nHost: zef.pm\r\nContent-Length: {$data.chars}\r\n\r\n{$data}");
    my %result = %(from-json($sock.recv.decode('UTF-8').split("\r\n\r\n")[1]));
    
    if %result<success> {
        say 'Login successful.';
        $config<session-key> = %result<newkey>;
        save-config;
    } 
    elsif %result<failure> {
        say "Login failed with error: {%result<reason>}";
    } 
    else {
        say 'Unknown problem -';
        say %result.perl;
    }
}

multi MAIN('register', $user, $password?) {
    my $pass = $password // prompt 'Password: ';
    use IO::Socket::SSL;
    my $data = to-json({ username => $user, password => $pass, });
    my $sock = IO::Socket::SSL.new(:host<zef.pm>, :port(443));
    $sock.send("POST /register HTTP/1.0\r\nHost: zef.pm\r\nContent-Length: {$data.chars}\r\n\r\n{$data}");
    my %result = %(from-json($sock.recv.decode('UTF-8').split("\r\n\r\n")[1]));
    
    if %result<success> {
        say 'Welcome to Zef.';
        $config<sessionkey> = %result<newkey>;
        save-config;
    } 
    elsif %result<failure> {
        say "Registration failed with error: {%result<reason>}";
    } 
    else {
        say 'Unknown problem -';
        say %result.perl;
    }
}

multi MAIN('search', *@terms) {
    use IO::Socket::SSL;
    for @terms -> $term {
        my $data = to-json({ query => $term });
        my $sock = IO::Socket::SSL.new(:host<zef.pm>, :port(443));
        $sock.send("POST /search HTTP/1.0\r\nHost: zef.pm\r\nContent-Length: {$data.chars}\r\n\r\n{$data}");
        my @results = @(from-json($sock.recv.decode('UTF-8').split("\r\n\r\n")[1]));
        say "Results for $term";
        say "Package\tAuthor\tVersion";
        for @results -> %result {
            say "{%result<name>}\t{%result<owner>}\t{%result<version>}";
        }
    }
}

multi MAIN('push', :$target = $*CWD, :@exclude?, :$force?) {
    require MIME::Base64;
    my $data = '';
    my @paths = $target.dir;
    my @files;

    while @paths.shift -> $path {
        given $path.IO {
            when @exclude { say "skipping $path" }
            when :d { for .dir -> $io { @paths.push: $io } }
            when :f & { @files.push($_) }
        }            
    }

    my @failures;
    for @files -> $path {
        my $buff;
        try {
            $buff = $buff // MIME::Base64.encode-str(".$path".IO.slurp);
            CATCH { default { } }
        }
        try {
            my $b = Buf.new;
            my $f = open ".$path", :r;
            while !$f.eof { 
                $b ~= $f.read(1024); 
            }
            $f.close;
            $buff = MIME::Base64.encode($b);
            CATCH { when $path eq '/md5sum' { .say } }
        }

        if $buff !~~ Str {
            @failures.push($path);
        } 
        else {
            $data ~= "{$path}\r\n{$buff}\r\n";
        }
    }

    if !$force && @failures.elems {
        print "Failed to package the following files:\n\t";
        say @failures.join("\n\t");
    } 
    else {
        my $metf = 'META.info'.IO ~~ :f ?? 'META.info'.IO !! 'META6.json'.IO ~~ :f ?? 'META6.json'.IO !! die 'Couldn\'t find META6.json or META.info';
        my $json = to-json({ key => $config<session-key>, data => $data, meta => %(from-json($metf.slurp)) });
        my $sock = IO::Socket::SSL.new(:host<zef.pm>, :port(443));
        $sock.send("POST /push HTTP/1.0\r\nHost: zef.pm\r\nContent-Length: {$json.chars}\r\n\r\n{$json}");
        my %result = %(from-json($sock.recv.decode('UTF-8').split("\r\n\r\n")[1]));
        
        if %result<version> {
            say "Successfully pushed version '{%result<version>}' to server";
        } 
        elsif %result<error> {
            say "Error pushing module to server: {%result<error>}";
        } 
        else {
            say "Unknown error - {%result.perl}";
        }
    }
}