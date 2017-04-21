use strict;
use warnings;
use ExtUtils::MakeMaker;


WriteMakefile(
	NAME				=> 'Term::ReadLine::Tiny',
	VERSION_FROM		=> 'lib/Term/ReadLine/Tiny.pm',
	MIN_PERL_VERSION	=> '5.010001',
	PREREQ_PM			=> {
		'Term::ReadKey'	=> '2.33',
	},
	EXE_FILES			=> [qw(
	)],
	AUTHOR				=> 'Orkun Karaduman <orkunkaraduman@gmail.com>',
	ABSTRACT			=> 'Tiny readline package',
	LICENSE				=> 'gpl_3',
	META_MERGE			=> {
		'meta-spec'		=> {
			version		=> 2,
		},
		resources		=> {
			homepage	=> 'https://metacpan.org/release/Term-ReadLine-Tiny',
			license		=> 'https://www.gnu.org/licenses/gpl-3.0.html',
			repository	=> {
				type	=> 'git',
				url		=> 'git://git@github.com:orkunkaraduman/p5-Term-ReadLine-Tiny.git',
				web		=> 'https://github.com/orkunkaraduman/p5-Term-ReadLine-Tiny',
			},
			bugtracker => {
				web    => 'https://github.com/orkunkaraduman/p5-Term-ReadLine-Tiny/issues',
				mailto => 'bug-Term-ReadLine-Tiny@rt.cpan.org',
			},
		},
	},
);
