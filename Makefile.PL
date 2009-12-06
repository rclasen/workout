use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Workout',
    VERSION_FROM      => 'lib/Workout.pm',
    PREREQ_PM         => {
	    # update debian/control, too!
	    'Geo::Distance'	=> undef,
	    'XML::SAX'	=> undef,
	    'Class::Accessor::Fast'	=> undef,
	    'Module::Pluggable'	=> undef,
	    'DateTime'		=> undef,
	    'MyChart'		=> '0.03',
	    'Encode'		=> undef,
    }, # e.g., Module::Name => 1.1
    'EXE_FILES'       => [qw(
	wkconv
	wkdelta
	wkdist
	wkdump
	wkhisto
	wkinfo
	wkmerge
	wkmodify
	wkplot
	wkpmc
	wksum
    )],
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Workout.pm', # retrieve abstract from module
       AUTHOR         => 'Rainer Clasen') : ()),
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
