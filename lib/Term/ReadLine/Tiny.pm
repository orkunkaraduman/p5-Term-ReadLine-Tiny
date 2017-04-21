package Term::ReadLine::Tiny;
=head1 NAME

Term::ReadLine::Tiny - Tiny readline package

=head1 VERSION

version 1.00

=head1 SYNOPSIS

Tiny readline package

	use Term::ReadLine::Tiny;

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
	our @EXPORT_OK   = qw(readline);
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

	$self->{history} = [];

	$self->{features} = {};
	#$self->{features}->{appname} = $appname if defined($appname);
	$self->{features}->{addhistory} = 1;
	$self->{features}->{minline} = 1;
	$self->{features}->{autohistory} = 1;
	$self->{features}->{changehistory} = 1;

	return $self;
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

	my $old_sigint = $SIG{INT};
	local $SIG{INT} = sub {
		Term::ReadKey::ReadMode('restore', $in);
		if (defined($old_sigint))
		{
			$old_sigint->();
		} else
		{
			print "\n";
			exit 130;
		}
	};
	my $old_sigterm = $SIG{TERM};
	local $SIG{TERM} = sub {
		Term::ReadKey::ReadMode('restore', $in);
		if (defined($old_sigterm))
		{
			$old_sigterm->();
		} else
		{
			print "\n";
			exit 143;
		}
	};
	Term::ReadKey::ReadMode('cbreak', $in);

	my ($line, $index, $history_index) = ("", 0);

	my $write = sub {
		my ($text) = @_;
		my $s;
		$s = "";
		for my $c (split(/(.)/, $text))
		{
			given ($c)
			{
				when (/[\x00-\x1F]/)
				{
					$c = "^".chr(0x40+ord($c));
				}
				when ($c =~ /[\x7F]/)
				{
					$c = "^".chr(0x3F);
				}
			}
			$s .= $c;
		}
		$text = $s;
		substr($line, $index) = $text.substr($line, $index);
		$index += length($text);
		$s = substr($line, $index);
		print $out "\e[J";
		print $out $text;
		print $out $s;
		print $out "\e[D" x length($s);
	};
	my $set = sub {
		my ($text) = @_;
		print $out "\e[D" x $index;
		print $out "\e[J";
		$index = 0;
		$line = "";
		$write->($text);
	};
	my $backspace = sub {
		my $s;
		return if $index <= 0;
		$index--;
		substr($line, $index, 1) = "";
		$s = substr($line, $index);
		print $out "\e[D\e[J";
		print $out $s;
		print $out "\e[D" x length($s);
	};
	my $delete = sub {
		my $s;
		substr($line, $index, 1) = "";
		$s = substr($line, $index);
		print $out "\e[J";
		print $out $s;
		print $out "\e[D" x length($s);
	};
	my $home = sub {
		print $out "\e[D" x $index;
		$index = 0;
	};
	my $end = sub {
		my $s;
		$s = substr($line, $index);
		$index += length($s);
		print $out "\e[J";
		print $out $s;
	};
	my $left = sub {
		return if $index <= 0;
		print $out "\e[D";
		$index--;
	};
	my $right = sub {
		return if $index >= length($line);
		print $out substr($line, $index, 1);
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
				when (/\n|\r/)
				{
					print $out $char;
					$history->[$#$history] = $line;
					pop $history unless length($line) >= $minline and $autohistory;
					last;
				}
				when (/[\b]|\x7F/)
				{
					$backspace->();
				}
				when (/[\x00-\x1F]|\x7F/)
				{
				}
				default
				{
					$write->($char);
				}
			}
			next;
		}
		$esc .= $char;
		if ($esc =~ /^.\d?\D/)
		{
			given ($esc)
			{
				when (/^\[A/)
				{
					$up->();
				}
				when (/^\[B/)
				{
					$down->();
				}
				when (/^\[C/)
				{
					$right->();
				}
				when (/^\[D/)
				{
					$left->();
				}
				when (/^\[H/)
				{
					$home->();
				}
				when (/^\[F/)
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
							#insert
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
							#pageup
						}
						when (6)
						{
							#pagedown
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
							#$write->("\e$esc");
						}
					}
				}
				default
				{
					#$write->("\e$esc");
				}
			}
			$esc = undef;
		}
	}
	Term::ReadKey::ReadMode('restore', $in);
	return $line;
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
