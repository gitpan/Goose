package Goose;

=head1 NAME

Goose - Multi-Use utility for manipulating subroutines, classes and more.

=head1 DESCRIPTION

What this module attempts to do is make a developers life easier by allowing them to manage and manipulate subroutines and modules. You can override a subroutine, then 
restore it as it was originally, create after, before and around hook modifiers, delete subroutines, or even tag every subroutine in a class to let you know when each one 
is being run, which is great for debugging.
On top of all this Goose offers some minor OOP framework utilities like C<extends>, C<exports>, C<accessor>, C<has> and C<chainable>. Of course if you need more I would advise L<Moose> or L<Mouse>.
Newer versions of Goose include C<Goose::Utils> which offers some basic, yet extremely handy functions for common situations, and access to L<Try::Tiny> just by a small import attribute, C<:Try>.

=head1 SYNOPSIS

    # Single file

    use Goose;

    sub greet { print "Hello, World!"; }

    greet; # prints Hello, World!

    override 'greet' => sub {
        print "Goodbye, World!";
    };

    greet; # now prints Goodbye, World!

    restore 'greet'; # restores it back to its original state

Changing a class method, by example

    # Foo.pm

    use Goose qw/:Class/;

    sub hello {
        my $self = shift;

        $self->{name} = "World";
    }

    # test.pl

    use Foo;

    my $foo = Foo->new;

    Foo->override( 'hello' => sub {
        my $self = shift;

        $self->{name} = "Town";
    });

    print "Hello, " . $foo->hello . "!\n"; # prints Hello, Town!

    Foo->restore('hello');

    print "Hello, " . $foo->hello . "!\n"; # prints Hello, World!

=cut

$Goose::VERSION = '0.009';
$Goose::Subs = {};
$Goose::Imports = [];
$Goose::Classes = [];
$Goose::Debug = 0;

sub import {
    my ($class, @args) = @_;
    my $pkg = caller;
    
    my $moosed;
    my $wantmoose;
    if (@args > 0) {
        for (@args) {
            feature::feature->import( ':5.10' )
                if $_ eq ':5.010';
            
            _debug_on()
                if $_ eq ':Debug';
            
            _setup_moosed($pkg)
                if $_ eq ':Class' or $_ eq ':Antlers';
            
            $wantmoose = 1
                if $_ eq ':UseMoose';

            $moosed = 1
                if $_ eq ':Antlers';
            _setup_utils($pkg)
                if $_ eq ':Utils';
            _add_try($pkg)
                if $_ eq ':Try';
            
        }
    }

    if ($wantmoose) {
        _import_def(
            $pkg,
            undef,
            qw/
                create
                sub_alert
                clone
                exports
                have
                drop_sub
                sub_run
            /,
        );
    }
    else {
        _import_def(
            $pkg,
            undef,
            qw/
                override
                restore
                after
                before
                create
                sub_alert
                clone
                exports
                have
                around
                drop_sub
                sub_run
            /,
        );
        if ($moosed) {
            _import_def(
                $pkg,
                undef,
                qw/ 
                    has
                /,
            );
        }
    }
}

sub _add_try {
    my $pkg = shift;
    use Try::Tiny;
    *{"$pkg\::try"} = \&{"Try::Tiny::try"};
    *{"$pkg\::catch"} = \&{"Try::Tiny::catch"};
}

sub drop_sub {
    my ($class, $sub);
    if (@_ < 2) {
        $sub = shift;
        $class = getscope();
    }
    else {
        ($class, $sub) = @_;
    }
    $class = \%{"$class\::"};
    delete $class->{$sub};
}

sub extends {
    my (@classes) = @_;
    my $pkg = getscope();

    if ($pkg eq 'main') {
        warn "Cannot extend main";
        return ;
    }

    _extend_class( \@classes, $pkg );
}

sub _extend_class {
    my ($mothers, $class) = @_;

    foreach my $mother (@$mothers) {
        # if class is unknown to us, import it (FIXME)
        unless (grep { $_ eq $mother } @$Goose::Classes) {
            eval "use $mother";
            warn "Could not load $mother: $@"
                if $@;
        
            $mother->import;
        }
        push @$Goose::Classes, $class;
    }

    {
        no strict 'refs';
        @{"${class}::ISA"} = @$mothers;
    }
}

