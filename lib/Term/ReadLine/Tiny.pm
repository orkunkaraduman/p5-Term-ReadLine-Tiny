package Term::ReadLine::Tiny;
=head1 NAME

Term::ReadLine::Tiny - Tiny implementation of ReadLine

=head1 VERSION

version 1.11

=head1 SYNOPSIS

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

=head1 DESCRIPTION

This package is a native perls implementation of ReadLine that doesn't need any library such as 'Gnu ReadLine'.
Also fully supports UTF-8, details in L<UTF-8 section|https://metacpan.org/pod/Term::ReadLine::Tiny#UTF-8>.

=head2 Keys

B<C<Enter> or C<^J> or C<^M>:> Gets input line. Returns the line unless C<EOF> or aborting or error, otherwise undef.

B<C<BackSpace> or C<^H> or C<^?>:> Deletes one character behind cursor.

B<C<UpArrow>:> Changes line to previous history line.

B<C<DownArrow>:> Changes line to next history line.

B<C<RightArrow>:> Moves cursor forward to one character.

B<C<LeftArrow>:> Moves cursor back to one character.

B<C<Home> or C<^A>:> Moves cursor to the start of the line.

B<C<End> or C<^E>:> Moves cursor to the end of the line.

B<C<PageUp>:> Change line to first line of history.

B<C<PageDown>:> Change line to latest line of history.

B<C<Insert>:> Switch typing mode between insert and overwrite.

B<C<Delete>:> Deletes one character at cursor. Does nothing if no character at cursor.

B<C<Tab> or C<^I>:> Completes line automatically by history.

B<C<^D>:> Aborts the operation. Returns C<undef>.

=cut
use strict;
use warnings;
use v5.10.1;
use feature qw(switch);
no if ($] >= 5.018), 'warnings' => 'experimental';
require utf8;
require PerlIO;
require Term::ReadLine;
require Term::ReadKey;
require Term::Cap;


BEGIN
{
	require Exporter;
	our $VERSION     = '1.10';
	our @ISA         = qw(Exporter);
	our @EXPORT      = qw();
	our @EXPORT_OK   = qw();
}


=head1 STANDARD METHODS AND FUNCTIONS

=cut

=head2 ReadLine()

Returns the actual package that executes the commands. If this package is used, the value is C<Term::ReadLine::Tiny>.

=cut
sub ReadLine
{
	return __PACKAGE__;
}

=head2 new([$appname[, IN[, OUT]]])

Returns the handle for subsequent calls to following functions.
Argument I<appname> is the name of the application B<but not supported yet>.
Optionally can be followed by two arguments for IN and OUT filehandles. These arguments should be globs.

This routine may also get called via C<Term::ReadLine-E<gt>new()> if you have $ENV{PERL_RL} set to 'Tiny'.

=cut
sub new
{
	my $class = shift;
	my ($appname, $IN, $OUT) = @_;
	my $self = {};
	bless $self, $class;

	$self->{readmode} = '';
	$self->{history} = [];

	$self->{features} = {};
	#$self->{features}->{appname} = $appname;
	$self->{features}->{addhistory} = 1;
	$self->{features}->{minline} = 1;
	$self->{features}->{autohistory} = 1;
	$self->{features}->{gethistory} = 1;
	$self->{features}->{sethistory} = 1;
	$self->{features}->{changehistory} = 1;
	$self->{features}->{utf8} = 1;

	$self->newTTY($IN, $OUT);

	return $self;
}

sub DESTROY
{
	my $self = shift;
	if ($self->{readmode})
	{
		Term::ReadKey::ReadMode('restore', $self->{IN});
		$self->{readmode} = '';
	}
}

=head2 readline([$prompt[, $default]])

Interactively gets an input line. Trailing newline is removed.

Returns C<undef> on C<EOF> or error.

