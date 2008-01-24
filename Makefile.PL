use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Workout',
    VERSION_FROM      => 'lib/Workout/Store.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    'EXE_FILES'       => [qw(
	        wkdump
		wkconv
    )],
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Workout/Store.pm', # retrieve abstract from module
       AUTHOR         => 'Rainer Clasen') : ()),
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