sub _setup_utils {
    my $class = shift;
    extends 'Goose::Utils';
    _import_def ($class, 'Goose::Utils', qw/ref_has is_number count/);
}

sub _setup_moosed {
    my $class = shift;

    *{ "$class\::new" } = sub { return bless { }, $class };
    _import_def ($class, undef, qw/extends accessor has chainable/);
}

sub _import_def {
    my ($pkg, $from, @subs) = @_;
    if ($from) {
        for (@subs) {
            *{$pkg . "::$_"} = \&{"$from\::$_"};
        }
    }
    else { 
        for (@subs) {
            *{$pkg . "::$_"} = \&$_;
            push @{$Goose::Imports}, $_;
        }
    }
}

sub override {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    my $warn = 0;
    if (! $pkg->can($name)) {
        warn "Cannot override a subroutine that doesn't exist";
        $warn = 1;
    }

    if ($warn == 0) {
        _debug("Override called for sub '$name' in package '$pkg'");
 
        _add_to_subs("$pkg\:\:$name");
        *$name = sub { $sub->(@_) };
        *{$pkg . "::$name"} = \*$name;
    }
}

sub _add_to_subs {
    my $sub = shift;

    if (! exists $Goose::Subs->{$sub}) {
        $Goose::Subs->{$sub} = {};
        $Goose::Subs->{$sub} = \&{$sub};
        _debug("$sub does not exist. Adding to Subs list\n");
    }
}

sub restore {
    my ($pkg, $sub) = @_;

    if (scalar @_ > 1) {
        my ($pkg, $sub) = @_;
    }
    else {
        $sub = $pkg;
        $pkg = caller;
    }

    $sub = "$pkg\:\:$sub";
    
    if (! exists $Goose::Subs->{$sub}) {
        _debug("Failed to restore '$sub' because it's not in the Subs list. Was it overriden or modified by a hook?");
        warn "I have no recollection of '$sub'";
        return 0;
    }

    *{$sub} = $Goose::Subs->{$sub};
    _debug("Restores sub $sub");
}

sub after {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    $full = "$pkg\:\:$name";
    my $alter_sub;
    my $new_code;
    my $old_code;
    die "Could not find $name in the hierarchy for $pkg\n"
        if ! $pkg->can($name);

    $old_code = \&{$full};
    *$name = sub {
        $old_code->(@_);
        $sub->(@_);
    };
    
    _add_to_subs($full);
    *{$full} = \*$name;
    _debug("Added after hook modified to '$name'");
}

sub before {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    if (ref($name) eq 'ARRAY') {
        for my $subname (@$name) {
            $full = "$pkg\:\:$subname";
            my $alter_sub;
            my $new_code;
            my $old_code;
            die "Could not find $subname in the hierarchy for $pkg\n"
                if ! $pkg->can($subname);

            $old_code = \&{$full};
            *$subname = sub {
                $sub->(@_);
                $old_code->(@_);
            };

            _add_to_subs($full);
            *{$full} = \*$subname;
            _debug("Added before hook modifier to $subname");
        }
    }
    else {
        $full = "$pkg\:\:$name";
        my $alter_sub;
        my $new_code;
        my $old_code;
        die "Could not find $name in the hierarchy for $pkg\n"
            if ! $pkg->can($name);

        $old_code = \&{$full};
        *$name = sub {
            $sub->(@_);
            $old_code->(@_);
        };

        _add_to_subs($full);
        *{$full} = \*$name;
        _debug("Added before hook modifier to $name");
    }
}

sub around {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    $full = "$pkg\:\:$name";
    die "Could not find $name in the hierarchy for $pkg\n"
        if ! $pkg->can($name);

    my $old_code = \&{$full};
    *$name = sub {
        $sub->($old_code, @_);
    };
     
    _add_to_subs($full);
    *{$full} = \*$name;  
}

sub getscope {
    my ($self) = @_;

    if (defined $self) { return ref($self); }
    else { return scalar caller(1); }
}

