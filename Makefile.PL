use ExtUtils::MakeMaker;
WriteMakefile( NAME         => "Test::Builder::Tester",
               VERSION_FROM => "lib/Test/Builder/Tester.pm",
               PREREQ_PM    => { Test::Builder => 0.12 },
);

 
