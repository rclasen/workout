use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Workout',
    VERSION      => '0.07',
    PREREQ_PM         => {
	    'Geo::Distance'	=> undef,
	    'Geo::Gpx'	=> undef,
	    'Class::Accessor::Fast'	=> undef,
	    'Module::Pluggable'	=> undef,
	    'DateTime'		=> undef,
    }, # e.g., Module::Name => 1.1
    'EXE_FILES'       => [qw(
	wkconv
	wkdelta
	wkdump
	wkinfo
	wkmerge
	wkmodify
	wkplot
	wkpmc
    )],
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Workout.pm', # retrieve abstract from module
       AUTHOR         => 'Rainer Clasen') : ()),
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