sub create {
    my ($pkg, $name, $sub) = @_;

    if (scalar @_ > 2) {
        ($pkg, $name, $sub) = @_;
    }
    else {
        ($name, $sub) = ($pkg, $name);
        $pkg = caller;
    }

    my $warn = 0;
    if ($pkg->can($name)) {
        warn "You can't create a subroutine that already exists. Did you mean 'override'?";
        $warn = 1;
    }
    
    if ($warn == 0) {
        my $full = "$pkg\:\:$name";
        *$name = sub { $sub->(@_); };

        *{$full} = \*$name;
        _debug("Created new subroutine '$name' in '$pkg'");
    }
}

sub sub_alert {
    my $pkg = shift;
    my $module = __PACKAGE__;

    for (keys %{$pkg . "::"}) {
        my $sub = $_;

        unless ($sub eq uc $sub) {
            $pkg->before($sub => sub { print "[$module/Sub Alert] '$sub' called from $pkg\n"; })
                unless grep { $_ eq $sub } @{$Goose::Imports};
        }
    }
}

sub clone {
    my ($name, %opts) = @_;

    my $from;
    my $to;
    foreach my $opt (keys %opts) {
        $from = $opts{$opt}
            if $opt eq 'from';
        $to = $opts{$opt}
            if $opt eq 'to';
    }

    if ((! $from || ! $to )) {
        warn "clone(): 'from' and 'to' needed to cast this spell";
        return ;
    }

    if (! $from->can($name)) {
        warn "clone(): $from does not have the method '$name'";
        return ;
    }

    *{$to . "::$name"} = \*{$from . "::$name"};
}
        
sub exports {
    my ($name, %args) = @_;

    my $class = caller;
    my $into = [];
    foreach my $opt (keys %args) {
        if ($opt eq 'into') {
            if (ref($args{into}) eq 'ARRAY') {
                for my $gc (@{$args{into}}) {
                    push @$into, $gc;
                }
            }
            else { push @$into, $args{into}; }
        }
    }
    
    my $code = sub { $class->$name(@_); };
    if (scalar @$into > 0) {
        for my $c (@$into) {
            if (! _class_exists($c)) {
                warn "Can't export $name into $c\:: because class $c does not exist";
                next;
            } 
            *{"$c\::$name"} = \*{"$class\::$name"};
        }
    }
    return;
}

sub have {
    my ($class, $method, %args) = @_;

    my $can = $class->can($method) ? 1 : 0;
    my $then;
    for $opt (keys %args) {
        if ($opt eq 'then') {
            if ($can) { $args{$opt}->($class, $method); }
        }
        if ($opt eq 'or') {
            if (! $can) {
                if (ref $args{$opt} eq 'CODE') {
                    $args{$opt}->(@_);
                    return 0;
                }
                else { warn $args{$opt}; }
            }
        }
    }
}

sub has {
    my ($name, %args) = @_;
    my $pkg = getscope();
    my $rtype;
    my $default;
    foreach my $key (keys %args) {
        $rtype = $args{is}
            if $key eq 'is';
        $default = $args{default}
            if $key eq 'default';
    }
    if ($rtype eq 'ro') {
        if (! $default) {
            warn "Redundant null static accessor '$name'";
        }
        *{$pkg . "::$name"} = sub {
            my ($class, $val) = @_;
            if ($val) {
                warn "Cannot alter a Read-Only accessor";
                return ;
            }
            return $default||0;
        };
    }
    else {
        *{$pkg . "::$name"} = sub {
            my ($class, $val) = @_;
            if ($val) {
                *{$pkg . "::$name"} = sub { return $val; }; return $val;
            }
            else {
                return $default||0;
            }
        };
    }
}
        

sub accessor {
    my ($name, $value) = @_;
    my $pkg = caller;

    *{$pkg . "::$name"} = sub {
        my ($class, $val) = @_;
        if ($val) { *{$pkg . "::$name"} = sub { return $val; }; return $val; }
        else { return $value; }
    };
}

