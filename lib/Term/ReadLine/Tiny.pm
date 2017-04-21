package Term::ReadLine::Tiny;
=head1 NAME

Term::ReadLine::Tiny - Tiny readline package

=head1 VERSION

version 1.00

=head1 SYNOPSIS

Tiny readline package

	use Term::ReadLine::Tiny;

	my $term = Term::ReadLine::Tiny->new();
	while ( defined($_ = $term->readline("Prompt: ")) )
	{
		print "$_\n";
	}

=head1 DESCRIPTION

Tiny readline package

=cut
use strict;
use warnings;
use v5.10.1;
use feature qw(switch);
no if ($] >= 5.018), 'warnings' => 'experimental';
require Term::ReadKey;


BEGIN
{
	require Exporter;
	our $VERSION     = '1.00';
	our @ISA         = qw(Exporter);
	our @EXPORT      = qw();
	our @EXPORT_OK   = qw();
}


sub ReadLine
{
	return __PACKAGE__;
}

sub new
{
	my $class = shift;
	my ($appname, $IN, $OUT) = @_;
	my $self = {};
	bless $self, $class;

	my ($console, $consoleOUT) = findConsole();
	my $in = $IN if ref($IN) eq "GLOB";
	$in = \$IN if ref(\$IN) eq "GLOB";
	open($in, '<', $console) unless defined($in);
	$in = \*STDIN unless defined($in);
	$self->{IN} = $in;
	my $out = $OUT if ref($OUT) eq "GLOB";
	$out = \$OUT if ref(\$OUT) eq "GLOB";
	open($out, '>', $consoleOUT) unless defined($out);
	$out = \*STDOUT unless defined($out);
	$self->{OUT} = $out;

	$self->{readmode} = '';
	$self->{history} = [];

	$self->{features} = {};
	#$self->{features}->{appname} = $appname if defined($appname);
	$self->{features}->{addhistory} = 1;
	$self->{features}->{minline} = 1;
	$self->{features}->{autohistory} = 1;
	$self->{features}->{changehistory} = 1;

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

sub readline
{
	my $self = shift;
	my ($prompt, $default) = @_;
	$prompt = "" unless defined($prompt);
	$default = "" unless defined($default);
	my ($in, $out, $history, $minline, $autohistory, $changehistory) = 
		($self->{IN}, $self->{OUT}, $self->{history}, $self->{features}->{minline}, $self->{features}->{autohistory}, $self->{features}->{changehistory});
	unless (-t $in)
	{
		my $line = <$in>;
		chomp $line if defined $line;
		return $line;
	}
	local $\ = undef;

	$self->{readmode} = 'cbreak';
	Term::ReadKey::ReadMode($self->{readmode}, $self->{IN});

	my $result;
	my @line;
	my ($line, $index) = ("", 0);
	my $history_index;
	my $ins_mode = 0;

	my $write = sub {
		my ($text, $ins) = @_;
		my $s;
		my @a = @line[$index..$#line];
		my $a = substr($line, $index);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		print $out "\e[J";
		for my $c (split("", $text))
		{
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
			unless ($ins)
			{
				print $out $s;
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
			print $out $s;
			print $out "\e[D" x length($s);
		} else
		{
			$s = join("", @a);
			print $out $s;
			print $out "\e[D" x (length($s) - length(join("", @a[0..length($text)-1])));
		}
		push @line, @a;
		$line .= $a;
	};
	my $print = sub {
		my ($text) = @_;
		$write->($text, $ins_mode);
	};
	my $set = sub {
		my ($text) = @_;
		print $out "\e[D" x length(join("", @line));
		print $out "\e[J";
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
		print $out "\e[D" x length($line[$index]);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		$write->($a);
		print $out "\e[D" x length(join("", @a));
		$index -= scalar(@a);
	};
	my $delete = sub {
		my @a = @line[$index+1..$#line];
		my $a = substr($line, $index+1);
		@line = @line[0..$index-1];
		$line = substr($line, 0, $index);
		$write->($a);
		print $out "\e[D" x length(join("", @a));
		$index -= scalar(@a);
	};
	my $home = sub {
		print $out "\e[D" x length(join("", @line[0..$index-1]));
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
		print $out "\e[D" x length($line[$index-1]);
		$index--;
	};
	my $right = sub {
		return if $index >= length($line);
		print $out $line[$index];
		$index++;
	};
	my $up = sub {
		return if $history_index <= 0;
		$history->[$history_index] = $line if length($line) >= $minline and $changehistory;
		$history_index--;
		$set->($history->[$history_index]);
	};
	my $down = sub {
		return if $history_index >= $#$history;
		$history->[$history_index] = $line if length($line) >= $minline and $changehistory;
		$history_index++;
		$set->($history->[$history_index]);
	};
	my $pageup = sub {
		return if $history_index <= 0;
		$history->[$history_index] = $line if length($line) >= $minline and $changehistory;
		$history_index = 0;
		$set->($history->[$history_index]);
	};
	my $pagedown = sub {
		return if $history_index >= $#$history;
		$history->[$history_index] = $line if length($line) >= $minline and $changehistory;
		$history_index = $#$history;
		$set->($history->[$history_index]);
	};

	print $prompt;
	$set->($default);
	push @$history, $line;
	$history_index = $#$history;

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
				when (/\t/)
				{
				}
				when (/\x04/)
				{
					$result = undef;
					last;
				}
				when (/\n|\r/)
				{
					print $out $char;
					$history->[$#$history] = $line;
					pop $history unless length($line) >= $minline and $autohistory;
					$result = $line;
					last;
				}
				when (/[\b]|\x7F/)
				{
					$backspace->();
				}
				when (/[\x00-\x1F]|\x7F/)
				{
					$print->($char);
				}
				default
				{
					$print->($char);
				}
			}
			next;
		}
		$esc .= $char;
		if ($esc =~ /^.\d?\D/)
		{
			given ($esc)
			{
				when (/^\[(A|0A)/)
				{
					$up->();
				}
				when (/^\[(B|0B)/)
				{
					$down->();
				}
				when (/^\[(C|0C)/)
				{
					$right->();
				}
				when (/^\[(D|0D)/)
				{
					$left->();
				}
				when (/^\[(H|OH)/)
				{
					$home->();
				}
				when (/^\[(F|0F)/)
				{
					$end->();
				}
				when (/^\[(\d)~/)
				{
					given ($1)
					{
						when (1)
						{
							$home->();
						}
						when (2)
						{
							$ins_mode = not $ins_mode;
						}
						when (3)
						{
							$delete->();
						}
						when (4)
						{
							$end->();
						}
						when (5)
						{
							$pageup->();
						}
						when (6)
						{
							$pagedown->();
						}
						when (7)
						{
							$home->();
						}
						when (8)
						{
							$end->();
						}
						default
						{
							#$print->("\e$esc");
						}
					}
				}
				default
				{
					#$print->("\e$esc");
				}
			}
			$esc = undef;
		}
	}

	Term::ReadKey::ReadMode('restore', $self->{IN});
	$self->{readmode} = '';
	return $result;
}

sub addhistory
{
	my $self = shift;
	push @{$self->{history}}, @_;
	return (@_);
}

sub IN
{
	my $self = shift;
	return $self->{IN};
}

sub OUT
{
	my $self = shift;
	return $self->{OUT};
}

sub MinLine
{
	my $self = shift;
	my ($minline) = @_;
	$self->{features}->{minline} = $minline if defined($minline);
	return $self->{features}->{minline};
}

sub findConsole
{
	my ($console, $consoleOUT);
 
	if (-e "/dev/tty" and $^O ne 'MSWin32') {
		$console = "/dev/tty";
	} elsif (-e "con" or $^O eq 'MSWin32' or $^O eq 'msys') {
	   $console = 'CONIN$';
	   $consoleOUT = 'CONOUT$';
	} elsif ($^O eq 'VMS') {
		$console = "sys\$command";
	} elsif ($^O eq 'os2' && !$DB::emacs) {
		$console = "/dev/con";
	} else {
		$console = undef;
	}
 
	$consoleOUT = $console unless defined $consoleOUT;
	$console = "&STDIN" unless defined $console;
	if ($console eq "/dev/tty" && !open(my $fh, "<", $console)) {
	  $console = "&STDIN";
	  undef($consoleOUT);
	}
	if (!defined $consoleOUT) {
	  $consoleOUT = defined fileno(STDERR) && $^O ne 'MSWin32' ? "&STDERR" : "&STDOUT";
	}
	return ($console, $consoleOUT);
}

sub Attribs
{
	return {};
}

sub Features
{
	my $self = shift;
	my %features = %{$self->{features}};
	return \%features;
}

sub autohistory
{
	my $self = shift;
	my ($autohistory) = @_;
	$self->{features}->{autohistory} = $autohistory if defined($autohistory);
	return $self->{features}->{autohistory};
}

sub changehistory
{
	my $self = shift;
	my ($changehistory) = @_;
	$self->{features}->{changehistory} = $changehistory if defined($changehistory);
	return $self->{features}->{changehistory};
}

sub history
{
	my $self = shift;
	if (@_ > 0)
	{
		if (ref($_[0]) eq "ARRAY")
		{
			@{$self->{history}} = @{$_[0]};
		} else
		{
			@{$self->{history}} = @_;
		}
	}
	my @history = @{$self->{history}};
	return \@history;
}


1;
__END__
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

Term::ReadKey

=back

=head1 REPOSITORY

B<GitHub> L<https://github.com/orkunkaraduman/p5-Term-ReadLine-Tiny>

B<CPAN> L<https://metacpan.org/release/Term-ReadLine-Tiny>

=head1 AUTHOR

Orkun Karaduman <orkunkaraduman@gmail.com>

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
