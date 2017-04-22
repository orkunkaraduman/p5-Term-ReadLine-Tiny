# NAME

Term::ReadLine::Tiny - Tiny implementation of ReadLine

# VERSION

version 1.00

# SYNOPSIS

Tiny implementation of ReadLine

        use Term::ReadLine::Tiny;
        
        $term = Term::ReadLine::Tiny->new();
        while ( defined($_ = $term->readline("Prompt: ")) )
        {
                print "$_\n";
        }
        print "\n";
        
        $s = "";
        while ( defined($_ = $term->readkey(1)) )
        {
                $s .= $_;
        }
        print "\n$s\n";

# DESCRIPTION

This package is a native perls implementation of ReadLine that doesn&#39;t need any library such as &#39;Gnu ReadLine&#39;.
Also fully supports UTF-8, details in _UTF-8 section|#UTF-8_.

# Standard Term::ReadLine Methods and Functions

## ReadLine()

returns the actual package that executes the commands. If this package is used, the value is `Term::ReadLine::Tiny`.

## new(\[$name\[, IN\[, OUT\]\]\])

returns the handle for subsequent calls to following functions.
Argument _name_ is the name of the application **but not supported yet**.
Optionally can be followed by two arguments for IN and OUT filehandles. These arguments should be globs.

This routine may also get called via `Term::ReadLine-`new()&gt; if you have $ENV{PERL\_RL} set to &#39;Tiny&#39;.

## readline(\[$prompt\[, $default\]\])

interactively gets an input line. Trailing newline is removed. Returns `undef` on `EOF`.

## addhistory($line1\[, $line2\[, ...\]\])

adds lines to the history of input.

## IN()

returns the filehandle for input.

## OUT()

returns the filehandle for output.

## MinLine(\[$minline\])

If argument is specified, it is an advice on minimal size of line to be included into history.
`undef` means do not include anything into history. Returns the old value.

## findConsole()

returns an array with two strings that give most appropriate names for files for input and output using conventions `"<$in"`, `"`out&quot;&gt;.

## Attribs()

returns a reference to a hash which describes internal configuration of the package. **Not supported in this package.**

## Features()

Returns a reference to a hash with keys being features present in current implementation.
This features are present:

- _appname_ is the name of the application **but not supported yet**.
- _addhistory_ is present, always 1.
- _autohistory_ is present, always 1.
- _minline_ is present, default 1. See `MinLine` method.
- _changehistory_ is present, default 1. See `changehistory` method.

# Additional Methods and Functions

## newTTY(\[$IN\[, $OUT\]\])

takes two arguments which are input filehandle and output filehandle. Switches to use these filehandles.

## readkey(\[$echo\])

reads a key from input and echoes by _echo_ argument. Returns `undef` on `EOF`.

## changehistory(\[$changehistory\])

If argument is specified, it allows to change old history lines by argument value. Returns the old value.

## history(\[$history\])

If argument is specified ArrayRef, rewrites all history by argument elements.

**history(\[$line1\[, $line2\[, ...\]\]\])**

If first argument is not ArrayRef, rewrites all history by argument values.
Returns copy of history in ArrayRef.

## encode\_controlchar($c)

encodes if argument `c` is a control character, otherwise returns argument `c`.

# UTF-8

`Term::ReadLine::Tiny` fully supports UTF-8.

        $term = Term::ReadLine::Tiny->new();
        binmode($term->IN, ":utf8");
        binmode($term->OUT, ":utf8");
        while ( defined($_ = $term->readline("Prompt: ")) )
        {
                print "$_\n";
        }
        print "\n";

# SEE ALSO

- [Term::ReadLine::Tiny::readline](https://metacpan.org/pod/Term::ReadLine::Tiny::readline) - A non-OO package of Term::ReadLine::Tiny

# INSTALLATION

To install this module type the following

        perl Makefile.PL
        make
        make test
        make install

from CPAN

        cpan -i Term::ReadLine::Tiny

# DEPENDENCIES

This module requires these other modules and libraries:

- Term::ReadLine
- Term::ReadKey

# REPOSITORY

**GitHub** [https://github.com/orkunkaraduman/p5-Term-ReadLine-Tiny](https://github.com/orkunkaraduman/p5-Term-ReadLine-Tiny)

**CPAN** [https://metacpan.org/release/Term-ReadLine-Tiny](https://metacpan.org/release/Term-ReadLine-Tiny)

# AUTHOR

Orkun Karaduman &lt;orkunkaraduman@gmail.com&gt;

# COPYRIGHT AND LICENSE

Copyright (C) 2017  Orkun Karaduman &lt;orkunkaraduman@gmail.com&gt;

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see &lt;http://www.gnu.org/licenses/&gt;.