sub chainable {
    my ($method, %args) = @_;
    my $pkg = getscope();
    my $bless;
    my $class;
    if (! $pkg->can($method)) {
        warn "Cannot chain subroutine that doesn't exist";
        return ;
    }
    
    foreach my $var (keys %args) {
        if ($var eq 'class') {
            $class = $args{$var};
        }    
        if ($var eq 'bless') {
            $bless = $args{$var};
        }
    }

    $pkg->after( $method => sub {
        my $self = shift;
        if (! $bless) { return bless $self, $class; }
        else { return bless $self->{$bless}, $class; }
    });
} 

sub sub_run {
    my ($class,$subs, $methods) = @_;
    
    my $name;
    my $orig;
    for my $sub (@$subs) {
        *{"$class\::$sub"}->($class, @$methods);
    }
}

sub _debug_on {
    $Goose::Debug = 1;
    _debug("Goose debugging ON");
}

sub _debug {
    print '[debug] ' . shift . "\n"
        if $Goose::Debug == 1;
}

sub _class_exists {
    my $class = shift;
    
    # i hard a hard time finding out how to go about this
    # this is all i could think of
    # every class should at _least_ have BEGIN, so count the keys!
    $class = "$class\::";
    return scalar(keys(%{$class}));
}

=head1 IMPORT ATTRIBUTES

When you C<use Goose> there are currently a couple of options you can pass to it. One is C<:5.010>. This will import the 5.010 feature.. this has nothing to do 
with subs, but I like this module, so it's there. The other is C<:Debug>. If for some reason you want some kind of debugging going on when you override, restore, create 
or create hook modifiers then this will enable it for you. It can get verbose, so use it only when you need to.

    use Goose ':5.010';

    say "It works!";

    #--

    use Goose qw/:5.010 :Debug/;

    create 'this_sub' => sub { }; # notifies you with [debug] that a subroutine was createed

The newest addition to Goose is C<Goose::Utils>. It contains features that make doing simple things in Perl, more simple. Like counting the number of elements in a HashRef or ArrayRef, 
returning the type of a number or if it is even a number, and searching a reference for a particular key (Works for arrayref and hashref).
To use these utilities just import C<:Utils>.

    use Goose ':Utils';
    
    my $h = {
        name => 'foo',
        baz  => { foo => 'bar' },
        test => 'za',
    };
    
    print count($h); # returns 4

    my $a = [1,2,3,4,'a'];
    print count($a); # returns 5

    if (ref_has($h, 'baz')) {} # true

    is_number(8); # Integer
    is_number("7"); # Integer
    is_number(5.2); # Float
    is_number("  1.0 "); # Float
    is_number('a'); # 0 

You can use L<Try::Tiny> within Goose for try/catching. Just import C<:Try> and you've got access to C<try> and C<catch>.

    use Goose ':Try';
    
    try {
        die "Oh gnoes";
    }
    catch {
        say "Last error: $_";
    };

Now with importing we can turn a perfectly normal package into a class, sort of. It saves you from creating C<sub new { ... }>

    # MyApp.pm
    package MyApp;

    use Goose qw/:Class/;

    1;

    # test.pl
    my $foo = MyApp->new;

    MyApp->create( name => sub {
        my ($self, $name) = @_;

        $self->{name} = $name;
        say "Set name to $name";
    });

    MyApp->create( getName => sub { return shift->{name}; });

    $foo->name('World');

    say $foo->getName;

Above we created a basically blank package, passed :Class to the Goose import method, then controlled the entire class from C<test.pl>.
As of 0.007, C<:Class> now offers B<extending> using C<extends> which inherits a specified class, similar to C<use base>

=head1 METHODS 

=head2 override

Overrides a subroutine with the one specified. On its own will override the one in the current script, but if you call it from 
a class, and that class is visible, then it will alter the subroutine in that class instead.
Overriding a subroutine inherits everything the old one had, including C<$self> in class methods.


    override 'subname' => sub {
        # do stuff here
    };

    # class method
    FooClass->override( 'subname' => sub {
        my $self = shift;

        # do stuff
    });

=head2 drop_sub