=cut
sub readline
{
	my $self = shift;
	my ($prompt, $default) = @_;
	$prompt = "" unless defined($prompt);
	$default = "" unless defined($default);
	my ($in, $out, $history, $minline, $changehistory) = 
		($self->{IN}, $self->{OUT}, $self->{history}, $self->{features}->{minline}, $self->{features}->{changehistory});
	unless (-t $in)
	{
		my $line = <$in>;
		chomp $line if defined $line;
		return $line;
	}

	my $termcap;
	eval {
		$termcap = Term::Cap->Tgetent();
	};
	return unless defined($termcap);
	my $term_autowrap = $termcap->{_am} && $termcap->{_xn} && 0;

	local $\ = undef;

	$self->{readmode} = 'cbreak';
	Term::ReadKey::ReadMode($self->{readmode}, $self->{IN});

	my @line;
	my ($line, $index) = ("", 0);
	my $history_index;
	my $ins_mode = 0;
	my ($row, $col);
	my ($width, $height) = Term::ReadKey::GetTerminalSize($out);

	my $autocomplete = $self->{autocomplete} || sub
	{
		for (my $i = $history_index; $i >= 0; $i--)
		{
			if ($history->[$i] =~ /^$line/)
			{
				return $history->[$i];
			}
		}
		return;
	};

	my $print = sub {
		my ($str) = @_;
		if ($term_autowrap)
		{
			print $out $str;
		} else
		{
			if ($str =~ /^\e/)
			{
				print $out $str;
			} else
			{
				for (my $i = 0; $i < length($str); $i++)
				{
					my $c = substr($str, $i, 1);
					unless ($c eq $termcap->{_bc})
					{
						print $out $c;
						unless ($col++ % $width)
						{
							print $out "\n";
							$row++ if $row < $height;
							$col = 1;
						}
					} else
					{
						if ($col > 1)
						{
							print $out $c;
							$col--;
						} else
						{
							$termcap->Tgoto('cm', ($col = $width) - 1, --$row - 1, $out);
						}
					}
				}
			}
		}
	};
	my $write = sub {
		my ($text, $ins) = @_;
		my $s;
		my @a = @line[$index..$#line];
		my $a = substr($line, $index);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		for my $c (split("", $text))
		{
			$s = encode_controlchar($c);
			unless ($ins)
			{
				$print->($s);
				push @line, $s;
				$line .= $c;
			} else
			{
				my $i = $index-length($line);
				$a[$i] = $s;
				substr($a, $i, 1) = $c;
			}
			$index++;
		}
		unless ($ins)
		{
			$s = join("", @a);
			$print->($s);
			$print->($termcap->{_bc} x length($s));
		} else
		{
			$s = join("", @a);
			$print->($s);
			$print->($termcap->{_bc} x (length($s) - length(join("", @a[0..length($text)-1]))));
		}
		push @line, @a;
		$line .= $a;
		if ($index >= length($line) and $term_autowrap)
		{
			$print->(" ");
			$print->("\e[D");
			$print->($termcap->{_cd});
		}
	};
	my $set = sub {
		my ($text) = @_;
		$print->($termcap->{_bc} x length(join("", @line[0..$index-1])));
		$print->($termcap->{_cd});
		@line = ();
		$line = "";
		$index = 0;
		$write->($text);
	};
	my $backspace = sub {
		return if $index <= 0;
		my @a = @line[$index..$#line];
		my $a = substr($line, $index);
		$index--;
		$print->($termcap->{_bc} x length($line[$index]));
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		$write->($a);
		$print->($termcap->{_bc} x length(join("", @a)));
		$index -= scalar(@a);
	};
	my $delete = sub {
		my @a = @line[$index+1..$#line];
		my $a = substr($line, $index+1);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		$write->($a);
		$print->($termcap->{_bc} x length(join("", @a)));
		$index -= scalar(@a);
	};
	my $home = sub {
		$print->($termcap->{_bc} x length(join("", @line[0..$index-1])));
		$index = 0;
	};
	my $end = sub {
		my @a = @line[$index..$#line];
		my $a = substr($line, $index);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		$write->($a);
	};
	my $left = sub {
		return if $index <= 0;
		$print->($termcap->{_bc} x length($line[$index-1]));
		$index--;
	};
	my $right = sub {
		return if $index >= length($line);
		$print->($line[$index]);
		$index++;
		unless ($index >= length($line))
		{
			$print->($line[$index]);
			$print->($termcap->{_bc} x length($line[$index]));
		}
	};
	my $up = sub {
		return if $history_index <= 0;
		$history->[$history_index] = $line if $changehistory;
		$history_index--;
		$set->($history->[$history_index]);
	};
	my $down = sub {
		return if $history_index >= $#$history;
		$history->[$history_index] = $line if $changehistory;
		$history_index++;
		$set->($history->[$history_index]);
	};
	my $pageup = sub {
		return if $history_index <= 0;
		$history->[$history_index] = $line if $changehistory;
		$history_index = 0;
		$set->($history->[$history_index]);
	};
	my $pagedown = sub {
		return if $history_index >= $#$history;
		$history->[$history_index] = $line if $changehistory;
		$history_index = $#$history;
		$set->($history->[$history_index]);
	};

	print $out $prompt;
	#$set->($default);
	push @$history, $line;
	$history_index = $#$history;

	print $out "\e[6n";

	my $result = undef;
	my ($char, $esc) = ("", undef);
	while (defined($char = getc($in)))
	{
		unless (defined($esc))
		{
			given ($char)
			{
				when (/\e/)
				{
					$esc = "\e";
				}
				when (/\x01/)	# ^A
				{
					$home->();
				}
				when (/\x04/)	# ^D
				{
					$result = undef;
					last;
				}
				when (/\x05/)	# ^E
				{
					$end->();
				}
				when (/\t/)	# ^I
				{
					my $newline = $autocomplete->($self, $line, $history_index, $index);
					$set->($newline) if defined $newline;
				}
				when (/\n|\r/)
				{
					$print->($char);
					$history->[$#$history] = $line;
					pop @$history unless defined($minline) and length($line) >= $minline;
					$result = $line;
					last;
				}
				when (/[\b]|\x7F|\Q$termcap->{_kb}\E/)
				{
					$backspace->();
				}
				when (/[\x00-\x1F]|\x7F/)
				{
					$write->($char, $ins_mode);
				}
				default
				{
					$write->($char, $ins_mode);
				}
			}
			next;
		}
		$esc .= $char;
		if ($esc =~ /^\e.(\d+|\d+;\d+)?[^\d;]/)
		{
			given ($esc)
			{
				when (/^(\e(\[|O)(A|0A))|\Q$termcap->{_ku}\E/)
				{
					$up->();
				}
				when (/^(\e(\[|O)(B|0B))|\Q$termcap->{_kd}\E/)
				{
					$down->();
				}
				when (/^(\e(\[|O)(C|0C))|\Q$termcap->{_kr}\E/)
				{
					$right->();
				}
				when (/^(\e(\[|O)(D|0D))|\Q$termcap->{_kl}\E/)
				{
					$left->();
				}
				when (/^(\e(\[|O)(F|0F))|(\e\[4~)|(\e\[8~)/)
				{
					$end->();
				}
				when (/^(\e(\[|O)(H|0H))|(\e\[1~)|(\e\[7~)|\Q$termcap->{_kh}\E/)
				{
					$home->();
				}
				when (/^(\e\[2~)|\Q$termcap->{_kI}\E/)
				{
					$ins_mode = not $ins_mode;
				}
				when (/^(\e\[3~)|\Q$termcap->{_kD}\E/)
				{
					$delete->();
				}
				when (/^(\e\[5~)|\Q$termcap->{_kP}\E/)
				{
					$pageup->();
				}
				when (/^(\e\[6~)|\Q$termcap->{_kN}\E/)
				{
					$pagedown->();
				}
				when (/^\e\[(\d+)~/)
				{
				}
				when (/^\e\[(\d+);(\d+)R/)
				{
					$row = $1;
					$col = $2;
				}
				default
				{
					#$write->($char, $ins_mode);
				}
			}
			$esc = undef;
		}
	}
	utf8::encode($result) if defined($result) and utf8::is_utf8($result) and $self->{features}->{utf8};

	Term::ReadKey::ReadMode('restore', $self->{IN});
	$self->{readmode} = '';
	return $result;
}

=head2 addhistory($line1[, $line2[, ...]])

B<AddHistory($line1[, $line2[, ...]])>

Adds lines to the history of input.

=cut
sub addhistory
{
	my $self = shift;
	if (grep(":utf8", PerlIO::get_layers($self->{IN})))
	{
		for (my $i = 0; $i < @_; $i++)
		{
			utf8::decode($_[$i]);
		}
	}
	push @{$self->{history}}, @_;
	return (@_);
}
sub AddHistory
{
	return addhistory(@_);
}

=head2 IN()

Returns the filehandle for input.

=cut
sub IN
{
	my $self = shift;
	return $self->{IN};
}

=head2 OUT()

Returns the filehandle for output.

=cut
sub OUT
{
	my $self = shift;
	return $self->{OUT};
}

=head2 MinLine([$minline])

B<minline([$minline])>

If argument is specified, it is an advice on minimal size of line to be included into history.
C<undef> means do not include anything into history (autohistory off).

Returns the old value.

=cut
sub MinLine
{
	my $self = shift;
	my ($minline) = @_;
	my $result = $self->{features}->{minline};
	$self->{features}->{minline} = $minline if @_ >= 1;
	$self->{features}->{autohistory} = defined($self->{features}->{minline});
	return $result;
}
sub minline
{
	return MinLine(@_);
}

=head2 findConsole()

B<findconsole()>

Returns an array with two strings that give most appropriate names for files for input and output using conventions C<"<$in">, C<">out">.

=cut
sub findConsole
{
	return (Term::ReadLine::Stub::findConsole(@_));
}
sub findconsole
{
	return findConsole(@_);
}

=head2 Attribs()

B<attribs()>

Returns a reference to a hash which describes internal configuration of the package. B<Not supported in this package.>

=cut
sub Attribs
{
	return {};
}
sub attribs
{
	return Attribs(@_);
}

=head2 Features()

B<features()>

Returns a reference to a hash with keys being features present in current implementation.
This features are present:

=over

=item *

I<appname> is not present and is the name of the application. B<But not supported yet.>

=item *

I<addhistory> is present, always C<TRUE>.

=item *

I<minline> is present, default 1. See C<MinLine> method.

=item *

I<autohistory> is present. C<FALSE> if minline is C<undef>. See C<MinLine> method.

=item *

I<gethistory> is present, always C<TRUE>.

=item *

I<sethistory> is present, always C<TRUE>.

=item *

I<changehistory> is present, default C<TRUE>. See C<changehistory> method.

=item *

I<utf8> is present, default C<TRUE>. See C<utf8> method.

=back

=cut
sub Features
{
	my $self = shift;
	my %features = %{$self->{features}};
	return \%features;
}
sub features
{
	return Features(@_);
}

=head1 ADDITIONAL METHODS AND FUNCTIONS

=cut

=head2 newTTY([$IN[, $OUT]])

takes two arguments which are input filehandle and output filehandle. Switches to use these filehandles.

=cut
sub newTTY
{
	my $self = shift;
	my ($IN, $OUT) = @_;

	my ($console, $consoleOUT) = findConsole();
	my $console_utf8 = defined($ENV{LANG}) && $ENV{LANG} =~ /\.UTF\-?8$/i;
	my $console_layers = "";
	$console_layers .= " :utf8" if $console_utf8;

	my $in;
	$in = $IN if ref($IN) eq "GLOB";
	$in = \$IN if ref(\$IN) eq "GLOB";
	open($in, "<$console_layers", $console) unless defined($in);
	$in = \*STDIN unless defined($in);
	$self->{IN} = $in;

	my $out;
	$out = $OUT if ref($OUT) eq "GLOB";
	$out = \$OUT if ref(\$OUT) eq "GLOB";
	open($out, ">$console_layers", $consoleOUT) unless defined($out);
	$out = \*STDOUT unless defined($out);
	$self->{OUT} = $out;

	return ($self->{IN}, $self->{OUT});
}

=head2 ornaments

This is void implementation. Ornaments is B<not supported>.

=cut
sub ornaments
{
	return;
}

=head2 gethistory()

B<GetHistory()>

Returns copy of the history in Array.

=cut
sub gethistory
{
	my $self = shift;
	my @result = @{$self->{history}};
	if ($self->{features}->{utf8})
	{
		for (my $i = 0; $i < @result; $i++)
		{
			utf8::encode($result[$i]) if utf8::is_utf8($result[$i]);
		}
	}
	return @result;
}
sub GetHistory
{
	return gethistory(@_);
}

=head2 sethistory($line1[, $line2[, ...]])

B<SetHistory($line1[, $line2[, ...]])>

rewrites all history by argument values.

=cut
sub sethistory
{
	my $self = shift;
	if (grep(":utf8", PerlIO::get_layers($self->{IN})))
	{
		for (my $i = 0; $i < @_; $i++)
		{
			utf8::decode($_[$i]);
		}
	}
	@{$self->{history}} = @_;
	return 1;
}
sub SetHistory
{
	return sethistory(@_);
}

=head1 NON-STANDARD METHODS AND FUNCTIONS

=cut

=head2 changehistory([$changehistory])

If argument is specified, it allows to change history lines when argument value is true.

Returns the old value.

=cut
sub changehistory
{
	my $self = shift;
	my ($changehistory) = @_;
	my $result = $self->{features}->{changehistory};
	$self->{features}->{changehistory} = $changehistory if @_ >= 1;
	return $result;
}

=head1 Other Methods and Functions

=cut

=head2 readkey([$echo])

reads a key from input and echoes if I<echo> argument is C<TRUE>.

Returns C<undef> on C<EOF>.

=cut
sub readkey
{
	my $self = shift;
	my ($echo) = @_;
	my ($in, $out) = 
		($self->{IN}, $self->{OUT});
	unless (-t $in)
	{
		return getc($in);
	}
	local $\ = undef;

	$self->{readmode} = 'cbreak';
	Term::ReadKey::ReadMode($self->{readmode}, $self->{IN});

	my $result;
	my ($char, $esc) = ("", undef);
	while (defined($char = getc($in)))
	{
		unless (defined($esc))
		{
			given ($char)
			{
				when (/\e/)
				{
					$esc = "";
				}
				when (/\x04/)
				{
					$result = undef;
					last;
				}
				default
				{
					print $out encode_controlchar($char) if $echo;
					$result = $char;
					last;
				}
			}
			next;
		}
		$esc .= $char;
		if ($esc =~ /^.\d?\D/)
		{
			$result = "\e$esc";
			$esc = undef;
			last;
		}
	}
	utf8::encode($result) if defined($result) and utf8::is_utf8($result) and $self->{features}->{utf8};

	Term::ReadKey::ReadMode('restore', $self->{IN});
	$self->{readmode} = '';
	return $result;
}

=head2 utf8([$enable])

If C<$enable> is C<TRUE>, all read methods return that binary encoded UTF-8 string as possible.

Returns the old value.

=cut
sub utf8
{
	my $self = shift;
	my ($enable) = @_;
	my $result = $self->{features}->{utf8};
	$self->{features}->{utf8} = $enable if @_ >= 1;
	return $result;
}

=head2 encode_controlchar($c)

encodes if first character of argument C<$c> is a control character,
otherwise returns first character of argument C<$c>.

Example: "\n" is ^J.

=cut
sub encode_controlchar
{
	my ($c) = @_;
	$c = substr($c, 0, 1);
	my $s;
	given ($c)
	{
		when (/[\x00-\x1F]/)
		{
			$s = "^".chr(0x40+ord($c));
		}
		when ($c =~ /[\x7F]/)
		{
			$s = "^".chr(0x3F);
		}
		default
		{
			$s = $c;
		}
	}
	return $s;
}

=head2 autocomplete($coderef)

Sets a coderef to be used to autocompletion. If C<< $coderef >> is undef,
will restore default behaviour.

The coderef will be called like C<< $coderef->($term, $line, $history_index, $line_position) >>,
where C<< $line >> is the existing line, C<< $history_index >> is the current
location in the history, and C<< $line_position >> is the position if the cursor.

It should return the completed line, or undef if completion fails.

=cut
sub autocomplete
{
	my $self = shift;
	$self->{autocomplete} = $_[0] if @_;
}


1;
__END__
=head1 UTF-8

C<Term::ReadLine::Tiny> fully supports UTF-8. If no input/output file handle specified when calling C<new()> or C<newTTY()>,
opens console input/output file handles with C<:utf8> layer by C<LANG> environment variable. You should set C<:utf8>
layer explicitly, if input/output file handles specified with C<new()> or C<newTTY()>.

	$term = Term::ReadLine::Tiny->new("", $in, $out);
	binmode($term->IN, ":utf8");
	binmode($term->OUT, ":utf8");
	$term->utf8(0); # to get UTF-8 marked string as possible
	while ( defined($_ = $term->readline("Prompt: ")) )
	{
		print "$_\n";
	}
	print "\n";

=head1 KNOWN BUGS

=over

=item *

Cursor doesn't move to new line at end of terminal line on some native terminals.

=back

=head1 SEE ALSO

=over

=item *

L<Term::ReadLine::Tiny::readline|https://metacpan.org/pod/Term::ReadLine::Tiny::readline> - A non-OO package of Term::ReadLine::Tiny

=item *

L<Term::ReadLine|https://metacpan.org/pod/Term::ReadLine> - Perl interface to various readline packages

=back

=head1 INSTALLATION

To install this module type the following

	perl Makefile.PL
	make
	make test
	make install

from CPAN

	cpan -i Term::ReadLine::Tiny

=head1 DEPENDENCIES

This module requires these other modules and libraries:

=over

=item *

Term::ReadLine

=item *

Term::ReadKey

=back

=head1 REPOSITORY

B<GitHub> L<https://github.com/orkunkaraduman/p5-Term-ReadLine-Tiny>

B<CPAN> L<https://metacpan.org/release/Term-ReadLine-Tiny>

=head1 AUTHOR

Orkun Karaduman (ORKUN) <orkun@cpan.org>

=head1 CONTRIBUTORS

=over

=item *

Adriano Ferreira (FERREIRA) <ferreira@cpan.org>

=item *

Toby Inkster (TOBYINK) <tobyink@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2017  Orkun Karaduman <orkunkaraduman@gmail.com>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