Deletes an entire subroutine from the current package, or a remote one. Please be aware this is non-reversable. There is no recycle bin for subroutines unfortunately. Not yet, anyway.

    package MyBin;

    sub test { print "Huzzah!" }
    
    __PACKAGE__->test; # prints Huzzah!
    
    drop_sub 'test'

    __PACKAGE__->test; # fails, because there's no subroutine named 'test'

    use AnotherPackage;
    AnotherPackage->drop_sub('test'); # removes the 'test' method from 'AnotherPackage'

=head2 restore

Restores a subroutine to its original state.

    override 'foo' => sub { };

    restore 'foo'; # and we're back in the room

=head2 after

Adds an after hook modifier to the subroutine. Anything in the after subroutine is called directly after the original sub.
Hook modifiers can also be restored.

    sub greet { print "Hello, "; }
    
    after 'greet' => sub { print "World!"; };

    greet(); # prints Hello, World!

=head2 before

Very similar to C<after>, but calls the before subroutine, yes that's right, before the original one.

    sub bye { print "Bye!"; }

    before 'bye' => sub { print "Good "; };

    bye(); # prints Good Bye!

Fancy calling C<before> on multiple subroutines? Sure. Just add them to an array.

    sub like {
        my ($self, $what) = @_;
        
        print "I like $what\n";
    }
    
    sub dislike {
        my ($self, $what) = @_;
        
        print "I dislike $what\n";
    }

    before [qw( like dislike )] => sub {
        my ($self, $name) = @_;

        print "I'm going to like or dislike $name\n";
    };

=head2 around

Around gives the user a bit more control over the subroutine. When you create an around method the first argument will be the old method, the second is C<$self> and the third is any arguments passed to the original subroutine. In a away this allows you to control the flow of the entire subroutine.

    sub greet {
        my ($self, $name) = @_;

        print "Hello, $name!\n";
    }

    # only call greet if any arguments were passed to Class->greet()
    around 'greet' => sub {
        my $method = shift;
        my $self = shift;

        $self->$method(@_)
            if @_;
    };

=head2 create

"Conjurs" a subroutine into the current script or a class. By create I just mean create. It will not allow you to override a subroutine 
using create.

    create 'test' => sub { print "In test\n"; }
    test;

    Foo->create( hello => sub {
        my ($self, $name) = @_;

        print "Hello, $name!\n";
    });

=head2 sub_alert

B<Very verbose>: Adds a before hook modifier to every subroutine in the package to let you know when a sub is being called. Great for debugging if you're not sure a method is being ran.

    __PACKAGE__->sub_alert;

    # define a normal sub
    sub test { return "World"; }

    say "Hello, " . test(); # prints Hello, World but also lets you know 'test' in 'package' was called.

=head2 clone

Clones a subroutine from one class to another. Probably rarely used, but the feature is there if you need it.

    use ThisPackage;
    use ThatPackage;

    clone 'subname' => ( from => 'ThisPackage', to => 'ThatPackage' );

    ThatPackage->subname; # duplicate of ThisPackage->subname

=head2 extends

To use C<extends> you need to have C<:Class> imported. This will extend the given class thereby inheriting it into 
the current class.

    package Foo;

    sub baz { }

    1;

    package Fooness;

    use Goose qw/:Class/;
    extends 'Foo';

    override 'baz' => sub { say "Hello!" };
    Magic->baz;

    1;

The above would not have worked if we had not have extended 'Foo'. This is because when we 
inheritted it, we also got access to its C<baz> method.

=head2 exports

Exporting subroutines is not generally needed or a good idea, so Goose will only allow you to export one subroutine at a time. 
Once you export the subroutine you can call it into the given package without referencing the class of the subroutines package.

    package Foo;
    
    use Goose;
    
    exports 'boo' => ( into => [qw/ThisClass ThatClass/] );
    exports 'spoons' => ( into => 'MyClass' );

    sub spoons { print "Spoons!\n"; }
    sub boo { print "boo!!!\n"; }
    sub test { print "A test\n"; }

    package ThisClass;

    use Foo;

    boo(); # instead of Foo->boo;
    test(); # this will fail because it was not exported

=head2 have

A pretty useless function, but it may be used to silently error, or create custom errors for failed subroutines. Similar to $class->can($method), but with some extra sugar.

    package Foo;

    use Goose;

    sub test { }
    
    package MyApp;

    use Goose qw/:5.010/;
    
    use Foo;
    
    my $success = sub {
        my ($class, $name) = @_;
      
        say "$class\::$name checked out OK";  
        after $class => sub {
            say "Successfully ran $name in $class";
        };
    };

    Foo->have( 'test' => ( then => $success ) );

On success the above will run whatever is in C<then>. But what about errors? If this fails it will not do anything - sometimes you just want silent deaths, right? You can create custom 
error handlers by using C<or>. This parameter may take a coderef or a string.

    package Foo;
    
    use Goose;

    sub knife { }
    
    package MyApp;

    use Goose qw/:5.010/;

    use Foo;

    my $error = sub {
        my ($class, $name) = @_;

        say "Oh dear! $class failed because no method $name exists";
        # do some other funky stuff if you wish
    };

    Foo->have( 'spoon' => ( then => $success, or => $error ) );

Or you may wish for something really simply.

    Foo->have( 'spoon' => ( then => $success, or => 'There is no spoon') );

This one will simply throw a warning with C<warn> so to still execute any following code you may have.

=head2 accessor

Simply creates an accessor for the current class. You will need to first import C<:Class> when using Goose before you can use C<accessor>. When you create an 
accessor it adds the subroutine for you with the specified default value. The parameter in the subroutine will cause its default value to change to whatever that is.

    package FooClass;

    use Goose qw/:Class/;

    accessor 'name' => 'World'; # creates the subroutine 'name'

    1;

    package main;

    use FooClass;

    my $foo = FooClass->new;
    print "Hello, " . $foo->name; # prints Hello, World

    $foo->name('Foo');
    
    print "Seeya, " . $foo->name; # prints Seeya, Foo

=head2 chainable

Another C<:Class> only method is C<chainable>. It doesn't really do anything you can't do yourself, but I find it helps to keep a visual of your chains at the top of your code so you can see in plain sight 
where they are leading you. Let's look at an example.
As of 0.015 you can now bless a different reference other than C<$self>. Whatever you bless will be C<$self->{option}>.

    # test.pl

    use Greeter;
    
    my $foo = Greeter->new;
    print "Hello, " . $foo->greet('World')->hello;

    # Greeter.pm
    package Greeter;

    use Greet::Class;
    use Goose qw/:Class/;

    chainable 'greet' => ( class => 'Greet::Class' );

    sub greet {
        my ($self, $name) = @_;
        $self->{_name} = $name;
    }

    # Greet/Class.pm
    package Greet;
    
    sub hello {
        my $self = shift;

        return $self->{_name};
    }

If you don't want to bless the entire C<$self>, use C<bless>.

    chainable 'greet' => ( bless => '_source', class => 'Greet::Class' );

    sub greet {
        my $self = shift;

        $self->{_source} = {
            _name => $self->{_name},
        };
    }

=head2 has

Create a more advanced accessor similar to Moose (but not as cool). It currently supports C<is> and C<default>. Don't forget to import C<:Antlers>

    package Foo;

    use Goose qw/:Antlers/;

    has name => ( is => 'rw' );
    has x => ( is => 'ro', default => 7 );
    print __PACKAGE__->x; # 7
    __PACKAGE__->x(5); # BAD! It's Read-Only!!
    __PACKAGE__->name('World'); # set and return 'World'
    
=head2 sub_run

Runs multiple subroutines in a class, with arguments if necessary. This function takes two arrayrefs, the first being the subroutines you want to run, and the last is 
the arguments to pass to each subroutine.

    # MyApp.pm
    package MyApp;
    use Goose;

    sub greet {
        my ($self, $name) = @_;
        print "Hello, $name!\n";
    }

    sub bye {
        my ($self, $name, $where) = @_;
        print "Bye, $name. I'm going $where\n";
    }

    # run.pl
    use MyApp;
    MyApp->sub_run(
        [qw/greet bye/],
        [qw/World home/]
    );

    # Hello, World!
    # Bye, World. I'm going home

=head1 AUTHOR

Brad Haywood <brad@geeksware.net>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
